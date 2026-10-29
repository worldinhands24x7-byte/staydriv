package com.staydriv.app

import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Point
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat

class StayDrivFloatingWidgetService : Service() {

    companion object {
        const val ACTION_SHOW = "com.staydriv.app.action.SHOW_FLOATING_WIDGET"
        const val ACTION_UPDATE = "com.staydriv.app.action.UPDATE_FLOATING_WIDGET"
        const val ACTION_HIDE = "com.staydriv.app.action.HIDE_FLOATING_WIDGET"
        const val ACTION_RESET_POSITION = "com.staydriv.app.action.RESET_FLOATING_POSITION"

        const val EXTRA_ROLE = "extra_role"
        const val EXTRA_STATUS = "extra_status"
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_SUBTITLE = "extra_subtitle"
        const val EXTRA_ETA = "extra_eta"
        const val EXTRA_BOOKING_ID = "extra_booking_id"
        const val EXTRA_IS_PILOT = "extra_is_pilot"

        private const val NOTIFICATION_ID = 9101
        private const val CHANNEL_ID = "staydriv_floating_widget_channel"
        private const val PREFS_NAME = "staydriv_floating_prefs"
        private const val KEY_POS_X = "pos_x"
        private const val KEY_POS_Y = "pos_y"
    }

    private data class SafeBounds(val minX: Int, val maxX: Int, val minY: Int, val maxY: Int)

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var windowParams: WindowManager.LayoutParams? = null
    private var prefs: SharedPreferences? = null
    private var currentRole: String = "customer"

    // UI elements inside floatingView
    private var bubbleContainer: FrameLayout? = null
    private var statusPill: LinearLayout? = null
    private var tvTitle: TextView? = null
    private var tvSubtitle: TextView? = null
    private var tvBadge: TextView? = null
    private var tvBubbleRole: TextView? = null
    private var liveDot: View? = null
    private var btnReturn: TextView? = null

