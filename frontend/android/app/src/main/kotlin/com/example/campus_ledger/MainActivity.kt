package com.example.campus_ledger

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var notificationPlugin: LedgerNotificationPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = LedgerNotificationPlugin(this, applicationContext)
        notificationPlugin = plugin
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LedgerNotificationPlugin.CHANNEL)
            .setMethodCallHandler(plugin)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        notificationPlugin?.onRequestPermissionsResult(requestCode, grantResults)
    }
}
