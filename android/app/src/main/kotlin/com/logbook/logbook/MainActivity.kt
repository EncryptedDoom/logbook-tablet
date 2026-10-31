package com.logbook.logbook

import android.app.Activity
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Adds two native capabilities: the device ID that activation is bound to,
/// and saving the exported PDF to a location the user picks, through
/// Android's own "Save as" dialog. Nothing leaves the tablet - the file goes
/// wherever the user points it on local storage.
class MainActivity : FlutterActivity() {
    private val saveRequest = 4201
    private var pendingBytes: ByteArray? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // The ID that activation is bound to. Android no longer lets apps read
        // the MAC address or hardware serial; ANDROID_ID is what it offers
        // instead - unique per tablet, stable across reinstalls, and reset
        // only by a factory reset or a change of signing key.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "logbook/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "deviceId") {
                    result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    )
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "logbook/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "savePdf") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("busy", "A save is already in progress", null)
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name") ?: "visitors-book.pdf"
                if (bytes == null) {
                    result.error("no_data", "No PDF bytes supplied", null)
                    return@setMethodCallHandler
                }
                pendingBytes = bytes
                pendingResult = result
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/pdf"
                    putExtra(Intent.EXTRA_TITLE, name)
                }
                startActivityForResult(intent, saveRequest)
            }
    }

    @Deprecated("FlutterActivity is not a ComponentActivity, so this is the API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveRequest) return

        val result = pendingResult ?: return
        val bytes = pendingBytes
        pendingResult = null
        pendingBytes = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) {
            result.success(null) // the user backed out of the dialog
            return
        }
        try {
            contentResolver.openOutputStream(uri, "w")?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not open the chosen file")
            result.success(uri.toString())
        } catch (e: Exception) {
            result.error("write_failed", e.message, null)
        }
    }
}
