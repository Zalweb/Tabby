package com.zalweb.tabby

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** Data-only messages are checked before any OS display, including closed app. */
class TabbyPushService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        // Never log tokens. Refresh registration while Flutter is alive; otherwise
        // foreground/resume obtains the current token and repairs the association.
        Handler(Looper.getMainLooper()).post { PushBridge.changed?.invoke() }
    }
    override fun onMessageReceived(message: RemoteMessage) {
        // A notification payload could bypass this check in the background. The
        // controlled sender uses data only; do not accept a mixed payload here.
        if (message.notification != null) return
        val envelope = PushEnvelope.parse(message.data) ?: return
        synchronized(PushBridge.lock) {
            if (!envelope.allowed(PushBridge.scope(this))) return
            if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) return
            val process = ActivityManager.RunningAppProcessInfo()
            ActivityManager.getMyMemoryState(process)
            if (process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) return
            val preferences = getSharedPreferences(PushBridge.PREFERENCES, Context.MODE_PRIVATE)
            val seen = preferences.getStringSet("seen", emptySet())!!.toMutableSet()
            if (seen.contains(envelope.event)) return
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(
                "tabby_background_reminders", "Shared tab reminders", NotificationManager.IMPORTANCE_DEFAULT))
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                data = Uri.parse("tabby-push://${envelope.binding}/${envelope.event}")
                envelope.asMap().forEach { (key, value) -> putExtra("tabby_push_$key", value) }
            }
            val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(this, "tabby_background_reminders")
                .setSmallIcon(R.drawable.ic_tabby_notification)
                .setContentTitle("A reminder in Tabby")
                .setContentText("Open Tabby to review your shared tab.")
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setAutoCancel(true).setContentIntent(pending).build()
            try { manager.notify("tabby-push:${envelope.event}", 0, notification) }
            catch (_: SecurityException) { return }
            seen.add(envelope.event)
            preferences.edit().putStringSet("seen", seen.toList().takeLast(200).toSet()).commit()
        }
    }
}

internal object PushBridge {
    const val PREFERENCES = "tabby_push_scope_v1"
    val lock = Any()
    var changed: (() -> Unit)? = null
    fun scope(context: Context): PushScope? {
        val p = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val account = p.getString("account", null) ?: return null
        val binding = p.getString("binding", null) ?: return null
        return PushScope(account, binding)
    }
    fun setScope(context: Context, account: String?, binding: String?) = synchronized(lock) {
        val previous = scope(context)
        val p = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        p.edit().putString("account", account).putString("binding", binding).commit()
        if (previous?.account != account || previous?.binding != binding) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.activeNotifications.filter { it.tag?.startsWith("tabby-push:") == true }
                .forEach { manager.cancel(it.tag, it.id) }
        }
    }
}
