package com.zalweb.tabby

import org.junit.Assert.*
import org.junit.Test

class PushTapDeliveryTest {
    @Test fun earlyIntentRetainsNewestPayloadUntilDartHandshake() {
        val delivery = PushTapDelivery<String>()
        var intent: String? = "first"
        var destructiveReads = 0
        val take = { destructiveReads++; val value = intent; intent = null; value }
        assertNull(delivery.onNewIntent(take))
        intent = "newest"
        assertNull(delivery.onNewIntent(take))
        assertEquals(0, destructiveReads)
        assertEquals("newest", delivery.listenerReady(take))
        assertNull(delivery.listenerReady(take))
        intent = "warm"
        assertEquals("warm", delivery.onNewIntent(take))
    }

    @Test fun scopeIsCheckedAtConsumptionRatherThanBeforeReadiness() {
        val delivery = PushTapDelivery<String>()
        var bindingAllowed = true
        var checks = 0
        val scopedTake = { checks++; if (bindingAllowed) "allowed" else null }
        assertNull(delivery.onNewIntent(scopedTake))
        bindingAllowed = false
        assertNull(delivery.listenerReady(scopedTake))
        assertEquals(1, checks)
        bindingAllowed = true
        assertEquals("allowed", delivery.onNewIntent(scopedTake))
    }
}
