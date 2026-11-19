import Foundation

/// Thiết bị iOS đang cắm cáp theo usbmuxd.
struct UsbDevice: Equatable, Sendable, Identifiable {
    let deviceID: Int
    let serial: String
    let productID: Int

    var id: Int { deviceID }
    /// usbmux không cho tên máy (cần lockdownd): hiện 8 ký tự cuối của số serial/UDID.
    var shortSerial: String { String(serial.suffix(8)) }
}

enum UsbmuxEvent: Equatable, Sendable {
    /// usbmuxd đã nhận lệnh Listen (kể cả khi chưa có thiết bị nào).
    case listening
    case attached(UsbDevice)
    case detached(deviceID: Int)
}

/// Phản hồi `Result` của usbmuxd (`Number`: 0 = OK; 2 = thiết bị không tồn tại; 3 = cổng bị từ chối; 6 = sai phiên bản).
struct UsbmuxResult: Equatable, Sendable {
    let number: Int
    var isOK: Bool { number == 0 }

    var description: String {
        switch number {
        case 0: "OK"
        case 2: "thiết bị không còn cắm cáp"
        case 3: "app Xdesk trên thiết bị chưa mở (cổng bị từ chối)"
        case 6: "usbmuxd không hiểu phiên bản giao thức"
        default: "usbmuxd trả lỗi \(number)"
        }
    }
}

enum UsbmuxMessage: Equatable, Sendable {
    case result(UsbmuxResult)
    case event(UsbmuxEvent)
    /// Gói hợp lệ nhưng không phải loại ta cần (vd. `Paired`).
    case other(String)
}

enum UsbmuxError: Error, Equatable, LocalizedError {
    case malformedHeader(String)
    case malformedPlist(String)
    case unavailable(String)
    case refused(UsbmuxResult)

    var errorDescription: String? {
        switch self {
        case .malformedHeader(let why): "usbmuxd gửi header sai: \(why)"
        case .malformedPlist(let why): "usbmuxd gửi plist sai: \(why)"
        case .unavailable(let why): "không nối được usbmuxd: \(why)"
        case .refused(let result): "usbmuxd từ chối: \(result.description)"
        }
    }
}

/// Khung plist của usbmuxd: header 16 byte little-endian `u32 length (gồm header) | u32 version=1 | u32 type=8 | u32 tag` rồi plist XML.
enum UsbmuxPlist {
    static let headerSize = 16
    static let maxPayload = 1 << 20
    private static let version: UInt32 = 1
    private static let plistType: UInt32 = 8

    // MARK: Mã hoá yêu cầu

    static func listenRequest(tag: UInt32) throws -> Data {
        try frame(["MessageType": "Listen", "ClientVersionString": "xdesk", "ProgName": "xdesk", "kLibUSBMuxVersion": 3], tag: tag)
    }

    /// `PortNumber` là cổng viết big-endian (htons) rồi đọc như số nguyên của máy little-endian.
    static func connectRequest(deviceID: Int, port: UInt16, tag: UInt32) throws -> Data {
        try frame([
            "MessageType": "Connect", "ClientVersionString": "xdesk", "ProgName": "xdesk", "kLibUSBMuxVersion": 3,
            "DeviceID": deviceID, "PortNumber": Int(port.byteSwapped),
        ], tag: tag)
    }

    static func frame(_ message: [String: Any], tag: UInt32) throws -> Data {
        let body = try PropertyListSerialization.data(fromPropertyList: message, format: .xml, options: 0)
        var out = Data()
        for value in [UInt32(headerSize + body.count), version, plistType, tag] { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
        return out + body
    }

    // MARK: Giải mã

    /// Độ dài payload (sau header) và tag; sai version/type/độ dài → lỗi.
    static func parseHeader(_ header: Data) throws -> (payloadLength: Int, tag: UInt32) {
        guard header.count == headerSize else { throw UsbmuxError.malformedHeader("cần \(headerSize) byte, có \(header.count)") }
        let words = (0..<4).map { index -> UInt32 in
            header.subdata(in: index * 4..<index * 4 + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        }
        guard words[1] == version else { throw UsbmuxError.malformedHeader("version \(words[1])") }
        guard words[2] == plistType else { throw UsbmuxError.malformedHeader("type \(words[2])") }
        guard words[0] >= UInt32(headerSize), Int(words[0]) - headerSize <= maxPayload else { throw UsbmuxError.malformedHeader("length \(words[0])") }
        return (Int(words[0]) - headerSize, words[3])
    }

    static func parseMessage(_ payload: Data) throws -> UsbmuxMessage {
        let object: Any
        do { object = try PropertyListSerialization.propertyList(from: payload, options: [], format: nil) } catch {
            throw UsbmuxError.malformedPlist(error.localizedDescription)
        }
        guard let dict = object as? [String: Any], let type = dict["MessageType"] as? String else {
            throw UsbmuxError.malformedPlist("thiếu MessageType")
        }
        switch type {
        case "Result":
            guard let number = dict["Number"] as? Int else { throw UsbmuxError.malformedPlist("Result thiếu Number") }
            return .result(UsbmuxResult(number: number))
        case "Attached":
            guard let id = dict["DeviceID"] as? Int, let props = dict["Properties"] as? [String: Any] else {
                throw UsbmuxError.malformedPlist("Attached thiếu DeviceID/Properties")
            }
            // Thiết bị qua Wi-Fi cũng được usbmuxd báo; chỉ đường cáp mới là "USB".
            guard (props["ConnectionType"] as? String) == "USB" else { return .other("Attached(\(props["ConnectionType"] as? String ?? "?"))") }
            let device = UsbDevice(deviceID: id, serial: props["SerialNumber"] as? String ?? "", productID: props["ProductID"] as? Int ?? 0)
            return .event(.attached(device))
        case "Detached":
            guard let id = dict["DeviceID"] as? Int else { throw UsbmuxError.malformedPlist("Detached thiếu DeviceID") }
            return .event(.detached(deviceID: id))
        default:
            return .other(type)
        }
    }
}
