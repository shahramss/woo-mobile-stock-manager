package com.wmsm.app

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterFragmentActivity() {
    private val channelName = "modiriat_sari/gallery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "savePngToGallery") {
                try {
                    val bytes = call.argument<ByteArray>("bytes")
                    val rawFileName = call.argument<String>("fileName") ?: "invoice.png"
                    val fileName = if (rawFileName.endsWith(".png")) rawFileName else "$rawFileName.png"

                    if (bytes == null || bytes.isEmpty()) {
                        result.error("EMPTY_FILE", "فایل فاکتور خالی است.", null)
                        return@setMethodCallHandler
                    }

                    val uriString = savePng(bytes, fileName)
                    result.success(uriString)
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message ?: "ذخیره فاکتور انجام نشد.", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun savePng(bytes: ByteArray, fileName: String): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/ModiriatSari")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }

            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("امکان ساخت فایل در گالری وجود ندارد.")

            resolver.openOutputStream(uri)?.use { output ->
                output.write(bytes)
                output.flush()
            } ?: throw Exception("امکان نوشتن فایل فاکتور وجود ندارد.")

            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            uri.toString()
        } else {
            val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            val appDir = File(picturesDir, "ModiriatSari")
            if (!appDir.exists()) appDir.mkdirs()
            val file = File(appDir, fileName)
            file.writeBytes(bytes)
            MediaScannerConnection.scanFile(applicationContext, arrayOf(file.absolutePath), arrayOf("image/png"), null)
            file.absolutePath
        }
    }
}
