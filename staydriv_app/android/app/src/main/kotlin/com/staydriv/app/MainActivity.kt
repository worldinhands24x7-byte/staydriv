package com.staydriv.app

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.ContactsContract
import android.provider.Settings
import android.telephony.TelephonyManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val REQUEST_CODE_PICK_CONTACT = 2001
    private var pendingContactPickerResult: MethodChannel.Result? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var screenWakeLock: PowerManager.WakeLock? = null
    private var sharedLocationData: String? = null
    private var locationShareChannel: MethodChannel? = null
    private var wakeLockChannel: MethodChannel? = null
    private var pendingBookingAction: Map<String, String?>? = null
    private var isAutoPipEnabled = false
    private var isPipActive = false
    private var isAppInForeground = false

    override fun onResume() {
        super.onResume()
        isAppInForeground = true
    }

    override fun onPause() {
        super.onPause()
        isAppInForeground = false
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type

        // 1. Check for incoming booking notification actions (ACCEPT, VIEW, DECLINE)
        if (action == StayDrivForegroundService.ACTION_ACCEPT_BOOKING ||
            action == StayDrivForegroundService.ACTION_VIEW_BOOKING ||
            action == StayDrivForegroundService.ACTION_DECLINE_BOOKING) {
            
            val bookingId = intent.getStringExtra(StayDrivForegroundService.EXTRA_BOOKING_ID)
            val actionType = when (action) {
                StayDrivForegroundService.ACTION_ACCEPT_BOOKING -> "accept"
                StayDrivForegroundService.ACTION_DECLINE_BOOKING -> "decline"
                else -> "view"
            }

            wakeUpScreen()
            val actionPayload = mapOf("action" to actionType, "bookingId" to bookingId)

            if (wakeLockChannel != null) {
                runOnUiThread {
                    wakeLockChannel?.invokeMethod("onBookingActionReceived", actionPayload)
                }
            } else {
                pendingBookingAction = actionPayload
            }

            if (action == StayDrivForegroundService.ACTION_DECLINE_BOOKING ||
                action == StayDrivForegroundService.ACTION_ACCEPT_BOOKING) {
                dismissIncomingAlert()
            }
        }

        // 2. Share intent (Google Maps location share)
        var extractedText: String? = null

        if (Intent.ACTION_SEND == action) {
            if (type != null && (type == "text/plain" || type.startsWith("text/"))) {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
                extractedText = if (!text.isNullOrBlank()) {
                    if (!subject.isNullOrBlank() && !text.contains(subject)) {
                        "$subject\n$text"
                    } else {
                        text
                    }
                } else {
                    subject ?: intent.data?.toString()
                }
            }
        } else if (Intent.ACTION_VIEW == action) {
            extractedText = intent.data?.toString()
        }

        if (!extractedText.isNullOrBlank()) {
            sharedLocationData = extractedText
            runOnUiThread {
                locationShareChannel?.invokeMethod("onLocationReceived", extractedText)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Cellular Network Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.staydriv.app/network").setMethodCallHandler { call, result ->
            if (call.method == "getCellularGeneration") {
                result.success(getCellularGeneration())
            } else {
                result.notImplemented()
            }
        }

        // 2. StayDriv WakeLock & Background Keep-Alive Channel
        wakeLockChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.staydriv.app/wake_lock").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireWakeLock" -> {
                        acquireWakeLock()
                        result.success(true)
                    }
                    "releaseWakeLock" -> {
                        releaseWakeLock()
                        result.success(true)
                    }
                    "wakeUpScreen" -> {
                        wakeUpScreen()
                        result.success(true)
                    }
                    "startForegroundService" -> {
                        val title = call.argument<String>("title") ?: "StayDriv Online"
                        val message = call.argument<String>("message") ?: "Ready to receive bookings"
                        startForegroundKeepAlive(title, message)
                        result.success(true)
                    }
                    "stopForegroundService" -> {
                        stopForegroundKeepAlive()
                        result.success(true)
                    }
                    "showIncomingAlert" -> {
                        val title = call.argument<String>("title") ?: "New StayDriv Booking!"
                        val message = call.argument<String>("message") ?: "A new ride request is available."
                        val bookingId = call.argument<String>("bookingId")
                        val role = call.argument<String>("role") ?: "pilot"
                        val force = call.argument<Boolean>("force") ?: false
                        showIncomingAlert(title, message, bookingId, role, force)
                        result.success(true)
                    }
                    "dismissIncomingAlert" -> {
                        dismissIncomingAlert()
                        result.success(true)
                    }
                    "bringAppToForeground" -> {
                        bringAppToForeground()
                        result.success(true)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(true)
                    }
                    "enableAutoPip" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setAutoPipEnabled(enabled)
                        result.success(true)
                    }
                    "enterPip" -> {
                        val success = enterPipMode()
                        result.success(success)
                    }
                    "canDrawOverlays" -> {
                        val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Settings.canDrawOverlays(this@MainActivity)
                        } else {
                            true
                        }
                        result.success(canDraw)
                    }
                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this@MainActivity)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    "showFloatingWidget" -> {
                        val role = call.argument<String>("role") ?: "customer"
                        val status = call.argument<String>("status") ?: "active"
                        val title = call.argument<String>("title") ?: "StayDriv"
                        val subtitle = call.argument<String>("subtitle") ?: ""
                        val eta = call.argument<String>("eta") ?: ""
                        val bookingId = call.argument<String>("bookingId") ?: ""
                        val isPilot = call.argument<Boolean>("isPilot") ?: (role.lowercase() == "pilot" || role.lowercase() == "partner")

                        val serviceIntent = Intent(this@MainActivity, StayDrivFloatingWidgetService::class.java).apply {
                            action = StayDrivFloatingWidgetService.ACTION_SHOW
                            putExtra(StayDrivFloatingWidgetService.EXTRA_ROLE, role)
                            putExtra(StayDrivFloatingWidgetService.EXTRA_STATUS, status)
                            putExtra(StayDrivFloatingWidgetService.EXTRA_TITLE, title)
                            putExtra(StayDrivFloatingWidgetService.EXTRA_SUBTITLE, subtitle)
                            putExtra(StayDrivFloatingWidgetService.EXTRA_ETA, eta)
                            putExtra(StayDrivFloatingWidgetService.EXTRA_BOOKING_ID, bookingId)
                            putExtra(StayDrivFloatingWidgetService.EXTRA_IS_PILOT, isPilot)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    }
                    "updateFloatingWidget" -> {
                        val status = call.argument<String>("status") ?: ""
                        val title = call.argument<String>("title") ?: ""
                        val subtitle = call.argument<String>("subtitle") ?: ""
                        val eta = call.argument<String>("eta") ?: ""

                        val serviceIntent = Intent(this@MainActivity, StayDrivFloatingWidgetService::class.java).apply {
                            action = StayDrivFloatingWidgetService.ACTION_UPDATE
                            putExtra(StayDrivFloatingWidgetService.EXTRA_STATUS, status)
                            putExtra(StayDrivFloatingWidgetService.EXTRA_TITLE, title)
                            putExtra(StayDrivFloatingWidgetService.EXTRA_SUBTITLE, subtitle)
                            putExtra(StayDrivFloatingWidgetService.EXTRA_ETA, eta)
                        }
                        startService(serviceIntent)
                        result.success(true)
                    }
                    "hideFloatingWidget" -> {
                        val serviceIntent = Intent(this@MainActivity, StayDrivFloatingWidgetService::class.java).apply {
                            action = StayDrivFloatingWidgetService.ACTION_HIDE
                        }
                        startService(serviceIntent)
                        result.success(true)
                    }
                    "resetFloatingPosition" -> {
                        val serviceIntent = Intent(this@MainActivity, StayDrivFloatingWidgetService::class.java).apply {
                            action = StayDrivFloatingWidgetService.ACTION_RESET_POSITION
                        }
                        startService(serviceIntent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Deliver any pending booking notification actions that arrived before engine initialization
        pendingBookingAction?.let { actionPayload ->
            runOnUiThread {
                wakeLockChannel?.invokeMethod("onBookingActionReceived", actionPayload)
            }
            pendingBookingAction = null
        }

        // 3. Location Share Channel (Google Maps & System Share)
        locationShareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.staydriv.app/location_share").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedLocation" -> {
                        val data = sharedLocationData
                        sharedLocationData = null
                        result.success(data)
                    }
                    "clearSharedLocation" -> {
                        sharedLocationData = null
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // 4. Contact Picker Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.staydriv.app/contact_picker").setMethodCallHandler { call, result ->
            if (call.method == "pickContact") {
                if (pendingContactPickerResult != null) {
                    result.error("BUSY", "Another contact pick operation is in progress", null)
                    return@setMethodCallHandler
                }
                pendingContactPickerResult = result
                try {
                    val pickIntent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI)
                    startActivityForResult(pickIntent, REQUEST_CODE_PICK_CONTACT)
                } catch (e: Exception) {
                    pendingContactPickerResult = null
                    result.error("UNAVAILABLE", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        handleIntent(intent)
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "StayDriv:BackgroundSyncLock").apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(24 * 60 * 60 * 1000L) // 24 hours max safeguard
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun wakeUpScreen() {
        runOnUiThread {
            try {
                // 1. Light up screen via PowerManager WakeLock
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                @Suppress("DEPRECATION")
                screenWakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                    "StayDriv:ScreenWakeLock"
                ).apply {
                    setReferenceCounted(false)
                }
                screenWakeLock?.acquire(30000L) // 30 seconds screen wake-up for incoming alert

                // 2. Window flags for lock screen display & wake-up
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    setShowWhenLocked(true)
                    setTurnScreenOn(true)
                    val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                    keyguardManager.requestDismissKeyguard(this, null)
                } else {
                    @Suppress("DEPRECATION")
                    window.addFlags(
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    )
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                powerManager.isIgnoringBatteryOptimizations(packageName)
            } else {
                true
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!isIgnoringBatteryOptimizations()) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getCellularGeneration(): String {
        return try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val networkType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                tm.dataNetworkType
            } else {
                tm.networkType
            }
            when (networkType) {
                TelephonyManager.NETWORK_TYPE_GPRS,
                TelephonyManager.NETWORK_TYPE_EDGE,
                TelephonyManager.NETWORK_TYPE_CDMA,
                TelephonyManager.NETWORK_TYPE_1xRTT,
                TelephonyManager.NETWORK_TYPE_IDEN -> "2g"
                
                TelephonyManager.NETWORK_TYPE_UMTS,
                TelephonyManager.NETWORK_TYPE_EVDO_0,
                TelephonyManager.NETWORK_TYPE_EVDO_A,
                TelephonyManager.NETWORK_TYPE_HSDPA,
                TelephonyManager.NETWORK_TYPE_HSUPA,
                TelephonyManager.NETWORK_TYPE_HSPA,
                TelephonyManager.NETWORK_TYPE_EVDO_B,
                TelephonyManager.NETWORK_TYPE_EHRPD,
                TelephonyManager.NETWORK_TYPE_HSPAP -> "3g"
                
                TelephonyManager.NETWORK_TYPE_LTE -> "4g"
                
                20 -> "5g" // TelephonyManager.NETWORK_TYPE_NR
                
                else -> "unknown"
            }
        } catch (e: Exception) {
            "unknown"
        }
    }

    private fun startForegroundKeepAlive(title: String, message: String) {
        try {
            val serviceIntent = Intent(this, StayDrivForegroundService::class.java).apply {
                action = StayDrivForegroundService.ACTION_START
                putExtra(StayDrivForegroundService.EXTRA_TITLE, title)
                putExtra(StayDrivForegroundService.EXTRA_MESSAGE, message)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopForegroundKeepAlive() {
        try {
            val serviceIntent = Intent(this, StayDrivForegroundService::class.java).apply {
                action = StayDrivForegroundService.ACTION_STOP
            }
            startService(serviceIntent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun isScreenInteractiveAndUnlocked(): Boolean {
        return try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            val isInteractive = powerManager.isInteractive
            val isLocked = keyguardManager.isKeyguardLocked
            isInteractive && !isLocked
        } catch (e: Exception) {
            false
        }
    }

    private fun showIncomingAlert(title: String, message: String, bookingId: String?, role: String = "pilot", force: Boolean = false) {
        try {
            // Guard: If app is currently in the foreground and screen is active, do not display floating notification banner
            if (!force && isAppInForeground && isScreenInteractiveAndUnlocked()) {
                android.util.Log.d("MainActivity", "Suppressed system alert notification because app is in foreground: $title")
                return
            }

            wakeUpScreen()
            val serviceIntent = Intent(this, StayDrivForegroundService::class.java).apply {
                action = StayDrivForegroundService.ACTION_ALERT
                putExtra(StayDrivForegroundService.EXTRA_TITLE, title)
                putExtra(StayDrivForegroundService.EXTRA_MESSAGE, message)
                putExtra(StayDrivForegroundService.EXTRA_BOOKING_ID, bookingId)
                putExtra(StayDrivForegroundService.EXTRA_ROLE, role)
            }
            startService(serviceIntent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun dismissIncomingAlert() {
        try {
            val serviceIntent = Intent(this, StayDrivForegroundService::class.java).apply {
                action = StayDrivForegroundService.ACTION_DISMISS_ALERT
            }
            startService(serviceIntent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun bringAppToForeground() {
        runOnUiThread {
            try {
                wakeUpScreen()
                val intent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                startActivity(intent)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Do not force automatic unexpected minimization into PiP on user leave
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        isPipActive = isInPictureInPictureMode
        runOnUiThread {
            wakeLockChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
        }
    }

    private fun enterPipMode(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return try {
                val aspectRatio = android.util.Rational(3, 4) // Optimal vertical driving navigation mini-window
                val builder = android.app.PictureInPictureParams.Builder()
                    .setAspectRatio(aspectRatio)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    builder.setAutoEnterEnabled(false)
                }
                val success = enterPictureInPictureMode(builder.build())
                isPipActive = success
                success
            } catch (e: Exception) {
                e.printStackTrace()
                false
            }
        }
        return false
    }

    private fun setAutoPipEnabled(enabled: Boolean) {
        isAutoPipEnabled = enabled
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val aspectRatio = android.util.Rational(3, 4)
                val builder = android.app.PictureInPictureParams.Builder()
                    .setAspectRatio(aspectRatio)
                    .setAutoEnterEnabled(false) // Keep disabled to prevent unexpected minimization
                setPictureInPictureParams(builder.build())
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun isPipSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_PICK_CONTACT) {
            val callback = pendingContactPickerResult
            pendingContactPickerResult = null

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val contactUri: Uri = data.data!!
                var displayName: String? = null
                var phoneNumber: String? = null
                val phoneNumbers = mutableListOf<String>()

                try {
                    val projection = arrayOf(
                        ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                        ContactsContract.CommonDataKinds.Phone.NUMBER,
                        ContactsContract.CommonDataKinds.Phone.CONTACT_ID
                    )
                    contentResolver.query(contactUri, projection, null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                            val numIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                            val idIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)

                            if (nameIdx != -1) displayName = cursor.getString(nameIdx)
                            if (numIdx != -1) {
                                val num = cursor.getString(numIdx)
                                if (!num.isNullOrBlank()) {
                                    phoneNumber = num
                                    phoneNumbers.add(num)
                                }
                            }

                            val contactId = if (idIdx != -1) cursor.getString(idIdx) else null
                            if (!contactId.isNullOrBlank()) {
                                try {
                                    contentResolver.query(
                                        ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                                        arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
                                        "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID} = ?",
                                        arrayOf(contactId),
                                        null
                                    )?.use { extraCursor ->
                                        val extraNumIdx = extraCursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                                        if (extraNumIdx != -1) {
                                            while (extraCursor.moveToNext()) {
                                                val extraNum = extraCursor.getString(extraNumIdx)
                                                if (!extraNum.isNullOrBlank() && !phoneNumbers.contains(extraNum)) {
                                                    phoneNumbers.add(extraNum)
                                                }
                                            }
                                        }
                                    }
                                } catch (_: Exception) {
                                    // Fallback: phoneNumbers contains the chosen number
                                }
                            }
                        }
                    }

                    callback?.success(mapOf(
                        "name" to (displayName ?: ""),
                        "phoneNumber" to (phoneNumber ?: ""),
                        "phoneNumbers" to phoneNumbers
                    ))
                } catch (e: Exception) {
                    callback?.error("READ_FAILED", e.message, null)
                }
            } else {
                // User cancelled or closed picker
                callback?.success(null)
            }
        }
    }
}
