package me.pinlin.simple_pass

import android.app.Activity
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/** Toggles FLAG_SECURE on the Activity window, so it needs an attached Activity. */
class ScreenGuardPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {
    companion object {
        private const val CHANNEL = "me.pinlin.simple_pass/screen_guard"
    }

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    // Re-applied after a rotation re-attaches the Activity.
    private var pendingSecure: Boolean? = null
    private var pendingRecentsScreenshotEnabled: Boolean? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        pendingSecure?.let(::applySecure)
        pendingRecentsScreenshotEnabled?.let(::applyRecentsScreenshotEnabled)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        pendingSecure?.let(::applySecure)
        pendingRecentsScreenshotEnabled?.let(::applyRecentsScreenshotEnabled)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setSecure" -> {
                val secure = call.argument<Boolean>("secure") ?: false
                pendingSecure = secure
                applySecure(secure)
                result.success(null)
            }
            "setRecentsScreenshotEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                pendingRecentsScreenshotEnabled = enabled
                applyRecentsScreenshotEnabled(enabled)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun applySecure(secure: Boolean) {
        val current = activity ?: return
        current.runOnUiThread {
            if (secure) {
                current.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                current.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
    }

    // Only Android 13+ can leave the app out of the recents thumbnail; on older
    // versions the Dart side turns on FLAG_SECURE instead while the app lock is on.
    private fun applyRecentsScreenshotEnabled(enabled: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val current = activity ?: return
        current.runOnUiThread { current.setRecentsScreenshotEnabled(enabled) }
    }
}
