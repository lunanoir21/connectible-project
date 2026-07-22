package io.connectible.mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.connectible.mobile.notifications.NotificationPlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Registers the notification-access method + event channels used by
        // T-B4/T-B5/T-B6. The plugin is self-contained; it owns its channels.
        NotificationPlugin.registerWith(flutterEngine, applicationContext)
    }
}
