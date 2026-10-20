package com.gooduselabs.smartprint

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var lock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartprint/net").setMethodCallHandler { call, result ->
            when (call.method) {
                "multicastLock" -> {
                    try {
                        if (call.arguments == true) {
                            if (lock == null) {
                                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                                lock = wifi.createMulticastLock("smartprint-mdns").apply { setReferenceCounted(false) }
                            }
                            lock?.acquire()
                        } else {
                            lock?.release()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        lock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }
}
