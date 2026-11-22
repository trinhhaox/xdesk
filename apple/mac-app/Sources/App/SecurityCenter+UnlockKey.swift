import XdeskCrypto

extension SecurityCenter {
    /// Khoá mở khoá đã đăng ký của viewer (đọc thẳng từ kho, không qua bản sao UI có thể cũ).
    func unlockKey(forViewerKey key: [UInt8]) async -> [UInt8]? {
        await stores?.hostDevices.device(publicKey: key)?.unlockKey
    }

    func enrollUnlockKey(viewerKey: [UInt8], unlockKey: [UInt8]) async -> PairedDevicesStore.UnlockKeyEnrollment {
        guard let store = stores?.hostDevices, let device = await store.device(publicKey: viewerKey) else { return .notPermitted }
        do {
            let result = try await store.enrollUnlockKey(id: device.id, key: unlockKey)
            if result == .enrolled {
                unlockEnrollmentUntil[device.id] = nil
                await refresh()
            }
            return result
        } catch {
            log.error("đăng ký khoá mở khoá lỗi: \(error.localizedDescription, privacy: .public)")
            return .notPermitted
        }
    }

    /// "Đặt lại khoá": lần `unlock.key` kế tiếp của điện thoại sẽ đăng ký lại.
    func resetUnlockKey(deviceId: String) async {
        do {
            try await stores?.hostDevices.clearUnlockKey(id: deviceId)
            unlockEnrollmentUntil[deviceId] = Date().addingTimeInterval(PairedDevicesStore.unlockEnrollmentWindow)
            log.notice("mở cửa sổ đăng ký khoá mở khoá 5 phút cho thiết bị \(deviceId, privacy: .public)")
        } catch {
            log.error("đặt lại khoá mở khoá lỗi: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }
}
