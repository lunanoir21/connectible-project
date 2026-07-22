package io.connectible.mobile

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.connectible.mobile.files.SaveFilePlugin
import io.connectible.mobile.net.MulticastLockPlugin
import io.connectible.mobile.notifications.NotificationPlugin

class MainActivity : FlutterActivity() {
    private var saveFilePlugin: SaveFilePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Registers the notification-access method + event channels used by
        // T-B4/T-B5/T-B6. The plugin is self-contained; it owns its channels.
        NotificationPlugin.registerWith(flutterEngine, applicationContext)
        // Wi-Fi multicast lock (T-X20): held while mDNS discovery is active so
        // the OS does not filter inbound multicast; without it discovery finds
        // nothing on most real devices. Self-contained; owns its channel.
        MulticastLockPlugin.registerWith(flutterEngine, applicationContext)
        // "Save to..." (T-X6): streams received files out of app-private
        // storage via ACTION_CREATE_DOCUMENT. Activity-bound because the
        // document picker round-trips through onActivityResult below.
        saveFilePlugin = SaveFilePlugin(this).also { it.register(flutterEngine) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (saveFilePlugin?.handleActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
