package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.ControlMessage

data class AgentHelpRequest(val id: String, val reason: String)

internal class AgentHelpGate(
    private val onChange: (AgentHelpRequest?) -> Unit,
) {
    private val lock = Any()
    private var current: AgentHelpRequest? = null

    val pending: AgentHelpRequest? get() = synchronized(lock) { current }

    fun receive(help: ControlMessage.AgentHelp) {
        if (help.isResolved) return
        val request = AgentHelpRequest(help.requestId, help.reason ?: "Cần người dùng hỗ trợ")
        synchronized(lock) { current = request }
        onChange(request)
    }

    fun take(): AgentHelpRequest? {
        val taken = synchronized(lock) { current.also { current = null } }
        if (taken != null) onChange(null)
        return taken
    }

    fun clear() { take() }
}
