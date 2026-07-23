package io.connectible.mobile.net

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import io.connectible.mobile.MainActivity

/**
 * Foreground service (T-X36) that keeps this phone's inbound gRPC/TLS
 * server + mDNS advertise + heartbeat alive under Doze/OEM background
 * kills while the "receiving" (pairable) role is on. Started/stopped by
 * [ReceivingServicePlugin] in lockstep with `PairingModel.
 * setPairableEnabled` (Dart side) -- this service owns no LAN/networking
 * logic itself; it only keeps the process alive and shows the persistent
 * notification Android requires of any foreground service.
 *
 * Not `START_STICKY`: if the OS kills it anyway, resurrecting a
 * foreground service with no Dart-side owner to reconcile against would
 * leave native/Dart state out of sync (the notification would claim
 * "discoverable" even if the Dart-side toggle had since been switched
 * off), which is worse than simply staying dead until the next toggle
 * or app launch re-starts it.
 */
class ReceivingForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotEmpty() } ?: "Connectible"
        val text = intent?.getStringExtra(EXTRA_TEXT).orEmpty()
        startForegroundWithNotification(title, text)
        return START_NOT_STICKY
    }

    private fun startForegroundWithNotification(title: String, text: String) {
        ensureChannel()

        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )

        val icon = applicationInfo.icon
        val notification: Notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(icon)
                .setContentIntent(openApp)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(icon)
                .setContentIntent(openApp)
                .setOngoing(true)
                .build()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // IMPORTANCE_LOW: visible in the shade/status bar but silent (no
        // sound/heads-up) -- an ambient status indicator, not an alert.
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Discoverable status",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shown while this phone can be found and paired into"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        private const val CHANNEL_ID = "connectible_receiving"
        private const val NOTIFICATION_ID = 1001
    }
}
