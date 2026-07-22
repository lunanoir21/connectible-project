package io.connectible.mobile.notifications

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.concurrent.LinkedBlockingQueue

/**
 * Mirrors the device's notifications to Connectible (T-B4).
 *
 * The Android system binds and drives this service once the user grants
 * "Notification access" in system settings; we cannot (and must not) start
 * it ourselves. On each post/remove we push a small, payload-only map onto
 * [Companion.events], a bounded queue that the Dart side drains over an
 * event channel. No icons/PIDs/extras are forwarded by default -- only the
 * minimal fields the desktop mirror needs (package/app name, title, text,
 * key, post time), so we never leak more than the system itself shows.
 *
 * Lifecycle note: [onListenerConnected] / [onListenerDisconnected] are how
 * Android tells us the permission was granted/revoked. We reflect both as
 * synthetic "connected"/"disconnected" events so the Dart UI stays in sync
 * without polling [getComponentEnabledSetting].
 */
class ConnectibleNotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        Log.i(TAG, "listener connected (permission granted)")
        Companion.connected = true
        Companion.events.offer(mapOf("type" to "connected"))
    }

    override fun onListenerDisconnected() {
        Log.i(TAG, "listener disconnected (permission revoked)")
        Companion.connected = false
        Companion.events.offer(mapOf("type" to "disconnected"))
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val map = mapNotification(sbn, isRemoval = false) ?: return
        Companion.events.offer(map)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        val map = mapNotification(sbn, isRemoval = true) ?: return
        Companion.events.offer(map)
    }

    private fun mapNotification(sbn: StatusBarNotification?, isRemoval: Boolean): Map<String, Any>? {
        if (sbn == null) return null
        val n: Notification = sbn.notification ?: return null
        // Foreground-service notifications are how media players, VPNs,
        // navigation apps, and (this app itself) stay alive. Mirroring
        // them is noise at best and a loop at worst (we'd mirror our own
        // transfer-progress notification), so skip the flag entirely.
        if (n.flags and Notification.FLAG_FOREGROUND_SERVICE != 0) return null
        // Group-summary notifications carry no user-visible content; only
        // their children matter, and those arrive as their own posts.
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return null

        val extras: Bundle = n.extras
        val pkg = sbn.packageName ?: ""
        val appName = resolveAppName(pkg)
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val sub = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty()
        val body = when {
            text.isNotBlank() -> text
            sub.isNotBlank() -> sub
            else -> ""
        }

        // A stable id the desktop can correlate later dismissals against.
        // We combine package + tag + id (Android's own de-dup key) and do
        // not include the actual notification object or any extras map.
        val key = "${pkg}#${sbn.tag ?: ""}#${sbn.id}"

        return mapOf(
            "type" to if (isRemoval) "removed" else "posted",
            "notification_id" to key,
            "package_name" to pkg,
            "app_name" to appName,
            "title" to title,
            "body" to body,
            "posted_at_ms" to sbn.postTime,
            "is_dismissal" to isRemoval,
        )
    }

    private fun resolveAppName(pkg: String): String {
        if (pkg.isEmpty()) return ""
        return try {
            val pm = packageManager
            val info = pm.getApplicationInfo(pkg, PackageManager.GET_META_DATA)
            pm.getApplicationLabel(info).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            pkg // fall back to the package name; better than empty
        }
    }

    companion object {
        private const val TAG = "ConnectibleNotifListener"

        /** Reflects the last [onListenerConnected/Disconnected] callback. */
        @Volatile
        var connected: Boolean = false

        /**
         * Bounded buffer of pending notification events for the Dart side to
         * drain. Dropping at capacity is intentional: notification mirroring
         * is best-effort; a flood must never grow unbounded (RULES.md) and
         * must never OOM the app.
         */
        private const val MAX_EVENTS = 512
        val events: LinkedBlockingQueue<Map<String, Any>> = LinkedBlockingQueue(MAX_EVENTS)

        fun resetForTest() {
            connected = false
            events.clear()
        }

        /**
         * Whether the user has enabled our component in the system
         * "Notification access" settings. Cheap to call; the Dart side uses
         * this to decide whether to deep-link to the settings page.
         */
        @JvmStatic
        fun componentEnabled(context: Context): Boolean {
            val enabledListeners =
                android.provider.Settings.Secure.getString(
                    context.contentResolver,
                    "enabled_notification_listeners",
                ) ?: return false
            val componentName = ComponentName(context, ConnectibleNotificationListener::class.java)
            val flat = componentName.flattenToString()
            // The string is a colon-separated list of flattened component names.
            val items = enabledListeners.split(":")
            for (item in items) {
                if (item.equals(flat, ignoreCase = true)) return true
            }
            return false
        }
    }
}
