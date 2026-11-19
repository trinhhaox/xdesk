package vn.xox.xdesk.app.input

/** Việc cần gửi host sau một thao tác của IME. */
sealed interface TextAction {
    data class Insert(val text: String) : TextAction
    data class Backspaces(val count: Int) : TextAction
}

/**
 * Cầu nối InputConnection → host. Bộ gõ Telex (Gboard, Laban Key) sửa chữ đang soạn nhiều lần (`setComposingText`)
 * rồi mới chốt; ta chỉ gửi chữ ĐÃ CHỐT (`commitText`/`finishComposingText`) qua `input.text`, nên "việt" không bao giờ
 * lộ dạng "viet"/"viê". Xoá lùi khi đang soạn chỉ sửa bản nháp cục bộ; xoá lùi khi không soạn → backspace tới host.
 * Không phụ thuộc Android để test được. Không thread-safe (main thread).
 */
class TextInputBridge {
    private var composing = ""

    val composingText: String get() = composing

    fun setComposing(text: String): List<TextAction> {
        composing = text
        return emptyList()
    }

    /** Chốt chữ soạn dở (kết thúc composition mà không có chữ mới). */
    fun finishComposing(): List<TextAction> = flush()

    fun commit(text: String): List<TextAction> {
        composing = ""
        return if (text.isEmpty()) emptyList() else listOf(TextAction.Insert(text))
    }

    /** `before` tính theo UTF-16 như `InputConnection.deleteSurroundingText`. */
    fun deleteBefore(before: Int): List<TextAction> {
        if (before <= 0) return emptyList()
        if (composing.isNotEmpty()) {
            composing = composing.dropLast(minOf(before, composing.length))
            return emptyList()
        }
        return listOf(TextAction.Backspaces(before))
    }

    private fun flush(): List<TextAction> {
        val pending = composing
        composing = ""
        return if (pending.isEmpty()) emptyList() else listOf(TextAction.Insert(pending))
    }
}
