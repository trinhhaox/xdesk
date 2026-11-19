package vn.xox.xdesk.transport

/** Trạng thái phiên viewer. */
sealed interface ViewerState {
    object Idle : ViewerState
    object Connecting : ViewerState
    object Streaming : ViewerState
    class Failed(val message: String, val code: TransportErrorCode? = null) : ViewerState
}
