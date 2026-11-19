package vn.xox.xdesk.app

enum class Screen { HOSTS, PAIR, STREAM, SECURITY }

/** Kết quả hiển thị của lần kết nối gần nhất. `repairable` = nên đề nghị "Ghép đôi lại". */
data class ConnectionFailure(val message: String, val repairable: Boolean)
