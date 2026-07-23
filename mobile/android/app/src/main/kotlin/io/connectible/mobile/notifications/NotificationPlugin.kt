package io.connectible.mobile.notifications

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Dart and the native notification-access surface (T-B4).
 *
 * Two channels:
 *  - `connectible/notifications` (method): `isGranted`, `openSettings`,
 *    `openAppSettings` (T-X33 fallback when the notification-access page
 *    itself doesn't resolve on this ROM), `cancel` (T-K4: clears a live
 *    system notification in response to a remote dismiss command).
 *  - `connectible/notification_events` (event): drains
 *    [ConnectibleNotificationListener.events] to Dart, posted/removed and
 *    the connected/disconnected lifecycle signals.
 *
 * We never start the listener ourselves -- Android forbids it and rightly
 * so. The flow is always: read `isGranted`; if false, `openSettings`
 * (which deep-links the user to the system Notification-access page); the
 * system binds our service on grant, which fires onListenerConnected ->
 * a "connected" event here -> the Dart UI flips to "granted".
 */
object NotificationPlugin {
    private const val METHOD_CHANNEL = "connectible/notifications"
    private const val EVENT_CHANNEL = "connectible/notification_events"

    private var eventSink: EventChannel.EventSink? = null
    private var drainThread: Thread? = null
    @Volatile private var draining = false

    fun registerWith(flutterEngine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result -> handleMethod(call, result, appContext) }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    startDraining()
                    // Immediately reflect the current grant state so the UI
                    // does not have to round-trip a method call on startup.
                    val granted = ConnectibleNotificationListener.componentEnabled(appContext)
                    ConnectibleNotificationListener.connected = granted
                    sink?.success(mapOf("type" to if (granted) "connected" else "disconnected"))
                }

                override fun onCancel(arguments: Any?) {
                    stopDraining()
                    eventSink = null
                }
            })
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result, context: Context) {
        when (call.method) {
            "isGranted" -> {
                result.success(ConnectibleNotificationListener.componentEnabled(context))
            }
            "openSettings" -> {
                val opened = openNotificationAccessSettings(context)
                result.success(opened)
            }
            "openAppSettings" -> {
                val opened = openGeneralAppSettings(context)
                result.success(opened)
            }
            "cancel" -> {
                // T-K4: a remote dismiss command for a notification we
                // ourselves mirrored. Best-effort -- see
                // ConnectibleNotificationListener.cancelByNotificationId's
                // own doc for exactly when this can and can't succeed.
                val id = call.argument<String>("notification_id").orEmpty()
                result.success(ConnectibleNotificationListener.cancelByNotificationId(id))
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Deep-links into the system Notification-access settings. Returns true
     * if the intent resolved (the page exists on this device); false if not
     * (some heavily-customized ROMs lack it), in which case the Dart UI
     * should fall back to the generic settings page.
     */
    private fun openNotificationAccessSettings(context: Context): Boolean {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent.resolveActivity(context.packageManager) == null) {
            return false
        }
        context.startActivity(intent)
        return true
    }

    /**
     * Fallback (T-X33) for the rare ROM where
     * [openNotificationAccessSettings]'s dedicated intent doesn't resolve:
     * this app's own general settings page, where the user can still find
     * notification access (usually under Permissions/App info) manually.
     * Nearly universally available -- unlike the notification-listener
     * page, this is a core platform intent every launcher/Settings app
     * must support.
     */
    private fun openGeneralAppSettings(context: Context): Boolean {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", context.packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent.resolveActivity(context.packageManager) == null) {
            return false
        }
        context.startActivity(intent)
        return true
    }

    private fun startDraining() {
        if (draining) return
        draining = true
        // Drain on a dedicated background thread: poll the bounded queue
        // (blocking, no busy-wait) and post each event to the UI-thread
        // event sink. Stopping cancels via interrupt.
        drainThread = Thread({
            while (draining) {
                try {
                    val event = ConnectibleNotificationListener.events.take()
                    val sink = eventSink
                    if (sink != null) {
                        // EventChannel sinks must be touched on the platform
                        // (UI) thread; the binary messenger serializes this.
                        mainHandler.post { sink.success(event) }
                    }
                } catch (_: InterruptedException) {
                    break
                }
            }
        }, "ConnectibleNotifDrain").apply {
            isDaemon = true
            start()
        }
    }

    private fun stopDraining() {
        draining = false
        drainThread?.interrupt()
        drainThread = null
    }

    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
}
