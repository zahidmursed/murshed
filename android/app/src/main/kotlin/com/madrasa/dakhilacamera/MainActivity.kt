package com.madrasa.dakhilacamera

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {

    /// Dart side: lib/utils/gallery_saver.dart
    private val channelName = "dakhila_camera/gallery"
    private val albumName = "DakhilaCamera"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToGallery" -> {
                        val path = call.argument<String>("path")
                        val fileName = call.argument<String>("fileName")
                        if (path == null || fileName == null) {
                            result.error("INVALID_ARGS", "path and fileName required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveToGallery(path, fileName))
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    "deleteFromGallery" -> {
                        val fileName = call.argument<String>("fileName")
                        if (fileName == null) {
                            result.error("INVALID_ARGS", "fileName required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(deleteFromGallery(fileName))
                        } catch (e: Exception) {
                            result.error("DELETE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun imageCollection(): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

    private fun relativePath(): String = "Pictures/$albumName"

    /// ছবিটি গ্যালারিতে (Pictures/DakhilaCamera) সেভ করে।
    /// একই নামের আগের এন্ট্রি আগে মুছে ফেলে — retake-এ ডুপ্লিকেট হয় না।
    private fun saveToGallery(srcPath: String, fileName: String): String? {
        val resolver = applicationContext.contentResolver
        deleteFromGallery(fileName)

        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, relativePath())
                put(MediaStore.Images.Media.IS_PENDING, 1)
            } else {
                // Android 9-: সরাসরি public Pictures ফোল্ডারে লেখা
                // (WRITE_EXTERNAL_STORAGE manifest-এ আছে; runtime grant না থাকলে SecurityException)
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    albumName
                )
                if (!dir.exists()) dir.mkdirs()
                put(MediaStore.Images.Media.DATA, File(dir, fileName).absolutePath)
            }
        }

        val uri = resolver.insert(imageCollection(), values)
            ?: throw IllegalStateException("MediaStore insert returned null")

        val out = resolver.openOutputStream(uri)
            ?: throw IllegalStateException("OutputStream is null")
        FileInputStream(srcPath).use { input ->
            out.use { output -> input.copyTo(output) }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
        return uri.toString()
    }

    /// নিজের সেভ করা (same album+name) এন্ট্রি মুছে দেয়।
    /// Android 10+: নিজের contribute করা ফাইলে permission লাগে না।
    private fun deleteFromGallery(fileName: String): Int {
        val resolver = applicationContext.contentResolver
        val selection: String
        val selectionArgs: Array<String>
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            selection =
                "${MediaStore.Images.Media.RELATIVE_PATH}=? AND ${MediaStore.Images.Media.DISPLAY_NAME}=?"
            selectionArgs = arrayOf(relativePath(), fileName)
        } else {
            selection =
                "${MediaStore.Images.Media.DATA} LIKE ? AND ${MediaStore.Images.Media.DISPLAY_NAME}=?"
            selectionArgs = arrayOf("%${relativePath()}%", fileName)
        }
        return resolver.delete(imageCollection(), selection, selectionArgs)
    }
}