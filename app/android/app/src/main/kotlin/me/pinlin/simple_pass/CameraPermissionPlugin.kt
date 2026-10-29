package me.pinlin.simple_pass

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.PluginRegistry

/** Asks for CAMERA only when Dart calls `request` (the user tapped Scan), never on its own. */
class CameraPermissionPlugin :
    FlutterPlugin, ActivityAware, MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val CHANNEL = "me.pinlin.simple_pass/camera_permission"
        private const val REQUEST_CODE = 0x5350
    }

    private lateinit var channel: MethodChannel
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        // A dialog cut short by the Activity going away must not block later requests.
        pending?.success("denied")
        pending = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val activity = binding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "No foreground activity", null)
            return
        }
        when (call.method) {
            "request" -> request(activity, result)
            "openSettings" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", activity.packageName, null))
                activity.startActivity(intent)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun request(activity: Activity, result: MethodChannel.Result) {
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            result.success("granted")
            return
        }
        if (pending != null) {
            result.error("IN_PROGRESS", "A camera permission request is already showing", null)
            return
        }
        pending = result
        activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        val activity = binding?.activity
        val status = when {
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED -> "granted"
            // Empty when the request was interrupted rather than answered.
            grantResults.isEmpty() -> "denied"
            // After a denial Android stops showing the dialog once rationale turns false.
            activity != null && !activity.shouldShowRequestPermissionRationale(Manifest.permission.CAMERA) ->
                "permanentlyDenied"
            else -> "denied"
        }
        result.success(status)
        return true
    }
}
