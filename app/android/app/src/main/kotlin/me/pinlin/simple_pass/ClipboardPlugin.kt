package me.pinlin.simple_pass

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/** Copies text flagged as sensitive; clears it only if the clipboard still holds that text. */
class ClipboardPlugin : FlutterPlugin, MethodCallHandler {
    companion object {
        private const val CHANNEL = "me.pinlin.simple_pass/clipboard"
        // Same value as ClipDescription.EXTRA_IS_SENSITIVE; the constant only
        // exists from API 33, but older releases honor the string too.
        private const val EXTRA_IS_SENSITIVE_COMPAT = "android.content.extra.IS_SENSITIVE"
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private val clipboard: ClipboardManager
        get() = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setText" -> {
                val text = call.argument<String>("text") ?: ""
                val sensitive = call.argument<Boolean>("sensitive") ?: false
                val clip = ClipData.newPlainText("", text)
                if (sensitive) {
                    clip.description.extras = PersistableBundle().apply {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                        } else {
                            putBoolean(EXTRA_IS_SENSITIVE_COMPAT, true)
                        }
                    }
                }
                clipboard.setPrimaryClip(clip)
                result.success(null)
            }
            "clearIfMatches" -> {
                val expected = call.argument<String>("text") ?: ""
                result.success(clearIfMatches(expected))
            }
            else -> result.notImplemented()
        }
    }

    private fun clearIfMatches(expected: String): String {
        // Null both when empty and when Android 10+ denies the read because
        // the app lacks focus; hasPrimaryClip() is equally restricted.
        val clip = clipboard.primaryClip ?: return "unavailable"
        if (clip.itemCount == 0) return "changed"
        val current = clip.getItemAt(0).coerceToText(context)?.toString()
        if (current != expected) return "changed"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            clipboard.clearPrimaryClip()
        } else {
            clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
        }
        return "cleared"
    }
}
