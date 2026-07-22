package io.connectible.mobile.notifications

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Dart and the native notification-access surface (T-B4).
 *
 * Two channels:
 *  - `connectible/notifications` (method): `isGranted`, `openSettings`,
 *    `requestUnbind`/`requestRebind` (best-effort self-toggle via the
 *    requestUnbind/requestRebind APIs Android added for exactly this).
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
    private const val TAG = "NotificationPlugin"
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
            "requestRebind" -> {
                // Best-effort toggle. May throw SecurityException on some
                // OEMs if the component isn't enabled; surface false rather
                // than crash. The canonical path is the settings page.
                try {
                    val cls = ConnectibleNotificationListener::class.java
                    val name = ComponentName(context, cls)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        requestRebindComponent(name)
                    }
                    result.success(true)
                } catch (e: Throwable) {
                    Log.w(TAG, "requestRebind failed: ${e.message}")
                    result.success(false)
                }
            }
            "requestUnbind" -> {
                try {
                    val cls = ConnectibleNotificationListener::class.java
                    val name = ComponentName(context, cls)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        requestUnbindComponent(name)
                    }
                    result.success(true)
                } catch (e: Throwable) {
                    Log.w(TAG, "requestUnbind failed: ${e.message}")
                    result.success(false)
                }
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
     * On Android Q+, requestRebind/requestUnbind are no-ops unless the
     * component is already enabled by the user. They are nevertheless the
     * documented way for an app to (re)request a bind without the user
     * leaving the app. We call them through reflection guarded by the SDK
     * check above so older toolchains don't need the newer reference.
     */
    private fun requestRebindComponent(name: ComponentName) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // The static NotificationListenerService.requestRebind API was
            // added at API 33; on older OS levels we simply can't self-bind.
            val listener = ConnectibleNotificationListener::class.java
            val method = listener.getMethod("requestRebind", ComponentName::class.java)
            method.invoke(null, name)
        }
    }

    private fun requestUnbindComponent(name: ComponentName) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val listener = ConnectibleNotificationListener::class.java
            val method = listener.getMethod("requestUnbind", ComponentName::class.java)
            method.invoke(null, name)
        }
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
