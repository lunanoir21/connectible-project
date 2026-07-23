package io.connectible.mobile.net

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart bridge for [ReceivingForegroundService] (T-X36).
 *
 * One channel (`connectible/receiving_service`) with two methods:
 *  - `start`: starts (or updates, if already running -- `startForeground`
 *    with the same notification id just replaces the content) the
 *    foreground service with the given `title`/`text` args, already
 *    localized on the Dart side (this layer has no i18n access, mirrors
 *    [NotificationPlugin]/[MulticastLockPlugin]'s same architecture).
 *  - `stop`: stops it.
 *
 * Both are best-effort: a failure here must never crash the app or block
 * the Dart-side toggle, since this service is a background-reliability
 * aid, not a correctness requirement -- everything it protects (the
 * inbound server, mDNS advertise, heartbeat) already works without it,
 * just less reliably once the app backgrounds.
 */
object ReceivingServicePlugin {
    private const val TAG = "ReceivingService"
    private const val CHANNEL = "connectible/receiving_service"

    fun registerWith(flutterEngine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result, appContext) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result, context: Context) {
        when (call.method) {
            "start" -> {
                try {
                    val title = call.argument<String>("title").orEmpty()
                    val text = call.argument<String>("text").orEmpty()
                    val intent = Intent(context, ReceivingForegroundService::class.java)
                        .putExtra(ReceivingForegroundService.EXTRA_TITLE, title)
                        .putExtra(ReceivingForegroundService.EXTRA_TEXT, text)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                    result.success(null)
                } catch (e: Throwable) {
                    // Never crash the app over a best-effort reliability aid
                    // (e.g. a OEM that blocks foreground services outright,
                    // or a missing POST_NOTIFICATIONS grant on API 33+).
                    Log.w(TAG, "start failed: ${e.message}")
                    result.error("start_failed", e.message, null)
                }
            }
            "stop" -> {
                try {
                    context.stopService(Intent(context, ReceivingForegroundService::class.java))
                    result.success(null)
                } catch (e: Throwable) {
                    Log.w(TAG, "stop failed: ${e.message}")
                    result.error("stop_failed", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
