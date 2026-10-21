package com.lantern.app

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Many phones silently drop incoming UDP broadcasts unless this lock is held.
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("lantern-multicast").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            Log.w("Lantern", "Could not acquire multicast lock", e)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lantern/network")
            .setMethodCallHandler { call, result ->
                if (call.method == "getWifiInfo") {
                    try {
                        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        result.success(
                            mapOf(
                                "wifiEnabled" to wifi.isWifiEnabled,
                                "multicastLockHeld" to (multicastLock?.isHeld == true)
                            )
                        )
                    } catch (e: Exception) {
                        result.error("wifi_error", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        try {
            multicastLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
            Log.w("Lantern", "Could not release multicast lock", e)
        }
        super.onDestroy()
    }
}
