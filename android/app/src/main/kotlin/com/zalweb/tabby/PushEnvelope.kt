package com.zalweb.tabby

import java.util.UUID

internal data class PushScope(val account: String, val binding: String)
/** Reading an intent consumes its extras; Dart must own the first delivery. */
internal class PushTapDelivery<T> {
    private var ready = false
    fun onNewIntent(take: () -> T?): T? = if (ready) take() else null
    fun listenerReady(take: () -> T?): T? {
        ready = true
        return take()
    }
}

internal data class PushEnvelope(val account: String, val binding: String, val event: String, val tab: String) {
    fun allowed(scope: PushScope?): Boolean = scope != null && account == scope.account && binding == scope.binding
    fun asMap(): Map<String, String> = mapOf("account" to account, "binding" to binding, "event" to event, "tab" to tab)
    companion object {
        fun parse(data: Map<String, String>): PushEnvelope? {
            if (data["v"] != "1" || data["kind"] != "reminder") return null
            val keys = listOf("account", "binding", "event", "tab")
            if (keys.any { key -> runCatching { UUID.fromString(data[key]).toString() == data[key] }.getOrDefault(false).not() }) return null
            return PushEnvelope(data.getValue("account"), data.getValue("binding"), data.getValue("event"), data.getValue("tab"))
        }
    }
}
