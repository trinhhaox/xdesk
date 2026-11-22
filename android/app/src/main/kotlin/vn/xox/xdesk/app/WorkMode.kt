package vn.xox.xdesk.app

import vn.xox.xdesk.wire.ScreenMode

/**
 * Chế độ làm việc thống nhất (2 chế độ xem màn hình + 3 chế độ điều khiển từ xa),
 * có thể đặt mặc định trong Cài đặt và chuyển đổi trực tiếp ngay khi đang kết nối Mac.
 */
enum class WorkMode(
    val title: String,
    val shortTitle: String,
    val summary: String,
    val screenMode: ScreenMode?,
) {
    MIRROR(
        title = "Chiếu màn hình Mac",
        shortTitle = "Chiếu Mac",
        summary = "Hiện đúng màn hình Mac để xem và chạm trực tiếp.",
        screenMode = ScreenMode.MIRROR,
    ),
    EXTEND(
        title = "Màn hình phụ",
        shortTitle = "Màn phụ",
        summary = "Biến điện thoại thành màn hình thứ hai bên cạnh Mac.",
        screenMode = ScreenMode.EXTEND,
    ),
    TRACKPAD(
        title = "Chuột cảm ứng",
        shortTitle = "Chuột",
        summary = "Biến màn hình điện thoại thành bàn di chuột không dây cho Mac.",
        screenMode = null,
    ),
    KEYBOARD(
        title = "Bàn phím ảo",
        shortTitle = "Bàn phím",
        summary = "Gõ tiếng Việt, dùng phím tắt Mac (⌘ ⌥ ⌃ ⇧) và cụm mũi tên.",
        screenMode = null,
    ),
    NUMPAD_MEDIA(
        title = "Trình chiếu & Phím số",
        shortTitle = "Slide & Số",
        summary = "Điều khiển thuyết trình slide (F5, lùi/tiến) và bàn phím số.",
        screenMode = null,
    );

    val isVideoMode: Boolean get() = screenMode != null
    val isControlMode: Boolean get() = screenMode == null

    companion object {
        fun fromStorage(raw: String?, fallbackScreenMode: ScreenMode): WorkMode =
            entries.firstOrNull { it.name == raw }
                ?: if (fallbackScreenMode == ScreenMode.EXTEND) EXTEND else MIRROR
    }
}
