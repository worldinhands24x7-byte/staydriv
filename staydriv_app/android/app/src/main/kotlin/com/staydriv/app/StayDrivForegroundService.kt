package com.staydriv.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class StayDrivForegroundService : Service() {

    companion object {
        const val ACTION_START = "com.staydriv.app.action.START_FOREGROUND"
        const val ACTION_STOP = "com.staydriv.app.action.STOP_FOREGROUND"
        const val ACTION_ALERT = "com.staydriv.app.action.SHOW_ALERT"
        const val ACTION_DISMISS_ALERT = "com.staydriv.app.action.DISMISS_ALERT"

        const val ACTION_ACCEPT_BOOKING = "com.staydriv.app.action.ACCEPT_BOOKING"
        const val ACTION_VIEW_BOOKING = "com.staydriv.app.action.VIEW_BOOKING"
        const val ACTION_DECLINE_BOOKING = "com.staydriv.app.action.DECLINE_BOOKING"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_MESSAGE = "extra_message"
        const val EXTRA_BOOKING_ID = "extra_booking_id"
        const val EXTRA_ROLE = "extra_role"

        private const val SERVICE_NOTIFICATION_ID = 9001
        private const val ALERT_NOTIFICATION_ID = 9002

        private const val CHANNEL_SERVICE_ID = "staydriv_service_channel"
        private const val CHANNEL_ALERT_ID = "staydriv_alert_channel_v3"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var screenWakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        acquireServiceWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START

        when (action) {
            ACTION_START -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "StayDriv Partner Online"
                val message = intent?.getStringExtra(EXTRA_MESSAGE) ?: "Ready to receive booking requests"
                startAsForeground(title, message)
            }
            ACTION_ALERT -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "New StayDriv Booking!"
                val message = intent?.getStringExtra(EXTRA_MESSAGE) ?: "A new ride request is waiting for you."
                val bookingId = intent?.getStringExtra(EXTRA_BOOKING_ID)
                val role = intent?.getStringExtra(EXTRA_ROLE) ?: "pilot"
                wakeUpScreenForAlert()
                showUrgentAlertNotification(title, message, bookingId, role)
            }
            ACTION_DISMISS_ALERT -> {
                dismissAlertNotification()
            }
            ACTION_STOP -> {
                dismissAlertNotification()
                stopForegroundSafely()
                stopSelf()
            }
        }

        return START_STICKY
    }

    private fun startAsForeground(title: String, message: String) {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            this.action = Intent.ACTION_MAIN
            this.addCategory(Intent.CATEGORY_LAUNCHER)
            this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, pendingIntentFlags)

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_SERVICE_ID)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(SERVICE_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(SERVICE_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(SERVICE_NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            e.printStackTrace()
            startForeground(SERVICE_NOTIFICATION_ID, notification)
        }
    }

    private fun showUrgentAlertNotification(title: String, message: String, bookingId: String?, role: String = "pilot") {
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        // 1. Full-screen intent & tap intent (View / Focus booking)
        val viewIntent = Intent(this, MainActivity::class.java).apply {
            this.action = ACTION_VIEW_BOOKING
            this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_BOOKING_ID, bookingId)
        }
        val viewPendingIntent = PendingIntent.getActivity(this, 101, viewIntent, pendingIntentFlags)

        val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val vibrationPattern = longArrayOf(0, 800, 300, 800, 300, 800)

        val isPilot = role.equals("pilot", ignoreCase = true) || role.equals("partner", ignoreCase = true) || role.equals("driver", ignoreCase = true)

        val builder = NotificationCompat.Builder(this, CHANNEL_ALERT_ID)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setSound(alarmSound)
            .setVibrate(vibrationPattern)
            .setOngoing(isPilot)
            .setAutoCancel(true)
            .setContentIntent(viewPendingIntent)
            .setFullScreenIntent(viewPendingIntent, true)

        if (isPilot) {
            // Direct ACCEPT action button for pilot
            val acceptIntent = Intent(this, MainActivity::class.java).apply {
                this.action = ACTION_ACCEPT_BOOKING
                this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_BOOKING_ID, bookingId)
            }
            val acceptPendingIntent = PendingIntent.getActivity(this, 102, acceptIntent, pendingIntentFlags)

            // Direct DECLINE action button for pilot
            val declineIntent = Intent(this, MainActivity::class.java).apply {
                this.action = ACTION_DECLINE_BOOKING
                this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_BOOKING_ID, bookingId)
            }
            val declinePendingIntent = PendingIntent.getActivity(this, 103, declineIntent, pendingIntentFlags)

            builder.addAction(R.mipmap.ic_launcher, "ACCEPT RIDE ✅", acceptPendingIntent)
            builder.addAction(R.mipmap.ic_launcher, "VIEW 🚗", viewPendingIntent)
            builder.addAction(R.mipmap.ic_launcher, "DECLINE ❌", declinePendingIntent)
        } else {
            // For customer: Only view action, never show pilot accept/decline buttons
            builder.addAction(R.mipmap.ic_launcher, "VIEW RIDE 🚗", viewPendingIntent)
        }

        val notification: Notification = builder.build().apply {
            if (isPilot) {
                flags = flags or Notification.FLAG_INSISTENT
            }
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(ALERT_NOTIFICATION_ID, notification)
    }

    private fun dismissAlertNotification() {
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(ALERT_NOTIFICATION_ID)
            if (screenWakeLock?.isHeld == true) {
                screenWakeLock?.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun wakeUpScreenForAlert() {
        try {
            if (screenWakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                @Suppress("DEPRECATION")
                screenWakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                    "StayDriv:ServiceScreenWakeLock"
                ).apply {
                    setReferenceCounted(false)
                }
            }
            if (screenWakeLock?.isHeld == false) {
                screenWakeLock?.acquire(30000L) // 30s screen awake for pilot to accept
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // 1. Service persistent status channel (low noise)
            val serviceChannel = NotificationChannel(
                CHANNEL_SERVICE_ID,
                "StayDriv Active Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps StayDriv connected to receive booking alerts while minimized"
                setShowBadge(false)
            }
            manager.createNotificationChannel(serviceChannel)

            // 2. Urgent Booking Alerts channel (heads-up popup, ringtone sound, vibration)
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .build()

            val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            val alertChannel = NotificationChannel(
                CHANNEL_ALERT_ID,
                "StayDriv Urgent Ride Requests",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Immediate heads-up alert when a new booking arrives"
                enableLights(true)
                lightColor = Color.GREEN
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 800, 300, 800, 300, 800)
                setSound(ringtoneUri, audioAttributes)
                setBypassDnd(true)
            }
            manager.createNotificationChannel(alertChannel)
        }
    }

    private fun acquireServiceWakeLock() {
        try {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "StayDriv:ForegroundKeepAlive").apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(24 * 60 * 60 * 1000L)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopForegroundSafely() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        dismissAlertNotification()
        stopForegroundSafely()
        super.onDestroy()
    }
}
