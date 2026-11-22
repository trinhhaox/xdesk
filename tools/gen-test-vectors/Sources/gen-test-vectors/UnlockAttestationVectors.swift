import Foundation
import XdeskWire

/// Khoá/nonce/chữ ký cố định (ECDSA ngẫu nhiên nên sinh một lần rồi cố định) để mọi nền tảng kiểm tra cùng một bộ dữ liệu.
/// Khoá riêng = scalar 0x01..0x20; nonce = 0x00..0x1f; hostKey = 0x11 x32; viewerKey = 0x22 x32;
/// thông điệp ký = "xdesk v1 unlock" || hostKey || viewerKey || nonce.
let unlockVectorPub = "BFFcPW6545a5BNP+yn9U/c0MwemXvzddylFa0KbDtANfRTa+OlDzGPv5pUdZAqIhUCvvDVfgjFOyzApW8X2fk1Q="
let unlockVectorNonce = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
let unlockVectorSig = "MEYCIQDA78kruuMJx1GGoma5H/ZqIVK3SkFpagxEUgIlCt75VwIhANvxlDvuIdVhyifCnHYlb7gZLd7XyEsx9A2Pr9rNP7Pw"
let unlockVectorHostKey = "ERERERERERERERERERERERERERERERERERERERERERE="
let unlockVectorViewerKey = "IiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI="

let unlockAttestationMessages: [(String, UInt32, ControlMessage)] = [
    ("system-unlock-signed", 38, .systemUnlock(SystemUnlock(sig: unlockVectorSig))),
    ("system-unlock-challenge", 39, .systemUnlockChallenge(SystemUnlockChallenge(nonce: unlockVectorNonce, ttlMs: 30_000))),
    ("system-lock-result-ok", 52, .systemLockResult(SystemLockResult(ok: true, message: "Đã khoá Mac"))),
    ("system-lock-result-display-only", 53, .systemLockResult(SystemLockResult(
        ok: false, message: "Mac chỉ tắt màn hình — bật 'Yêu cầu mật khẩu' trong Cài đặt Mac"))),
    ("host-state-video-unavailable", 54, .hostState(HostState(videoAvailable: false, locked: true))),
    ("host-state-video-available", 55, .hostState(HostState(videoAvailable: true, locked: false))),
    ("unlock-key", 51, .unlockKey(UnlockKey(pub: unlockVectorPub))),
]

let unlockAttestationInvalidMessages: [(String, String, String)] = [
    ("unlock-key-unknown-alg", "{\"alg\":\"rsa\",\"id\":1,\"pub\":\"\(unlockVectorPub)\",\"t\":\"unlock.key\"}", "invalidField"),
    ("unlock-key-short-pub", "{\"alg\":\"p256-ecdsa-sha256\",\"id\":1,\"pub\":\"AAAA\",\"t\":\"unlock.key\"}", "invalidField"),
    ("unlock-key-missing-pub", "{\"alg\":\"p256-ecdsa-sha256\",\"id\":1,\"t\":\"unlock.key\"}", "malformedJSON"),
    ("unlock-challenge-short-nonce", "{\"id\":1,\"nonce\":\"AAAA\",\"t\":\"system.unlock.challenge\",\"ttlMs\":30000}", "invalidField"),
    ("unlock-challenge-missing-ttl", "{\"id\":1,\"nonce\":\"\(unlockVectorNonce)\",\"t\":\"system.unlock.challenge\"}", "malformedJSON"),
    ("system-lock-result-missing-message", "{\"id\":1,\"ok\":true,\"t\":\"system.lock.result\"}", "malformedJSON"),
    ("host-state-missing-locked", "{\"id\":1,\"t\":\"host.state\",\"videoAvailable\":false}", "malformedJSON"),
    ("system-unlock-garbage-sig", "{\"id\":1,\"sig\":\"AAAA\",\"t\":\"system.unlock\"}", "invalidField"),
]

/// Dữ liệu để kiểm tra chéo chữ ký DER P-256 trên Swift (CryptoKit) và Kotlin (java.security).
var unlockAttestationSignatureVector: JSONObject {
    [
    "algorithm": "p256-ecdsa-sha256",
    "publicKey": unlockVectorPub,
    "nonce": unlockVectorNonce,
    "domain": "xdesk v1 unlock",
    "hostKey": unlockVectorHostKey,
    "viewerKey": unlockVectorViewerKey,
    "signature": unlockVectorSig,
]
}
