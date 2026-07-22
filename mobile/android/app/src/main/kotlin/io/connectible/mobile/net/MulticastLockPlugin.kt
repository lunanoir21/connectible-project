package io.connectible.mobile.net

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Holds a Wi-Fi multicast lock while mDNS discovery is active (T-X20).
 *
 * `multicast_dns` is pure Dart and cannot acquire one; most real devices
 * filter inbound multicast on Wi-Fi without a held [WifiManager.MulticastLock],
 * so discovery silently returns nothing in the field. The manifest already
 * declares CHANGE_WIFI_MULTICAST_STATE; this is the piece that actually uses
 * it.
 *
 * One channel (`connectible/multicast`) with two idempotent methods:
 *  - `acquire`: create + acquire the lock if not already held.
 *  - `release`: release + drop it if held.
 *
 * The lock is intentionally not reference-counted: the Dart side
 * ([MdnsService]) tracks held state itself and pairs each acquire with a
 * single release on discovery stop / app background.
 */
object MulticastLockPlugin {
    private const val TAG = "MulticastLock"
    private const val CHANNEL = "connectible/multicast"
    private const val LOCK_TAG = "connectible-mdns"

    private var lock: WifiManager.MulticastLock? = null

    fun registerWith(flutterEngine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result, appContext) }
    }

    @Synchronized
    private fun handle(call: MethodCall, result: MethodChannel.Result, context: Context) {
        when (call.method) {
            "acquire" -> {
                try {
                    acquire(context)
                    result.success(null)
                } catch (e: Throwable) {
                    // Never crash the app over a best-effort discovery aid.
                    Log.w(TAG, "multicast lock acquire failed: ${e.message}")
                    result.error("acquire_failed", e.message, null)
                }
            }
            "release" -> {
                try {
                    release()
                    result.success(null)
                } catch (e: Throwable) {
                    Log.w(TAG, "multicast lock release failed: ${e.message}")
                    result.error("release_failed", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun acquire(context: Context) {
        if (lock?.isHeld == true) return
        val wifi = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        lock = wifi.createMulticastLock(LOCK_TAG).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun release() {
        lock?.let { if (it.isHeld) it.release() }
        lock = null
    }
}
