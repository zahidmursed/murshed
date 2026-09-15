package com.madrasa.dakhilacamera

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {

    /// Dart side: lib/utils/gallery_saver.dart
    private val channelName = "dakhila_camera/gallery"
    private val albumName = "DakhilaCamera"
    private var galleryReadResult: MethodChannel.Result? = null

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
                    "shareFile" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mime") ?: "*/*"
                        if (path == null) {
                            result.error("INVALID_ARGS", "path required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(shareFile(path, mime))
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                    "copyGalleryPhoto" -> {
                        val fileName = call.argument<String>("fileName")
                        val destPath = call.argument<String>("destPath")
                        if (fileName == null || destPath == null) {
                            result.error("INVALID_ARGS", "fileName and destPath required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(copyGalleryPhoto(fileName, destPath))
                        } catch (e: Exception) {
                            result.error("COPY_FAILED", e.message, null)
                        }
                    }
                    "listGalleryPhotos" -> {
                        // পুরনো ছবি রিকভারি: গ্যালারিতে এই অ্যালবামের ফাইলনামগুলো
                        if (hasImageReadPermission()) {
                            result.success(galleryFileNames())
                        } else {
                            // runtime permission চাই — ফলাফল onRequestPermissionsResult-এ
                            galleryReadResult = result
                            requestImageReadPermission()
                        }
                    }
                    "viewFile" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mime") ?: "*/*"
                        if (path == null) {
                            result.error("INVALID_ARGS", "path required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(viewFile(path, mime))
                        } catch (e: Exception) {
                            result.error("VIEW_FAILED", e.message, null)
                        }
                    }
                    "shareText" -> {
                        val text = call.argument<String>("text") ?: ""
                        try {
                            result.success(shareText(text))
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 2001) {
            val granted =
                grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            galleryReadResult?.let { pending ->
                if (granted) pending.success(galleryFileNames())
                else pending.error("PERMISSION_DENIED", "Storage permission denied", null)
            }
            galleryReadResult = null
        }
    }

    private fun hasImageReadPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(android.Manifest.permission.READ_MEDIA_IMAGES) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun requestImageReadPermission() {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            android.Manifest.permission.READ_MEDIA_IMAGES
        } else {
            android.Manifest.permission.READ_EXTERNAL_STORAGE
        }
        ActivityCompat.requestPermissions(this, arrayOf(permission), 2001)
    }

    /// Pictures/DakhilaCamera-তে থাকা ফাইলের নামগুলো (রিকভারির জন্য)।
    private fun galleryFileNames(): List<String> {
        val resolver = applicationContext.contentResolver
        val projection = arrayOf(MediaStore.Images.Media.DISPLAY_NAME)
        val selection: String
        val selectionArgs: Array<String>
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            selection = "${MediaStore.Images.Media.RELATIVE_PATH}=?"
            selectionArgs = arrayOf(relativePath())
        } else {
            selection = "${MediaStore.Images.Media.DATA} LIKE ?"
            selectionArgs = arrayOf("%${relativePath()}%")
        }
        val names = mutableListOf<String>()
        resolver.query(imageCollection(), projection, selection, selectionArgs, null)
            ?.use { cursor ->
                val idx = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
                while (cursor.moveToNext()) names.add(cursor.getString(idx))
            }
        return names
    }

    /// গ্যালারির কপি থেকে অ্যাপ ডিরেক্টরিতে ফাইল ফেরত আনে (রিকভারি)।
    private fun copyGalleryPhoto(fileName: String, destPath: String): Boolean {
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
        resolver.query(
            imageCollection(),
            arrayOf(MediaStore.Images.Media._ID),
            selection,
            selectionArgs,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(0)
                val uri = android.content.ContentUris.withAppendedId(imageCollection(), id)
                resolver.openInputStream(uri)?.use { input ->
                    val dest = File(destPath)
                    dest.parentFile?.mkdirs()
                    dest.outputStream().use { output -> input.copyTo(output) }
                    return true
                }
            }
        }
        return false
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

        val mime = if (fileName.lowercase().endsWith(".png")) "image/png" else "image/jpeg"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, mime)
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

    /// যেকোনো এক্সপোর্ট ফাইল (ZIP/PDF/CSV) সিস্টেম শেয়ার শিটে পাঠায়।
    private fun shareFile(path: String, mime: String): Boolean {
        val file = File(path)
        if (!file.exists()) throw IllegalStateException("File not found: $path")
        val uri = FileProvider.getUriForFile(
            applicationContext,
            "${applicationContext.packageName}.fileprovider",
            file
        )
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "Share"))
        return true
    }

    /// সিস্টেম ভিউয়ারে ফাইল খোলে (PDF/ইমেজ — ACTION_VIEW)।
    private fun viewFile(path: String, mime: String): Boolean {
        val file = File(path)
        if (!file.exists()) throw IllegalStateException("File not found: $path")
        val uri = FileProvider.getUriForFile(
            applicationContext,
            "${applicationContext.packageName}.fileprovider",
            file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
        return true
    }

    /// রিপোর্ট ফরমের মতো টেক্সট সিস্টেম শেয়ার শিটে পাঠায় (WhatsApp/SMS ইত্যাদি)।
    private fun shareText(text: String): Boolean {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        startActivity(Intent.createChooser(intent, "Share"))
        return true
    }
}