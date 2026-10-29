package me.pinlin.simple_pass

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import android.util.Base64
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import java.security.KeyStore
import javax.crypto.BadPaddingException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-GCM keys in AndroidKeyStore usable only shortly after authentication. A refused cipher init
 * returns `notAuthenticated`; Dart then calls `authenticate` and retries.
 */
class KeystorePlugin : FlutterPlugin, ActivityAware, MethodCallHandler {
    companion object {
        private const val CHANNEL = "me.pinlin.simple_pass/keystore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_BYTES = 12
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: FragmentActivity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "authenticate" -> authenticate(result)
            "encrypt", "decrypt", "deleteKey" -> keyOperation(call, result)
            else -> result.notImplemented()
        }
    }

    private fun keyOperation(call: MethodCall, result: MethodChannel.Result) {
        val alias = call.argument<String>("alias")!!
        try {
            when (call.method) {
                "encrypt" -> {
                    val timeout = call.argument<Int>("timeoutSeconds")!!
                    // A new key under the same alias can't open what the old one sealed.
                    val keyInUse = call.argument<Boolean>("keyInUse")!!
                    val cipher = Cipher.getInstance(TRANSFORMATION)
                    try {
                        val key = existingKey(alias)
                            ?: if (keyInUse) throw KeyPermanentlyInvalidatedException() else createKey(alias, timeout)
                        cipher.init(Cipher.ENCRYPT_MODE, key)
                    } catch (e: KeyPermanentlyInvalidatedException) {
                        if (keyInUse) throw e
                        keyStore().deleteEntry(alias)
                        cipher.init(Cipher.ENCRYPT_MODE, createKey(alias, timeout))
                    }
                    val sealed = cipher.iv + cipher.doFinal(call.argument<String>("plaintext")!!.toByteArray())
                    result.success(Base64.encodeToString(sealed, Base64.NO_WRAP))
                }
                "decrypt" -> {
                    // A missing key can't come back either, same as an invalidated one.
                    val key = existingKey(alias) ?: throw KeyPermanentlyInvalidatedException()
                    val sealed = Base64.decode(call.argument<String>("ciphertext")!!, Base64.NO_WRAP)
                    val cipher = Cipher.getInstance(TRANSFORMATION)
                    cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed, 0, IV_BYTES))
                    result.success(String(cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES)))
                }
                "deleteKey" -> {
                    keyStore().deleteEntry(alias)
                    result.success(null)
                }
            }
        } catch (e: UserNotAuthenticatedException) {
            result.error("notAuthenticated", null, null)
        } catch (e: KeyPermanentlyInvalidatedException) {
            result.error("keyInvalidated", null, null)
        } catch (e: BadPaddingException) {
            // AEADBadTagException: this ciphertext is damaged; the key itself may still open others.
            result.error("damaged", null, null)
        } catch (e: Exception) {
            // Class name only: messages could echo key material.
            result.error("failed", e.javaClass.simpleName, null)
        }
    }

    private fun keyStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun existingKey(alias: String) = keyStore().getKey(alias, null) as SecretKey?

    private fun createKey(alias: String, timeoutSeconds: Int): SecretKey {
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationParameters(
                timeoutSeconds,
                KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL,
            )
            // Enrolling another fingerprint must not destroy the secrets.
            .setInvalidatedByBiometricEnrollment(false)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply { init(spec) }
            .generateKey()
    }

    private fun authenticate(result: MethodChannel.Result) {
        val current = activity ?: return result.success("failed")
        // BiometricPrompt silently does nothing once the state is saved, which
        // would leave this call unanswered.
        if (current.supportFragmentManager.isStateSaved) return result.success("canceled")
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(res: BiometricPrompt.AuthenticationResult) {
                result.success("success")
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                result.success(
                    when (errorCode) {
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_CANCELED,
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                        BiometricPrompt.ERROR_TIMEOUT -> "canceled"
                        BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL -> "noCredentials"
                        BiometricPrompt.ERROR_LOCKOUT,
                        BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockedOut"
                        else -> "failed"
                    }
                )
            }
        }
        // The app's own name as the title; the system localizes the rest.
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(context.applicationInfo.loadLabel(context.packageManager))
            .setAllowedAuthenticators(BIOMETRIC_STRONG or DEVICE_CREDENTIAL)
            .build()
        BiometricPrompt(current, ContextCompat.getMainExecutor(context), callback).authenticate(info)
    }
}
