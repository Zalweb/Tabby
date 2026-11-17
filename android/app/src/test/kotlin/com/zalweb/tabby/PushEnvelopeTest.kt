package com.zalweb.tabby

import org.junit.Assert.*
import org.junit.Test

class PushEnvelopeTest {
    private val account = "00000000-0000-4000-8000-000000000001"
    private val binding = "00000000-0000-4000-8000-000000000002"
    private val event = "00000000-0000-4000-8000-000000000003"
    private val tab = "00000000-0000-4000-8000-000000000004"
    private fun data() = mapOf("v" to "1", "kind" to "reminder", "account" to account,
        "binding" to binding, "event" to event, "tab" to tab)
    @Test fun exactBindingRequired() {
        val envelope = PushEnvelope.parse(data())!!
        assertTrue(envelope.allowed(PushScope(account, binding)))
        assertFalse(envelope.allowed(null))
        assertFalse(envelope.allowed(PushScope(account, event)))
        assertFalse(envelope.allowed(PushScope(event, binding)))
    }
    @Test fun malformedOrForeignPayloadRejected() {
        assertNull(PushEnvelope.parse(data() - "account"))
        assertNull(PushEnvelope.parse(data() + ("tab" to "../../tabs/private")))
        assertNull(PushEnvelope.parse(data() + ("v" to "2")))
        assertNull(PushEnvelope.parse(data() + ("kind" to "payment")))
        assertNull(PushEnvelope.parse(data() + ("tab" to "1-1-1-1-1")))
    }
}
