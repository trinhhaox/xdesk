package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.ControlMessage

/** Host xin duyệt quyền điều khiển cho agent AI; UI hiện hộp thoại Cho phép / Từ chối. `expiresAtMs` theo đồng hồ viewer. */
data class AgentApprovalRequest(val id: String, val agentName: String, val summary: String, val expiresAtMs: Long)

/**
 * Giữ tối đa một yêu cầu duyệt đang chờ: yêu cầu mới thay yêu cầu cũ, tự hết hạn đúng hạn host,
 * và [take] lấy yêu cầu đúng một lần nên chỉ gửi được một trả lời. [onChange] báo `null` khi hết/đã trả lời.
 */
internal class AgentApprovalGate(
    private val nowMs: () -> Long,
    private val schedule: (delayMs: Long, task: () -> Unit) -> Unit,
    private val onChange: (AgentApprovalRequest?) -> Unit,
) {
    private val lock = Any()
    private var current: AgentApprovalRequest? = null

    val pending: AgentApprovalRequest? get() = synchronized(lock) { current }

    /** [hostNowMs] = giờ host ước lượng từ ClockSync; chưa đồng bộ thì coi hai đồng hồ trùng nhau. */
    fun receive(approve: ControlMessage.AgentApprove, hostNowMs: Long?) {
        if (!approve.isRequest) return
        val remainingMs = (approve.expiresAt ?: return) - (hostNowMs ?: nowMs())
        if (remainingMs <= 0) return
        val request = AgentApprovalRequest(approve.requestId, approve.agentName ?: DEFAULT_AGENT_NAME, approve.summary.orEmpty(), nowMs() + remainingMs)
        synchronized(lock) { current = request }
        onChange(request)
        schedule(remainingMs) { expire(request.id) }
    }

    /** Lấy và xoá yêu cầu đang chờ; lần gọi thứ hai trả `null`. */
    fun take(): AgentApprovalRequest? {
        val taken = synchronized(lock) { current.also { current = null } }
        if (taken != null) onChange(null)
        return taken
    }

    fun clear() { take() }

    private fun expire(id: String) {
        val expired = synchronized(lock) { if (current?.id == id) current.also { current = null } else null }
        if (expired != null) onChange(null)
    }

    private companion object {
        const val DEFAULT_AGENT_NAME = "Agent AI"
    }
}
