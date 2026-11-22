package vn.xox.xdesk.app

import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.UnrecoverableKeyException
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import vn.xox.xdesk.transport.UnlockCancelledException
import vn.xox.xdesk.transport.UnlockKeyInvalidatedException
import vn.xox.xdesk.transport.UnlockSigner
import vn.xox.xdesk.wire.UnlockAttestation

/**
 * Khoá ECDSA P-256 trong AndroidKeyStore, mỗi lần ký bắt buộc xác thực sinh trắc học mạnh hoặc mã khoá màn hình
 * (BiometricPrompt + CryptoObject). Khoá không xuất khỏi keystore; app sửa đổi không ký được nếu không qua xác thực.
 */
class AndroidKeystoreUnlockSigner : UnlockSigner {
    /** Activity hiện tại để hiện BiometricPrompt; [vn.xox.xdesk.app.ui.StreamScreen] gắn/bỏ theo vòng đời màn hình stream. */
    @Volatile var activity: FragmentActivity? = null

    private val main = Handler(Looper.getMainLooper())

    override fun publicKey(): ByteArray {
        ensureKey()
        val cert = keyStore().getCertificate(ALIAS) ?: error("thiếu chứng chỉ khoá mở khoá")
        return UnlockAttestation.encodePublicKey(cert.publicKey as ECPublicKey)
    }

    override fun existingPublicKey(): ByteArray? = try {
        keyStore().getCertificate(ALIAS)?.let { UnlockAttestation.encodePublicKey(it.publicKey as ECPublicKey) }
    } catch (e: Exception) {
        null
    }

    override fun sign(message: ByteArray, hostName: String, onResult: (Result<ByteArray>) -> Unit) {
        main.post { signOnMain(message, hostName, onResult) }
    }

    private fun signOnMain(message: ByteArray, hostName: String, onResult: (Result<ByteArray>) -> Unit) {
        val host = activity
        if (host == null) {
            onResult(Result.failure(IllegalStateException("không có màn hình để hiện xác thực")))
            return
        }
        val signature = try {
            ensureKey()
            Signature.getInstance(SIGNATURE_ALGORITHM).apply { initSign(keyStore().getKey(ALIAS, null) as PrivateKey) }
        } catch (e: KeyPermanentlyInvalidatedException) {
            return replaceInvalidatedKey(onResult)
        } catch (e: UnrecoverableKeyException) {
            return replaceInvalidatedKey(onResult)
        } catch (e: Exception) {
            onResult(Result.failure(e))
            return
        }
        if (BiometricManager.from(host).canAuthenticate(AUTHENTICATORS) != BiometricManager.BIOMETRIC_SUCCESS) {
            onResult(Result.failure(IllegalStateException("chưa bật sinh trắc học/khoá màn hình")))
            return
        }
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                onResult(runCatching {
                    val signed = checkNotNull(result.cryptoObject?.signature) { "thiếu CryptoObject" }
                    signed.update(message)
                    signed.sign()
                })
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                val cancelled = errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                    errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON || errorCode == BiometricPrompt.ERROR_CANCELED
                onResult(Result.failure(if (cancelled) UnlockCancelledException() else IllegalStateException(errString.toString())))
            }
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Mở khoá $hostName")
            .setSubtitle("Xác thực sinh trắc học hoặc mã khoá điện thoại để tiếp tục")
            .setAllowedAuthenticators(AUTHENTICATORS)
            .build()
        BiometricPrompt(host, ContextCompat.getMainExecutor(host), callback).authenticate(info, BiometricPrompt.CryptoObject(signature))
    }

    /** Khoá bị vô hiệu: xoá, tạo khoá mới; viewer đăng ký lại khoá mới và báo người dùng đặt lại khoá trên Mac. */
    private fun replaceInvalidatedKey(onResult: (Result<ByteArray>) -> Unit) {
        try {
            keyStore().deleteEntry(ALIAS)
            ensureKey()
        } catch (e: Exception) {
            onResult(Result.failure(e))
            return
        }
        onResult(Result.failure(UnlockKeyInvalidatedException()))
    }

    @Synchronized
    private fun ensureKey() {
        if (keyStore().containsAlias(ALIAS)) return
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL)
            .setInvalidatedByBiometricEnrollment(false)
            .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE).apply { initialize(spec) }.generateKeyPair()
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "vn.xox.xdesk.unlock-key"
        const val SIGNATURE_ALGORITHM = "SHA256withECDSA"
        // Mở khoá Mac chỉ nhận sinh trắc học loại mạnh (Class 3) hoặc mã khoá; bỏ loại yếu như mở khoá khuôn mặt 2D.
        const val AUTHENTICATORS = BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
    }
}
