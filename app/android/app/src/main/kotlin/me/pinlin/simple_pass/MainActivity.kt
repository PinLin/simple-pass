package me.pinlin.simple_pass

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.woheller69.freeDroidWarn.FreeDroidWarn

// FlutterFragmentActivity (not FlutterActivity): BiometricPrompt in
// KeystorePlugin needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // One-time notice shown again whenever versionCode increases.
        FreeDroidWarn.showWarningOnUpgrade(this, BuildConfig.VERSION_CODE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(ScreenGuardPlugin())
        flutterEngine.plugins.add(ClipboardPlugin())
        flutterEngine.plugins.add(KeystorePlugin())
        flutterEngine.plugins.add(CameraPermissionPlugin())
        // Enrollment reports the Android version the way MobilePASS servers expect it; the app lock needs
        // the API level to know whether the recents thumbnail can be left out.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "me.pinlin.simple_pass/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "osRelease" -> result.success(Build.VERSION.RELEASE)
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    else -> result.notImplemented()
                }
            }
    }
}
