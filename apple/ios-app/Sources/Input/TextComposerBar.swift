import SwiftUI
import UIKit

/// Ô gõ chữ dùng bàn phím hệ thống (Telex tiếng Việt do iOS xử lý); chỉ gửi văn bản đã chốt.
struct TextComposerBar: View {
    let controller: TextComposerController
    let onClose: () -> Void

    var body: some View {
        ComposerField(controller: controller, onClose: onClose)
            .frame(height: 40)
            .padding(.horizontal, 12)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Ô gõ chữ gửi sang Mac")
    }
}

private struct ComposerField: UIViewRepresentable {
    let controller: TextComposerController
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller, onClose: onClose) }

    func makeUIView(context: Context) -> BackspaceAwareTextField {
        let field = BackspaceAwareTextField()
        field.attributedPlaceholder = NSAttributedString(
            string: "Gõ chữ gửi sang Mac…", attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.5)]
        )
        field.textColor = .white
        field.tintColor = .white
        field.returnKeyType = .send
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        field.delegate = context.coordinator
        field.onBackspaceWhenEmpty = { context.coordinator.controller.backspaceOnEmptyField() }
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: BackspaceAwareTextField, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        let controller: TextComposerController
        let onClose: () -> Void

        init(controller: TextComposerController, onClose: @escaping () -> Void) {
            self.controller = controller
            self.onClose = onClose
        }

        @objc func editingChanged(_ field: UITextField) {
            guard field.markedTextRange == nil else { return }
            controller.textChanged(to: field.text ?? "")
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            controller.returnPressed()
            field.text = ""
            return false
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            controller.reset()
            onClose()
        }
    }
}

/// `deleteBackward` vẫn chạy khi ô rỗng, để Backspace xoá được chữ đã gõ trước đó.
private final class BackspaceAwareTextField: UITextField {
    var onBackspaceWhenEmpty: (() -> Void)?

    override func deleteBackward() {
        let wasEmpty = (text ?? "").isEmpty
        super.deleteBackward()
        if wasEmpty { onBackspaceWhenEmpty?() }
    }
}