    private var isPillVisible = true
    private var isServiceAttached = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        createNotificationChannel()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        adjustPositionWithinScreen()
    }

    private fun adjustPositionWithinScreen() {
        floatingView?.post {
            val params = windowParams ?: return@post
            val bounds = getSafeBounds()
            params.x = params.x.coerceIn(bounds.minX, bounds.maxX)
            params.y = params.y.coerceIn(bounds.minY, bounds.maxY)
            try {
                windowManager?.updateViewLayout(floatingView, params)
                saveWindowPosition(params.x, params.y)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_SHOW

        when (action) {
            ACTION_SHOW -> {
                val role = intent?.getStringExtra(EXTRA_ROLE) ?: "customer"
                val status = intent?.getStringExtra(EXTRA_STATUS) ?: "active"
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "StayDriv Active"
                val subtitle = intent?.getStringExtra(EXTRA_SUBTITLE) ?: "Tap to return to ride"
                val eta = intent?.getStringExtra(EXTRA_ETA) ?: ""
                val isPilot = intent?.getBooleanExtra(EXTRA_IS_PILOT, false) ?: false

                startForegroundNotification(title, subtitle)
                showFloatingWidget(role, status, title, subtitle, eta, isPilot)
            }
            ACTION_UPDATE -> {
                val status = intent?.getStringExtra(EXTRA_STATUS) ?: ""
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: ""
                val subtitle = intent?.getStringExtra(EXTRA_SUBTITLE) ?: ""
                val eta = intent?.getStringExtra(EXTRA_ETA) ?: ""

                updateFloatingWidgetData(status, title, subtitle, eta)
            }
            ACTION_RESET_POSITION -> {
                resetFloatingWidgetPosition()
            }
            ACTION_HIDE -> {
                hideFloatingWidget()
                stopForeground(true)
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    private fun getStatusBarHeight(): Int {
        val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else (24 * resources.displayMetrics.density).toInt()
    }

    private fun getNavBarHeight(): Int {
        val resourceId = resources.getIdentifier("navigation_bar_height", "dimen", "android")
        return if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else (48 * resources.displayMetrics.density).toInt()
    }

    private fun getSafeBounds(): SafeBounds {
        val screen = getScreenDimensions()
        val viewW = if (floatingView != null && floatingView!!.width > 0) {
            floatingView!!.width
        } else {
            (floatingView?.measuredWidth ?: (220 * resources.displayMetrics.density).toInt()).coerceAtLeast(100)
        }
        val viewH = if (floatingView != null && floatingView!!.height > 0) {
            floatingView!!.height
        } else {
            (floatingView?.measuredHeight ?: (64 * resources.displayMetrics.density).toInt()).coerceAtLeast(50)
        }

        val statusBarH = getStatusBarHeight()
        val navBarH = getNavBarHeight()
        val margin = (8 * resources.displayMetrics.density).toInt()

        val minX = margin
        val maxX = (screen.x - viewW - margin).coerceAtLeast(minX)
        val minY = statusBarH + margin
        val maxY = (screen.y - navBarH - viewH - margin).coerceAtLeast(minY)

        return SafeBounds(minX, maxX, minY, maxY)
    }

    private fun getPrefKeyX(role: String): String = "pos_x_${role.lowercase()}"
    private fun getPrefKeyY(role: String): String = "pos_y_${role.lowercase()}"

    private fun saveWindowPosition(x: Int, y: Int) {
        try {
            prefs?.edit()?.apply {
                putInt(KEY_POS_X, x)
                putInt(KEY_POS_Y, y)
                putInt(getPrefKeyX(currentRole), x)
                putInt(getPrefKeyY(currentRole), y)
                apply()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun loadSavedPosition(safeBounds: SafeBounds): Point {
        val roleKey = currentRole.lowercase()
        val defaultX = safeBounds.maxX
        val defaultY = safeBounds.minY + (40 * resources.displayMetrics.density).toInt()

        val savedX = prefs?.getInt(getPrefKeyX(roleKey), prefs?.getInt(KEY_POS_X, defaultX) ?: defaultX) ?: defaultX
        val savedY = prefs?.getInt(getPrefKeyY(roleKey), prefs?.getInt(KEY_POS_Y, defaultY) ?: defaultY) ?: defaultY

        return Point(
            savedX.coerceIn(safeBounds.minX, safeBounds.maxX),
            savedY.coerceIn(safeBounds.minY, safeBounds.maxY)
        )
    }

    private fun resetFloatingWidgetPosition() {
        val params = windowParams ?: return
        val bounds = getSafeBounds()
        params.x = bounds.maxX
        params.y = bounds.minY + (40 * resources.displayMetrics.density).toInt()
        params.y = params.y.coerceIn(bounds.minY, bounds.maxY)

        try {
            windowManager?.updateViewLayout(floatingView, params)
            saveWindowPosition(params.x, params.y)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun showFloatingWidget(
        role: String,
        status: String,
        title: String,
        subtitle: String,
        eta: String,
        isPilot: Boolean
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            return
        }

        currentRole = if (isPilot) "pilot" else role

        if (floatingView == null) {
            val inflater = LayoutInflater.from(this)
            floatingView = inflater.inflate(R.layout.layout_floating_widget, null)

            bubbleContainer = floatingView?.findViewById(R.id.frame_bubble_container)
            statusPill = floatingView?.findViewById(R.id.layout_status_pill)
            tvTitle = floatingView?.findViewById(R.id.tv_floating_title)
            tvSubtitle = floatingView?.findViewById(R.id.tv_floating_subtitle)
            tvBadge = floatingView?.findViewById(R.id.tv_floating_badge)
            tvBubbleRole = floatingView?.findViewById(R.id.tv_bubble_role)
            liveDot = floatingView?.findViewById(R.id.view_live_dot)
            btnReturn = floatingView?.findViewById(R.id.btn_floating_return)

            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val isOnlineOnly = status.lowercase() == "online"
            statusPill?.visibility = if (isOnlineOnly) View.GONE else View.VISIBLE

            floatingView?.measure(
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
            )

            val safeBounds = getSafeBounds()
            val initialPos = loadSavedPosition(safeBounds)

            windowParams = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                layoutType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = initialPos.x
                y = initialPos.y
            }

            setupTouchListener()

            try {
                windowManager?.addView(floatingView, windowParams)
                isServiceAttached = true
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // Set role text
        tvBubbleRole?.text = if (isPilot) "Pilot" else "StayDriv"

        updateFloatingWidgetData(status, title, subtitle, eta)
    }

    private fun updateFloatingWidgetData(status: String, title: String, subtitle: String, eta: String) {
        if (title.isNotEmpty()) tvTitle?.text = title
        if (subtitle.isNotEmpty()) tvSubtitle?.text = subtitle

        val isOnlineOnly = status.lowercase() == "online"
        if (isOnlineOnly) {
            bubbleContainer?.setBackgroundResource(R.drawable.bg_floating_bubble_online)
            liveDot?.setBackgroundResource(R.drawable.bg_live_pulse_dot_green)
            tvBadge?.setTextColor(Color.parseColor("#10B981"))
            // Remove the floating online banner (text, status label, subtitle, blue open button, container)
            // Keep the StayDriv Pilot app icon (yellow tick) visible and unobstructed
            statusPill?.visibility = View.GONE
        } else {
            // Active booking: vibrant red circle ring as requested by user
            bubbleContainer?.setBackgroundResource(R.drawable.bg_floating_bubble_red)
            liveDot?.setBackgroundResource(R.drawable.bg_live_pulse_dot_red)
            tvBadge?.setTextColor(Color.parseColor("#EF4444"))
            statusPill?.visibility = View.VISIBLE
        }

        if (eta.isNotEmpty()) {
            tvBadge?.text = eta.uppercase()
            tvBadge?.visibility = View.VISIBLE
        } else if (status.isNotEmpty()) {
            val badgeText = when (status.lowercase()) {
                "searching" -> "FINDING"
                "accepted", "pilot_assigned" -> "ASSIGNED"
                "arrived" -> "ARRIVED"
                "started", "in_progress" -> "TRIP"
                "completed" -> "DONE"
                "online" -> "ONLINE"
                else -> "ACTIVE"
            }
            tvBadge?.text = badgeText
            tvBadge?.visibility = View.VISIBLE
        }

        // Pulse live dot indicator
        liveDot?.visibility = if (status.lowercase() == "completed" || status.lowercase() == "cancelled") {
            View.GONE
        } else {
            View.VISIBLE
        }
    }

    private fun setupTouchListener() {
        val touchListener = object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var isMoving = false
            private var touchStartTime = 0L

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                val params = windowParams ?: return false
                val touchSlop = try {
                    android.view.ViewConfiguration.get(this@StayDrivFloatingWidgetService).scaledTouchSlop.toFloat()
                } catch (_: Exception) {
                    16f
                }

                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        touchStartTime = System.currentTimeMillis()
                        isMoving = false
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        val distanceMoved = Math.hypot(dx.toDouble(), dy.toDouble()).toFloat()

                        if (distanceMoved > touchSlop) {
                            isMoving = true
                        }

                        if (isMoving) {
                            val bounds = getSafeBounds()
                            params.x = (initialX + dx).toInt().coerceIn(bounds.minX, bounds.maxX)
                            params.y = (initialY + dy).toInt().coerceIn(bounds.minY, bounds.maxY)

                            try {
                                windowManager?.updateViewLayout(floatingView, params)
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        val touchDuration = System.currentTimeMillis() - touchStartTime
                        if (!isMoving && touchDuration < 400L) {
                            // User tapped without dragging -> Reopen active ride screen in StayDriv app!
                            bringAppToForeground()
                        } else if (isMoving) {
                            // User finished dragging the window!
                            // Requirement A: Keep window at the exact released position (do not snap back).
                            val bounds = getSafeBounds()
                            params.x = params.x.coerceIn(bounds.minX, bounds.maxX)
                            params.y = params.y.coerceIn(bounds.minY, bounds.maxY)

                            try {
                                windowManager?.updateViewLayout(floatingView, params)
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }

                            // Requirement B: Persist the selected position locally for this role/user.
                            saveWindowPosition(params.x, params.y)
                        }
                        return true
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        if (isMoving) {
                            val bounds = getSafeBounds()
                            params.x = params.x.coerceIn(bounds.minX, bounds.maxX)
                            params.y = params.y.coerceIn(bounds.minY, bounds.maxY)
                            try {
                                windowManager?.updateViewLayout(floatingView, params)
                                saveWindowPosition(params.x, params.y)
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                        }
                        return true
                    }
                }
                return false
            }
        }

        // Attach touch listener across all interactive parts so dragging from anywhere works smoothly
        val root = floatingView?.findViewById<View>(R.id.root_floating_widget) ?: floatingView
        root?.setOnTouchListener(touchListener)
        bubbleContainer?.setOnTouchListener(touchListener)
        statusPill?.setOnTouchListener(touchListener)
        btnReturn?.setOnTouchListener(touchListener)
    }

    private fun bringAppToForeground() {
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            if (launchIntent != null) {
                startActivity(launchIntent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun hideFloatingWidget() {
        if (floatingView != null && isServiceAttached) {
            try {
                windowManager?.removeView(floatingView)
                isServiceAttached = false
                floatingView = null
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun getScreenDimensions(): Point {
        val size = Point()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val metrics = windowManager?.currentWindowMetrics
            if (metrics != null) {
                val bounds = metrics.bounds
                size.x = bounds.width()
                size.y = bounds.height()
                return size
            }
        }
        @Suppress("DEPRECATION")
        windowManager?.defaultDisplay?.getSize(size)
        return size
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "StayDriv Floating Mini Screen",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows live booking status in floating mini screen when minimized"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun startForegroundNotification(title: String, subtitle: String) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_menu_revert, "Open StayDriv", pendingIntent)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    override fun onDestroy() {
        hideFloatingWidget()
        super.onDestroy()
    }
}
