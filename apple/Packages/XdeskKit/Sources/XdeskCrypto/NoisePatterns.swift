enum NoiseToken: Sendable { case e, s, ee, es, se, ss, psk }

/// Các pattern Noise dùng trong Xdesk, suite `25519_ChaChaPoly_SHA256`.
public enum NoisePattern: UInt8, Sendable, CaseIterable {
    /// Ghép đôi so mã SAS.
    case xx = 1
    /// Ghép đôi bằng QR (psk = token).
    case xxPsk3 = 2
    /// Kết nối lại (initiator biết khoá tĩnh của responder).
    case ik = 3

    public var protocolName: String {
        switch self {
        case .xx: "Noise_XX_25519_ChaChaPoly_SHA256"
        case .xxPsk3: "Noise_XXpsk3_25519_ChaChaPoly_SHA256"
        case .ik: "Noise_IK_25519_ChaChaPoly_SHA256"
        }
    }

    public var usesPresharedKey: Bool { self == .xxPsk3 }

    /// IK có pre-message `<- s`: initiator phải biết khoá tĩnh responder trước.
    public var initiatorKnowsResponderStatic: Bool { self == .ik }

    /// Số message của bắt tay (initiator viết các message chỉ số chẵn).
    public var messageCount: Int { messages.count }

    var messages: [[NoiseToken]] {
        switch self {
        case .xx: [[.e], [.e, .ee, .s, .es], [.s, .se]]
        case .xxPsk3: [[.e], [.e, .ee, .s, .es], [.s, .se, .psk]]
        case .ik: [[.e, .es, .s, .ss], [.e, .ee, .se]]
        }
    }
}

public enum NoiseRole: Sendable, Equatable {
    case initiator
    case responder
}
