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
import java.util.concurrent.ConcurrentHashMap
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
 *
 * T-K4 finding: dismissing a *received* notification (desktop -> phone
 * direction) works reliably for Connectible's own use case.
 * [NotificationListenerService.cancelNotification] only requires the
 * listener to currently hold visibility into that notification (i.e. it
 * is still live and was posted while we were connected) -- both hold for
 * anything we ourselves already mirrored to the desktop, since we only
 * ever forward what [onNotificationPosted] actually saw. It is *not*
 * guaranteed to work for arbitrary third-party notifications on every
 * OEM (some heavily-customized ROMs restrict cross-app cancellation),
 * but that's outside what this feature needs. See
 * [Companion.cancelByNotificationId].
 */
class ConnectibleNotificationListener : NotificationListenerService() {

    override fun onCreate() {
        super.onCreate()
        Companion.instance = this
    }

    override fun onDestroy() {
        if (Companion.instance === this) Companion.instance = null
        super.onDestroy()
    }

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
        // Remember the real system key under our synthetic id (T-K4) so a
        // later dismiss command for this id -- arriving over the wire
        // with only the synthetic id, not Android's own key -- can still
        // find the live notification to cancel.
        sbn?.let { Companion.activeKeys[map["notification_id"] as String] = it.key }
        Companion.events.offer(map)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        val map = mapNotification(sbn, isRemoval = true) ?: return
        Companion.activeKeys.remove(map["notification_id"] as String)
        Companion.events.offer(map)
    }

    private fun mapNotification(sbn: StatusBarNotification?, isRemoval: Boolean): Map<String, Any>? {
        if (sbn == null) return null
        val n: Notification = sbn.notification ?: return null
        // Foreground-service notifications are how media players, VPNs,
        // and navigation apps stay alive -- mirroring them is just noise.
        // Connectible itself has no foreground service yet (T-X36,
        // decision-gated: a receiving-role one is planned but not built),
        // but skip the flag unconditionally regardless of source so this
        // doesn't need revisiting when it lands -- a self-mirror loop
        // (mirroring our own receiving-status notification) would be
        // exactly the kind of noise this filter exists to prevent.
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

        /**
         * The currently-bound service instance, so [cancelByNotificationId]
         * (a companion/static entry point, called from [NotificationPlugin]
         * with no instance of its own) has something to call the instance
         * method [cancelNotification] on. Null whenever the system hasn't
         * bound us (matches [connected]'s own lifecycle, but tracked
         * separately since this is `onCreate`/`onDestroy`-scoped rather
         * than `onListenerConnected`/`onListenerDisconnected`-scoped).
         */
        @Volatile
        private var instance: ConnectibleNotificationListener? = null

        /**
         * Maps our synthetic `notification_id` (pkg#tag#id, sent over the
         * wire) to Android's own [StatusBarNotification.getKey], the only
         * thing [cancelNotification] actually accepts (T-K4). Populated on
         * every post, removed on every removal (ours or the user's) --
         * naturally bounded by the number of currently-live notifications,
         * not by time or a fixed cap.
         */
        private val activeKeys = ConcurrentHashMap<String, String>()

        /**
         * Cancels the live system notification matching a remote dismiss
         * command's `notification_id` (T-K4/T-K5), if we're still tracking
         * it and the listener is currently bound. Returns false (not an
         * error) if either isn't true -- the notification may have already
         * been dismissed locally, or access may have been revoked since.
         */
        fun cancelByNotificationId(id: String): Boolean {
            val key = activeKeys[id] ?: return false
            val service = instance ?: return false
            return try {
                service.cancelNotification(key)
                true
            } catch (e: Throwable) {
                Log.w(TAG, "cancelNotification failed: ${e.message}")
                false
            }
        }

        fun resetForTest() {
            connected = false
            events.clear()
            instance = null
            activeKeys.clear()
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
