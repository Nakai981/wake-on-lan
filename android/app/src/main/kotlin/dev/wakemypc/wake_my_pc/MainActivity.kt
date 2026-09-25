package dev.wakemypc.wake_my_pc

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wake_my_pc/lan").setMethodCallHandler { call, result ->
            if (call.method != "mac") {
                result.notImplemented()
            } else {
                // Best effort only. Android 10+ normally restricts the ARP table.
                val ip = call.arguments as? String
                val mac = try {
                    File("/proc/net/arp").useLines { lines ->
                        lines.map { it.trim().split(Regex("\\s+")) }
                            .firstOrNull { it.size >= 4 && it[0] == ip && it[2] == "0x2" }
                            ?.get(3)
                    }
                } catch (_: Exception) { null }
                result.success(mac)
            }
        }
    }
}
