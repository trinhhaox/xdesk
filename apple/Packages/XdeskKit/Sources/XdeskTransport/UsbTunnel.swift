/// Hằng số đường hầm USB (usbmuxd): app viewer iOS nghe cổng này (chỉ trên loopback của thiết bị), Mac nối vào qua usbmuxd.
public enum UsbTunnel {
    /// Cổng TCP cố định trên iPhone/iPad (cạnh cổng host Wi-Fi 47800).
    public static let devicePort: UInt16 = 47_801
}
