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
