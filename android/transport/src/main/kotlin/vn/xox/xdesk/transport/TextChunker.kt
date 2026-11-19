package vn.xox.xdesk.transport

/** Chia chuỗi UTF-8 thành đoạn ≤ `maxBytes` byte, không cắt giữa cặp surrogate (emoji) hay ký tự ghép dựng sẵn. */
object TextChunker {
    fun splitUtf8(text: String, maxBytes: Int): List<String> {
        require(maxBytes >= 4) { "maxBytes phải chứa được một code point" }
        val chunks = ArrayList<String>()
        val current = StringBuilder()
        var size = 0
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            val len = Character.charCount(cp)
            val cost = String(Character.toChars(cp)).toByteArray(Charsets.UTF_8).size
            if (size + cost > maxBytes && current.isNotEmpty()) {
                chunks += current.toString()
                current.setLength(0)
                size = 0
            }
            current.appendCodePoint(cp)
            size += cost
            i += len
        }
        if (current.isNotEmpty()) chunks += current.toString()
        return chunks
    }
}
