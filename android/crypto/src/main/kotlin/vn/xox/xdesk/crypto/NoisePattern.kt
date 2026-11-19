package vn.xox.xdesk.crypto

internal enum class NoiseToken { E, S, EE, ES, SE, SS, PSK }

/** Các pattern Noise của Xdesk, suite `25519_ChaChaPoly_SHA256`. `raw` là byte pattern trong frame `begin`. */
enum class NoisePattern(val raw: Int, val protocolName: String) {
    /** Ghép đôi so mã SAS. */
    XX(1, "Noise_XX_25519_ChaChaPoly_SHA256"),
    /** Ghép đôi bằng QR (psk = token). */
    XX_PSK3(2, "Noise_XXpsk3_25519_ChaChaPoly_SHA256"),
    /** Kết nối lại (initiator biết khoá tĩnh responder). */
    IK(3, "Noise_IK_25519_ChaChaPoly_SHA256");

    val usesPresharedKey: Boolean get() = this == XX_PSK3

    /** IK có pre-message `<- s`. */
    val initiatorKnowsResponderStatic: Boolean get() = this == IK

    val messageCount: Int get() = messages.size

    internal val messages: List<List<NoiseToken>>
        get() = when (this) {
            XX -> listOf(listOf(NoiseToken.E), listOf(NoiseToken.E, NoiseToken.EE, NoiseToken.S, NoiseToken.ES), listOf(NoiseToken.S, NoiseToken.SE))
            XX_PSK3 -> listOf(
                listOf(NoiseToken.E), listOf(NoiseToken.E, NoiseToken.EE, NoiseToken.S, NoiseToken.ES),
                listOf(NoiseToken.S, NoiseToken.SE, NoiseToken.PSK),
            )
            IK -> listOf(
                listOf(NoiseToken.E, NoiseToken.ES, NoiseToken.S, NoiseToken.SS),
                listOf(NoiseToken.E, NoiseToken.EE, NoiseToken.SE),
            )
        }

    companion object {
        fun of(raw: Int): NoisePattern? = entries.firstOrNull { it.raw == raw }
    }
}

enum class NoiseRole { INITIATOR, RESPONDER }
