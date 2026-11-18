# Security review: phase 06a crypto (XdeskCrypto)

Date: 2026-11-19 | Scope: `apple/Packages/XdeskKit/Sources/XdeskCrypto/*.swift`, specs `protocol/spec/crypto-handshake.md`, `framing.md`, `media-packets.md` | Mode: read-only, no repo edits
Tests: `swift test --filter XdeskCryptoTests` gives 63/63 green. PoC and probe code live only in the session scratchpad (`sas-poc/`, `lowpoint.swift`).

## Summary

| Severity | Confirmed | Latent/spec-level (no consumer code yet) |
|---|---|---|
| Critical | 1 | 0 |
| High | 0 | 1 |
| Medium | 2 | 4 |
| Low | 3 | 5 |
| Info | several | |

Noise core conformance looks correct. MixKey, MixHash and MixKeyAndHash run in the right order. The psk3 token sits at the end of message 3, and in psk mode `e` also calls MixKey. The nonce is 4 zero bytes followed by a LE u64. Nonce 2^64-1 is rejected for both encrypt and decrypt. With no key set, encrypt passes plaintext through. Split and HKDF follow §4.3. IK initiators must have the remote static key and other roles may not pass one. The cacophony vectors pass. Key separation in `SessionKeys` is sound: 4 labels, salt = h, TCP and UDP never share a key. The UDP replay window is updated only after the tag verifies. The serious problem is in the SAS layer on top of Noise.

---

## CRITICAL

