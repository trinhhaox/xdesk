import Foundation
import Observation
import XdeskInput
import XdeskViewer
import XdeskWire

/// Bàn phím ảo gửi sang Mac: biến thay đổi của ô gõ ẩn thành input theo đúng thứ tự, giữ phím bổ trợ dính của thanh phím phụ.
/// Phím (Backspace/Return/mũi tên…) đi UDP còn chữ đi TCP nên giữa hai loại có khoảng nghỉ ngắn để host nhận đúng thứ tự.
@MainActor
@Observable
final class TextComposerController {
    private enum Step: Sendable {
        case key(usage: UInt16, mods: InputModifiers, count: Int)
        case text(String)
    }

    /// Bàn phím hệ thống đang được yêu cầu mở (điều khiển bởi nút bàn phím và nút "ẩn bàn phím").
    var isActive = false
    /// Chiều cao bàn phím + thanh phím phụ đang che đáy màn hình (điểm); do view video cập nhật.
    var obscuredHeight: CGFloat = 0
    /// Chữ đang soạn dở (Telex): chỉ hiện làm xem trước, chưa gửi.
    var preview = ""
    private(set) var modifiers = StickyModifiers()

    /// ComposerInputView đăng ký: chốt chữ đang soạn rồi xoá ô, để phím điều hướng không làm lệch ô với Mac.
    @ObservationIgnored var commitAndClearField: (() -> Void)?

    @ObservationIgnored private let session: ViewerSession
    @ObservationIgnored private let steps: AsyncStream<Step>.Continuation
    @ObservationIgnored private var synced = ""

    private static let channelGap: Duration = .milliseconds(30)

    init(session: ViewerSession) {
        self.session = session
        let (stream, continuation) = AsyncStream.makeStream(of: Step.self)
        steps = continuation
        Task { [weak self] in
            for await step in stream { await self?.run(step) }
        }
    }

    deinit { steps.finish() }

    // MARK: Chữ từ ô gõ

    /// Gọi khi nội dung ô gõ đã chốt (không còn văn bản đang soạn dở). Trả `true` nếu chữ đã đi như phím tắt và ô cần xoá.
    @discardableResult
    func textChanged(to text: String) -> Bool {
        let edit = TextEditDiff.edit(from: synced, to: text)
        synced = text
        if edit.deleteCount > 0 { steps.yield(.key(usage: HidUsage.backspace, mods: [], count: edit.deleteCount)) }
        guard !edit.insert.isEmpty else { return false }
        let mods = modifiers.consume()
        if edit.deleteCount == 0, !mods.isEmpty, let usage = edit.insert.first.flatMap(HidKeyMap.hidUsage(forCharacter:)), edit.insert.count == 1 {
            steps.yield(.key(usage: usage, mods: mods, count: 1))
            synced = ""
            return true
        }
        steps.yield(.text(edit.insert))
        return false
    }

    /// Backspace khi ô đã rỗng vẫn xoá chữ đã gõ trước đó trên Mac.
    func backspaceOnEmptyField() { steps.yield(.key(usage: HidUsage.backspace, mods: [], count: 1)) }

    func returnPressed() {
        synced = ""
        steps.yield(.key(usage: HidUsage.return, mods: modifiers.consume(), count: 1))
    }

    func reset() {
        synced = ""
        preview = ""
        modifiers.reset()
    }

    // MARK: Thanh phím phụ

    func tapKey(_ usage: UInt16) {
        if usage != HidUsage.backspace { commitAndClearField?() }
        synced = usage == HidUsage.backspace ? synced : ""
        steps.yield(.key(usage: usage, mods: modifiers.consume(), count: 1))
    }

    func tapModifier(_ modifier: InputModifiers) {
        modifiers.tap(modifier, nowMs: Int64(ProcessInfo.processInfo.systemUptime * 1000))
    }

    // MARK: Chạy tuần tự

    private func run(_ step: Step) async {
        switch step {
        case .key(let usage, let mods, let count):
            for _ in 0..<count { session.sendInput([.key(usage: usage, down: true, mods: mods), .key(usage: usage, down: false, mods: mods)]) }
        case .text(let text):
            if !(await session.sendText(text)) { return }
        }
        try? await Task.sleep(for: Self.channelGap)
    }
}

/// HID usage các phím trên thanh phím phụ.
enum HidUsage {
    static let `return`: UInt16 = 0x28, escape: UInt16 = 0x29, backspace: UInt16 = 0x2A, tab: UInt16 = 0x2B
    static let right: UInt16 = 0x4F, left: UInt16 = 0x50, down: UInt16 = 0x51, up: UInt16 = 0x52
}
