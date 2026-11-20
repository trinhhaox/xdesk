import Foundation
import Testing
@testable import Xdesk

/// Khung plist usbmuxd do chính test này viết tay (không lấy từ máy thật), theo mô tả giao thức: header 16 byte little-endian + plist XML.
@Suite struct UsbmuxPlistTests {
    private func frame(_ xml: String, tag: UInt32 = 1) -> Data {
        let body = Data(xml.utf8)
        var data = Data()
        for word in [UInt32(16 + body.count), 1, 8, tag] { withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) } }
        return data + body
    }

    private func plist(_ entries: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict>\(entries)</dict></plist>"
    }

    private func parse(_ xml: String) throws -> UsbmuxMessage {
        try UsbmuxPlist.parseMessage(Data(xml.utf8))
    }

    @Test func listenRequestHasHeaderAndMessageType() throws {
        let data = try UsbmuxPlist.listenRequest(tag: 7)
        let (length, tag) = try UsbmuxPlist.parseHeader(data.prefix(16))
        #expect(tag == 7)
        #expect(length == data.count - 16)
        let object = try PropertyListSerialization.propertyList(from: data.dropFirst(16), options: [], format: nil) as? [String: Any]
        #expect(object?["MessageType"] as? String == "Listen")
        #expect(object?["ProgName"] as? String == "xdesk")
    }

    @Test func connectRequestWritesPortBigEndianIntoTheNumber() throws {
        // 47801 = 0xBAB9 → viết big-endian rồi đọc như số little-endian = 0xB9BA = 47546.
        let data = try UsbmuxPlist.connectRequest(deviceID: 12, port: 47_801, tag: 2)
        let object = try PropertyListSerialization.propertyList(from: data.dropFirst(16), options: [], format: nil) as? [String: Any]
        #expect(object?["MessageType"] as? String == "Connect")
        #expect(object?["DeviceID"] as? Int == 12)
        #expect(object?["PortNumber"] as? Int == 0xB9BA)
        #expect(UInt16(0xB9BA).byteSwapped == 47_801)
    }

    @Test func headerRoundTripAndRejection() throws {
        let good = frame(plist("<key>MessageType</key><string>Result</string><key>Number</key><integer>0</integer>"), tag: 9)
        let header = try UsbmuxPlist.parseHeader(good.prefix(16))
        #expect(header.tag == 9 && header.payloadLength == good.count - 16)
        var wrongVersion = good.prefix(16)
        wrongVersion.replaceSubrange(4..<8, with: Data([2, 0, 0, 0]))
        #expect(throws: UsbmuxError.self) { _ = try UsbmuxPlist.parseHeader(wrongVersion) }
        #expect(throws: UsbmuxError.self) { _ = try UsbmuxPlist.parseHeader(good.prefix(15)) }
        var tooShort = good.prefix(16)
        tooShort.replaceSubrange(0..<4, with: Data([8, 0, 0, 0]))
        #expect(throws: UsbmuxError.self) { _ = try UsbmuxPlist.parseHeader(tooShort) }
        var huge = good.prefix(16)
        huge.replaceSubrange(0..<4, with: Data([0xFF, 0xFF, 0xFF, 0x7F]))
        #expect(throws: UsbmuxError.self) { _ = try UsbmuxPlist.parseHeader(huge) }
    }

    @Test func parsesResultAttachedDetached() throws {
        #expect(try parse(plist("<key>MessageType</key><string>Result</string><key>Number</key><integer>3</integer>")) == .result(UsbmuxResult(number: 3)))
        let attached = try parse(plist("""
        <key>MessageType</key><string>Attached</string><key>DeviceID</key><integer>5</integer>
        <key>Properties</key><dict><key>ConnectionType</key><string>USB</string><key>DeviceID</key><integer>5</integer>
        <key>ProductID</key><integer>4776</integer><key>SerialNumber</key><string>00008120-001251613C13C01E</string></dict>
        """))
        #expect(attached == .event(.attached(UsbDevice(deviceID: 5, serial: "00008120-001251613C13C01E", productID: 4776))))
        #expect(try parse(plist("<key>MessageType</key><string>Detached</string><key>DeviceID</key><integer>5</integer>")) == .event(.detached(deviceID: 5)))
    }

    @Test func wifiAttachedDevicesAreNotUsbDevices() throws {
        let message = try parse(plist("""
        <key>MessageType</key><string>Attached</string><key>DeviceID</key><integer>9</integer>
        <key>Properties</key><dict><key>ConnectionType</key><string>Network</string></dict>
        """))
        #expect(message == .other("Attached(Network)"))
    }

    @Test func malformedPlistIsReportedNotTrapped() {
        for xml in ["", "not a plist", plist("<key>NoType</key><string>x</string>"), plist("<key>MessageType</key><string>Result</string>"),
                    plist("<key>MessageType</key><string>Attached</string><key>DeviceID</key><integer>1</integer>"),
                    plist("<key>MessageType</key><string>Detached</string>")] {
            #expect(throws: UsbmuxError.self) { _ = try UsbmuxPlist.parseMessage(Data(xml.utf8)) }
        }
        #expect(try! UsbmuxPlist.parseMessage(Data(plist("<key>MessageType</key><string>Paired</string>").utf8)) == .other("Paired"))
    }

    @Test func resultDescriptionsAreHumanReadable() {
        #expect(UsbmuxResult(number: 3).description == String(localized: "app Xdesk trên thiết bị chưa mở (cổng bị từ chối)"))
        #expect(UsbmuxResult(number: 2).description == String(localized: "thiết bị không còn cắm cáp"))
        #expect(UsbmuxResult(number: 0).isOK)
    }

    @MainActor @Test func monitorTracksAttachAndDetach() {
        let monitor = UsbDeviceMonitor()
        let device = UsbDevice(deviceID: 1, serial: "ABCDEFGH12345678", productID: 1)
        monitor.apply(.attached(device))
        monitor.apply(.attached(UsbDevice(deviceID: 1, serial: "ABCDEFGH12345678", productID: 2)))
        #expect(monitor.devices.count == 1 && monitor.devices[0].productID == 2)
        #expect(monitor.devices[0].shortSerial == "12345678")
        monitor.apply(.detached(deviceID: 1))
        #expect(monitor.devices.isEmpty)
    }
}
