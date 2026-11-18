import Foundation
import XdeskInput
import XdeskViewer
import XdeskWire

/// Biến thay đổi của ô gõ thành input gửi host, theo đúng thứ tự.
/// Phím (Backspace/Return) đi UDP còn chữ đi TCP nên giữa hai loại có khoảng nghỉ ngắn để host nhận đúng thứ tự.
@MainActor
final class TextComposerController {
    private enum Step: Sendable {
        case backspaces(Int)
        case text(String)
        case returnKey
    }

    private static let hidBackspace: UInt16 = 0x2A
    private static let hidReturn: UInt16 = 0x28
    private static let channelGap: Duration = .milliseconds(30)

    private let session: ViewerSession
    private let steps: AsyncStream<Step>.Continuation
    private var synced = ""

    init(session: ViewerSession) {
        self.session = session
        let (stream, continuation) = AsyncStream.makeStream(of: Step.self)
        steps = continuation
        Task { [weak self] in
            for await step in stream { await self?.run(step) }
        }
    }

    deinit { steps.finish() }

    /// Gọi khi nội dung ô gõ đã chốt (không còn văn bản đang soạn dở).
    func textChanged(to text: String) {
        let edit = TextEditDiff.edit(from: synced, to: text)
        synced = text
        if edit.deleteCount > 0 { steps.yield(.backspaces(edit.deleteCount)) }
        if !edit.insert.isEmpty { steps.yield(.text(edit.insert)) }
    }

    /// Backspace khi ô đã rỗng vẫn xoá chữ đã gõ trước đó trên Mac.
    func backspaceOnEmptyField() { steps.yield(.backspaces(1)) }

    func returnPressed() {
        synced = ""
        steps.yield(.returnKey)
    }

    func reset() { synced = "" }

    private func run(_ step: Step) async {
        switch step {
        case .backspaces(let count):
            for _ in 0..<count { session.sendInput(Self.tap(Self.hidBackspace)) }
        case .text(let text):
            if !(await session.sendText(text)) { return }
        case .returnKey:
            session.sendInput(Self.tap(Self.hidReturn))
        }
        try? await Task.sleep(for: Self.channelGap)
    }

    private static func tap(_ usage: UInt16) -> [InputEvent] {
        [.key(usage: usage, down: true), .key(usage: usage, down: false)]
    }
}
