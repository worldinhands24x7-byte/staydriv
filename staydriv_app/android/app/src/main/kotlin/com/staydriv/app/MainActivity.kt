package com.staydriv.app

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telephony.TelephonyManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var screenWakeLock: PowerManager.WakeLock? = null

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.staydriv.app/wake_lock").setMethodCallHandler { call, result ->
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
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
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
                screenWakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                    "StayDriv:ScreenWakeLock"
                ).apply {
                    setReferenceCounted(false)
                }
                screenWakeLock?.acquire(15000L) // 15 seconds screen wake-up for incoming alert

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

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }
}
