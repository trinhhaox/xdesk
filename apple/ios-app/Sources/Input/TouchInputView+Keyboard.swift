import UIKit

extension TouchInputView {
    // MARK: Bàn phím vật lý

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !keyboard.pressesBegan(presses) { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !keyboard.pressesEnded(presses) { super.pressesEnded(presses, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        keyboard.releaseAll()
        super.pressesCancelled(presses, with: event)
    }
}
