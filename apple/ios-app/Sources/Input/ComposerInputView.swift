import UIKit

/// Ô gõ ẩn dùng bàn phím hệ thống (Telex tiếng Việt do iOS xử lý); chỉ gửi văn bản đã chốt, chữ đang soạn chỉ hiện làm xem trước.
/// Thanh phím phụ gắn làm `inputAccessoryView` nên đi cùng bàn phím và co giãn theo nó.
@MainActor
final class ComposerInputView: UITextField, UITextFieldDelegate {
    private let controller: TextComposerController

    init(controller: TextComposerController) {
        self.controller = controller
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        alpha = 0.01
        isAccessibilityElement = false
        autocorrectionType = .no
        spellCheckingType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        returnKeyType = .send
        delegate = self
        inputAccessoryView = KeyboardAccessoryView(controller: controller)
        addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        controller.commitAndClearField = { [weak self] in self?.commitAndClear() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func editingChanged() {
        if markedTextRange != nil {
            controller.preview = markedTextRange.flatMap { text(in: $0) } ?? ""
            return
        }
        controller.preview = ""
        if controller.textChanged(to: text ?? "") { text = "" }
    }

    private func commitAndClear() {
        unmarkText()
        controller.preview = ""
        controller.textChanged(to: text ?? "")
        text = ""
    }

    func textFieldShouldReturn(_ field: UITextField) -> Bool {
        commitAndClear()
        controller.returnPressed()
        return false
    }

    func textFieldDidEndEditing(_ field: UITextField) {
        controller.reset()
        controller.isActive = false
    }

    /// `deleteBackward` vẫn chạy khi ô rỗng, để Backspace xoá được chữ đã gõ trước đó.
    override func deleteBackward() {
        let wasEmpty = (text ?? "").isEmpty
        super.deleteBackward()
        if wasEmpty { controller.backspaceOnEmptyField() }
    }
}