### C1. The SAS commitment does not cover the message-3 payload, so a MITM can grind `deviceName` and make both codes match (confirmed with PoC)
- Code: `ShortAuthString.swift:16-38`. Spec: `crypto-handshake.md:76-81`. Contributing code: `HandshakePayload.swift:27-33`, `NoiseSymmetricState.swift:34-38` (msg3 payload ciphertext is MixHash'ed into h).
- The cause: `code = HKDF(nonce, h_after_msg3)`. h after msg3 includes the encrypted msg3 payload (`role|flags|nameLen|name|nonce`). The commitment covers only `e | s | nonce`. The name (up to 64 bytes of free UTF-8) is not committed, so the attacker can still choose it after it learns the other side's code.
- Attack (I = viewer, M = attacker, R = host):
  1. Leg A: M acts as responder to I. I sends commit_I, msg1 and msg2, then msg3 with nonce_I. M now knows `code_I`.
  2. Leg B: M acts as initiator to R. It commits honestly to (e_M, s_M, n_M) and receives R's msg2.
  3. M tries msg3 payload names one after another, for example "iPad" plus invisible zero-width characters, until `code_R == code_I`. About 10^6 tries finds a match.
  4. R's commitment check passes, both screens show the same 6 digits, the user taps "Khớp", and M is paired in both directions with default view+input.
- PoC result, using only the public XdeskCrypto API: `MITM SUCCEEDS`. A match came after about 1.16M tries in 27.7 s on 8 cores, and each try paid for a full `writeMessage` including X25519. An attacker with its own Noise state can cache everything before the payload encryption. Each try then costs one ChaChaPoly, one SHA-256 and one HKDF, roughly 2 µs, so under a second with multiple cores. That fits well inside the 30 s handshake timeout. The "3 failures / 10 min" limit does not help because the first attempt succeeds.
- The spec's argument at :81 ("code_R bị M xác định hoàn toàn…") is wrong for this reason. The existing test `endToEndAgreementAndMitmMismatch` only models a non-adaptive MITM.
- Fix (choose one; option a is simplest):
  a. Derive the SAS from the handshake hash taken right after message 2: `code = HKDF(ikm: sasNonce, salt: h2, info: "xdesk v1 sas")`. Keep the commitment over `e|s|nonce` and keep checking it against the `s` received in msg3. Each side saves `h2` when it writes or reads msg2. After the commit, nothing the initiator controls can then change the SAS input. Update spec §5 steps 4-5 and the rationale. Also enforce an empty msg1 payload (see L1).
  b. Alternatively, commit to the whole msg3 plaintext: `commit = SHA-256(label | e | s | SHA-256(msg3Payload))`, where msg3Payload contains the nonce. The responder recomputes it from the decrypted payload.
  - Add a regression test based on the PoC: grinding the msg3 payload must not change `code_R`, and an adaptive MITM matches with probability at most 10^-6.

---

## HIGH (latent: will become real once 06b implements host pairing policy)

### H1. A viewer that already has view permission (or a screen recording) can read the QR pairing token and escalate to input control
- Spec `crypto-handshake.md:60` ("Thành công → ghi thiết bị với quyền mặc định"). Defaults in `PairedDevice.swift:10`: view + input.
- Scenario: the host shows the QR on the same screen Xdesk streams. Any connected viewer, even view-only, sees the token. So does Zoom or Meet screen sharing, a screen recording, or a camera pointed at the screen. Within 120 s that party can pair its own device through XXpsk3. It gets input control with no prompt on the host. The psk binds the session to whoever saw the QR, not to the person sitting at the host.
- Fix: exclude the QR window from capture (`NSWindow.sharingType = .none` and an `SCContentFilter` exclusion in the host's own encoder). Require a host-side confirmation ("Cho phép '<name>' điều khiển máy này?") before `add()`. Consider making QR-paired devices view-only by default. Invalidate the token when any viewer session is active, or rotate it at each display.

---

## MEDIUM

### M1. Paired-device lookup matches only the 64-bit fingerprint, not the full public key (confirmed in code)
- `PairedDevicesStore.swift:72` (`device(publicKey:)` → `byId[fingerprint]`), `:78-81` (`add` with a colliding id keeps the old `publicKey` and permissions). Fingerprint: `DeviceIdentity.swift:16-22` (first 8 bytes of SHA-256).
- Scenario: the host enforces IK with `store.device(publicKey: hs.remoteStaticKey)`, which is the obvious way to call the API. An attacker who finds an X25519 key whose SHA-256 starts with the same 8 bytes as any paired device's (second preimage, about 2^64 / N work) is accepted with that device's permissions. That is costly but within reach of a nation-state, and the defense is free.
- Fix: in `device(publicKey:)`, also require `ConstantTime.equals(found.publicKey, publicKey)`. Better, key the dictionary by the full key (base64url) and keep the fingerprint for display only. In `add`, reject an id collision when the key differs. Never authorize by the Bonjour TXT `id`.

### M2. Cipher state types are copyable value types, so a copy reuses nonces (confirmed design hazard)
- `DatagramSender.swift:4`, `StreamCipher.swift:16,36`, `NoiseCipherState.swift:17`, `NoiseHandshakeState.swift:5`, `PairingToken.swift:15`, all `struct … Sendable`.
- Scenario: any copy keeps the same key and counter. Examples: `var s = session.udpSender` in two tasks, capturing it in a closure, a NACK resend path that holds its own copy, or retrying `writeMessage` on a saved copy. Two different plaintexts then go out under the same (key, nonce). That breaks ChaCha20-Poly1305 completely: XOR of the plaintexts leaks and the Poly1305 key is recovered, so packets can be forged. The PoC did exactly this 10^6 times with `NoiseHandshakeState` without any warning. A copied `PairingTokenIssuer` makes `consume` single-use only per copy.
- Fix: mark `DatagramSender`, `StreamSender`, `StreamReceiver`, `DatagramReceiver`, `NoiseCipherState` and `PairingTokenIssuer` as `~Copyable` (Swift 5.9+), or make them `final class` behind a lock or an actor. For `NoiseHandshakeState`, keep the internal copy-on-success pattern but make the public type `~Copyable`. NACK retransmits must call `seal` again on the single owner. The spec says this; the type system should enforce it.

### M3 (latent). The paired-devices JSON is the authorization list, and any same-user process can edit it, bypassing macOS TCC
- `PairedDevicesStore.swift:15-29`. The file is written atomically (temp file → rename, then chmod 0600, so there is a short window with umask permissions). It is neither integrity-protected nor encrypted, and the parent directory is not set to 0700.
- Scenario: the host app holds the Screen Recording and Accessibility TCC grants. A same-user process that lacks those grants adds `{pub: attacker, permissions: view+input}` to `~/Library/Application Support/Xdesk/paired-devices.json`. It then connects through IK, for example to localhost, and gets screen capture plus synthetic input. That is TCC privilege escalation. Whether it works depends on sandboxing and the macOS app-container protection, which is not verified.
- Fix: store the list in the Keychain (data-protection keychain, app access group). Or HMAC the file with a 32-byte key kept in the Keychain and reject it on mismatch. Create the directory with 0700. Write the file with 0600 from the start (`FileManager.createFile(atPath:contents:attributes:)`, then `replaceItemAt`).

### M4 (latent/spec). UDP "close the session if more than 50 failures per second" is a cheap kill switch for an off-path attacker
- Spec `crypto-handshake.md:140`.
- Scenario: someone who knows or guesses the 5-tuple, such as a LAN peer or a Tailscale peer spoofing the source, sends 51 garbage datagrams per second with valid length and epoch 0. The session closes. Datagrams carry no authentication before AEAD, so anyone can trigger this.
- Fix: drop failed packets and count them for telemetry, but never close on unauthenticated input. If a liveness signal is needed, close only when no valid packet arrives for N seconds.

### M5 (latent/spec). Handshake slot exhaustion: 4 concurrent unauthenticated handshakes with a 30 s total timeout
- Spec `crypto-handshake.md:41`.
- Scenario: 4 TCP connections that send `begin` and then stall block all pairing and reconnects, as a repeatable slowloris.
- Fix: limit per source IP (for example 1-2), set a per-message deadline of about 5 s, evict the oldest unauthenticated slot under pressure, and prefer IK reconnects of known keys over new XX/XXpsk3 attempts.

### M6 (latent). IK message 1 can be replayed and is KCI-vulnerable, so the host must not treat the peer as live after msg1
- Spec `crypto-handshake.md:62` ("Có → chạy tiếp, áp dụng quyền đã lưu, cập nhật lastSeen").
- Scenario: a captured IK msg1 replayed later makes the host accept, update `lastSeen`, show "connected", and possibly start capture and encoding. Confidentiality holds because the attacker lacks `e_i` for `ee`, but presence is spoofed and resources are spent. If the host's static key leaks, an attacker can also impersonate any viewer in msg1 (KCI through `es`/`ss`).
- Fix: mark the session authenticated, set `lastSeen`, and start capture only after the first valid transport frame from the initiator (for example a mandatory first control `hello` encrypted with the TCP i2r key).

---

## LOW

### L1. Payloads of unkeyed/weakly-keyed messages are not enforced empty in the crypto layer (confirmed)
- `NoiseCipherState.swift:31,39` (correct Noise passthrough) together with `NoiseHandshakeState.swift:82-106`. XX msg1 payload is plaintext. XXpsk3 msg1 is keyed only from the public `e`.
- The spec says these payloads must be empty (`crypto-handshake.md:56`), but nothing enforces it. Any app data placed there goes out in clear and stays unauthenticated.
- Fix: in `writeMessage`/`readMessage`, reject a non-empty payload for message index 0 of `.xx`/`.xxPsk3`.

### L2. The XX initiator has no built-in host-key pinning (latent)
- In the QR flow the viewer must compare the msg2 `s` with `h` from the QR before it sends msg3, which reveals the viewer's static key, its name, and possibly the SAS nonce. The crypto API leaves this to the caller.
- Fix: add `expectedRemoteStatic: [UInt8]?` to `NoiseHandshakeState.init`. Check it in constant time inside `read(.s)` and throw before any further processing.

### L3. Raw CryptoKit errors escape on low-order points; the all-zero check never runs on Apple (confirmed)
- `NoiseHandshakeState.swift:171-172`. A probe showed CryptoKit throws `underlyingCoreCryptoError(-7)` for all 7 standard low-order and non-canonical points, so the code reaches the caller without passing through `ConstantTime.isAllZero`. This is safe, but the error is not a `CryptoError`, which contradicts spec :144. The test `lowOrderEphemeralIsRejected` accepts `any Error`.
- Fix: wrap the call (`do { … } catch { throw CryptoError.invalidDiffieHellman }`) and assert the exact error in the test. Keep the all-zero check because the Kotlin/JCA port needs it explicitly.

### L4. Secrets can end up in logs through default reflection (confirmed)
- `PairingToken.bytes` (`PairingToken.swift:9`), `PairingURI.token` (`PairingURI.swift:9`), `HandshakePayload.sasNonce`, and `NoiseHandshakeState.psk` (private, but `dump()` / `"\(state)"` reflects private stored properties).
- Fix: conform these types to `CustomStringConvertible`, `CustomDebugStringConvertible` and `CustomReflectable` with redacted output. Avoid `Equatable` on `PairingToken` (it invites non-constant-time `==`).

### L5. Keychain item on macOS goes to the legacy file keychain (confirmed by code reading)
- `DeviceIdentityStore.swift:16-19,44-46`. Without `kSecUseDataProtectionKeychain: true`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is ignored on macOS. The item lands in login.keychain-db (it can be migrated or backed up, and its ACL works by prompt).
- Fix: add `kSecUseDataProtectionKeychain: true` (needs a signed app plus a keychain access group), an explicit `kSecAttrSynchronizable: false`, and `kSecAttrAccessGroup`.

### L6. Pairing token failure limit not implemented (latent)
- Spec :60 says to invalidate after 5 failed handshakes. `PairingTokenIssuer` has no counter. Brute force of the 256-bit token is impossible, so this mainly serves as a hygiene and DoS signal. Add `recordFailure()`.

### L7. Pairing URI addresses are not validated as `host:port` (confirmed)
- `PairingURI.swift:46-49`. A crafted QR can point the viewer at arbitrary internal endpoints, such as `127.0.0.1:22`, and make it send a `begin` frame. Host-key pinning prevents a session, but the viewer still connects to whatever address the QR names (SSRF-like).
- Fix: parse each address as IPv4, `[IPv6]` or a hostname plus a port in 1-65535, and reject everything else.

### L8. UDP receiver deadlocks when the sender jumps 2 or more epochs (by design)
- `DatagramReceiver.swift:36-46`. If every packet of epoch n+1 is lost, or the owner rekeys on a timer while idle, all later packets fail with `unknownEpoch` and never recover. Under the current M4 rule that also closes the session.
- Fix: rekey only when sending, or allow a look-ahead of up to K epochs (bounded key derivations, checked only after cheap length checks).

---

## INFO
- Media header (ptype, frameNo, keyframe flag, ptsMs, sizes) travels in clear. Input packets (ptype 0x30) expose keystroke timing and counts to on-path observers. Consider padding or batching input, or moving the input type into the encrypted payload.
- `ShortAuthString.randomNonce` uses `UInt8.random` (SystemRandomNumberGenerator, a CSPRNG). It is fine, but `SymmetricKey(size:)` or `SecRandomCopyBytes` makes the intent explicit. The mod 10^6 bias of a 64-bit value is about 5e-14, which is negligible.
- `KeySchedule.next` gives forward secrecy across rekeys but no post-compromise security. That is acceptable for 1 h epochs.
- Keys and DH secrets are kept in `[UInt8]` and never zeroized. This is minor and typical for CryptoKit code.
- TCP truncation (peer FIN mid-stream) is not authenticated. The app layer should treat an unexpected close as an error, not as a clean end.

## Unresolved questions
1. Is the macOS host app sandboxed? Is Application Support inside a protected container? This decides whether M3 is real.
2. How will 06b store and pass `h2` if fix C1(a) is chosen? Does the Kotlin port (phase 07) need matching vectors in `crypto-session.json`?
3. Is the default permission for QR pairing view+input on purpose (H1)?

---

# Resolution (2026-11-19, library level)

All edits stay inside `XdeskCrypto`, `XdeskWire` (MTU constant), specs, vectors and tests. Transport/UI items are deferred to 06b (list at the end).

| Finding | Status | What changed |
|---|---|---|
| C1 | Fixed | SAS code = `HKDF(ikm = sasNonce, salt = h2, info = "xdesk v1 sas")`, where `h2` is the handshake hash right after message 2 (`NoiseHandshakeState.messageTwoHash`, set on write or read of message 2). `ShortAuthString.code(messageTwoHash:nonce:)` replaces `code(handshakeHash:nonce:)`. The commitment over `e\|s\|nonce` is unchanged and still checked after message 3. Spec §5 steps 3-5 and rationale rewritten (explains why the old rationale was wrong). Regression test `grindingTheMessageThreePayloadCannotChangeTheCode`: 300 handshakes with fixed keys and different msg3 `deviceName` give 300 different final hashes (the old SAS input) but exactly 1 SAS code. `messageTwoHashIsUnavailableBeforeMessageTwoAndEqualOnBothSides` covers the capture. Vectors regenerated (`sas.messageTwoHash`). |
| H1 | Deferred | 06b (see list). |
| M1 | Fixed | `PairedDevicesStore.device(publicKey:)` scans all devices and compares the full 32-byte key with `ConstantTime.equals` (no early exit). Fingerprint remains display id. `add` throws `CryptoError.deviceIdCollision` if an id exists with a different key; load rejects duplicate ids as `corrupt`. Tests: one-bit flips at several offsets, wrong length, empty key. A real 64-bit collision cannot be constructed, so the collision branch in `add` is defensive and covered only by the duplicate-entry load test. |
| M2 | Fixed | `~Copyable` on `DatagramSender`, `DatagramReceiver`, `StreamSender`, `StreamReceiver`, `PairingTokenIssuer`, `NoiseHandshakeState`. Choice: structs (not classes), because they stay value-typed, need no lock, work with Swift 6 strict concurrency (`Sendable`), and a copy becomes a compile error. A noncopyable value also cannot be passed to `print`/`dump`/interpolation (needs `Any`), so it cannot leak through reflection. `NoiseHandshakeState` wraps an internal copyable `NoiseHandshakeCore`, which keeps the "apply a message only if it fully succeeds" rollback (existing test `tamperedMessageIsRejectedAndStateIsKept`). `NoiseCipherState` and `NoiseSymmetricState` stay internal copyable value types: they are never exposed and only live inside noncopyable owners or the core. Test side effects: `#expect` cannot take noncopyable expressions, so tests use `expectEqual` / `unwrap` helpers and no tuples of states. |
| M3 | Fixed | File is `{schemaVersion, devices, mac}`, `mac = HMAC-SHA256(key, "xdesk v1 paired-devices" 0x00 \| canonical JSON)`. Key: 32 random bytes in Keychain (`KeychainPairedDevicesMACKeyStore`, same accessibility class and data-protection logic as the identity key). Load of a file with a bad or missing MAC gives an empty list plus `integrityFailure == true`; next successful write re-signs and clears the flag. Corrupt JSON and unsupported schema still throw. File storage now creates the directory 0700 and the file 0600 from the start (temp file in the same directory, `rename`). Tests use `InMemoryPairedDevicesMACKey`: edited permissions, injected device (no mac / junk mac / zero mac), wrong key, re-sign. Residual: a rollback to an older valid file still passes the MAC; the tampered file is overwritten on the next save (no quarantine copy). |
| M4, M5, M6 | Deferred | 06b. |
| L1 | Fixed | `writeMessage` and `readMessage` reject a non-empty payload for message 0 of XX and XXpsk3 (`invalidHandshakePayload`; state unchanged). IK message 1 payload still allowed. Only the internal vector initializer (ephemeral override, cacophony vectors have payloads) opts out. |
| L2 | Not done | Not in this task's list; remains a 06b/API item (pin check in the caller before sending msg3). |
| L3 | Fixed | CryptoKit errors from `sharedSecretFromKeyAgreement` become `CryptoError.invalidDiffieHellman`; the explicit all-zero check stays for Kotlin/JCA parity. Tests assert the exact error for 4 low-order encodings. |
| L4 | Fixed | New public marker protocol `Redacted` (description, debugDescription, `customMirror` with no children) on `PairingToken`, `PairingURI`, `SessionKeys`, `DeviceIdentity`. `NoiseHandshakeState` is noncopyable so it cannot be reflected at all. `PairingToken` is no longer `Equatable`; `PairingURI.==` is constant time on the token. Test checks `"\(x)"`, `String(reflecting:)` and `dump` for token bytes, base64url, key names. |
| L5 | Fixed with caveat | `KeychainSecretStore` (shared by identity key and MAC key) sets `kSecUseDataProtectionKeychain`, `kSecAttrSynchronizable = false`, `AfterFirstUnlockThisDeviceOnly`. Tested on this Mac: an unsigned or ad-hoc signed binary (and `swift test`) gets `errSecMissingEntitlement` (-34018) from the data-protection keychain. Policy `.required` then throws `IdentityStoreError.dataProtectionKeychainUnavailable`; policy `.preferred` (default) falls back to the login keychain and reports it through `backend` (`.legacyFileKeychain`). The signed app (team 4DU4BTV46U) was not exercised here; 06b must assert `backend == .dataProtection` at startup in a signed build and surface a warning otherwise. No `kSecAttrAccessGroup` is set (default group). |
| L6 | Deferred | `recordFailure()` for 5 failed handshakes goes with host policy in 06b. |
| L7 | Fixed | `HostPortAddress` validates each QR `a=`: IPv4 (`inet_pton`), `[IPv6]` (no zone), or RFC 1123 hostname (last label not all digits), port digits only 1-65535, max 255 B. Any bad address rejects the whole URI. 8 valid and 35 invalid cases tested. |
| L8 | Fixed | `DatagramReceiver` accepts packets from epoch `e+k`, `1 <= k <= 4`, trial-deriving `rekey^k` and moving only after the tag verifies; the previous epoch is kept (derived with a fresh window when `k >= 2`). `k >= 5` gives `unknownEpoch` and state is untouched. Spec §8 updated; beyond the lookahead the session layer must resync over control (message defined in 06b) or close. Tests: jumps 2..4 accepted, jump 5 rejected, forged future epoch does not move the receiver, previous/older epoch behaviour after a jump. |
| MTU | Fixed | `MediaPacket.maxPayload` 1200 -> 1192 (`XdeskWire/MediaHeader.swift`; `Packetizer` clamp follows). Max datagram = 16 + 1192 + 24 = 1232 B. `InputEvent.maxBatch` stays 42 (1192 / 28). Specs `media-packets.md`, `crypto-handshake.md` §8/§12, `xdesk-wire-v1-overview.md` updated; Wire tests that assumed 1200-byte fragments adjusted (`ReassemblerTests`, `NackTrackerTests`). `media-headers.json` uses explicit small `maxPayload` values, so it did not change. |

## 06b must do
1. H1: exclude the QR window from capture (`NSWindow.sharingType = .none` plus an exclusion in the host's capture filter); require a host-side confirmation before `PairedDevicesStore.add` for XXpsk3; consider view-only default for QR-paired devices; invalidate or rotate the token while any viewer session is active.
2. M4: never close a UDP session on unauthenticated failures; count them only. Close on "no valid packet for N seconds".
3. M5: handshake slot policy: per-source-IP cap (1-2), per-message deadline (~5 s), evict the oldest unauthenticated slot, prefer IK reconnects.
4. M6: treat IK as authenticated only after the first valid transport frame from the initiator (mandatory first control `hello`); only then set `lastSeen` and start capture.
5. L2: pin the host key (`h` from QR) before sending msg3 (or add `expectedRemoteStatic` to the handshake API).
6. L6: `PairingTokenIssuer.recordFailure()` and invalidate after 5 failed handshakes.
7. SAS flow: pass `messageTwoHash` (initiator: after reading msg2; responder: after writing msg2) and the revealed nonce to `ShortAuthString.code`; verify the commitment after msg3 against `remoteEphemeralKey`/`remoteStaticKey`; keep the 3 failures / 10 min limiter.
8. UDP resync control message for epoch gaps of 5 or more; define it in `control-messages.md`.
9. Wire `PairedDevicesStore(storage:macKey:)` with `KeychainPairedDevicesMACKeyStore`; show UI when `integrityFailure` is true; assert `backend == .dataProtection` in the signed app; decide whether to quarantine a tampered file before the next save.
10. Hold senders and receivers in a single owner (actor or a lock-protected box); NACK retransmits call `seal` again, never resend old bytes.
