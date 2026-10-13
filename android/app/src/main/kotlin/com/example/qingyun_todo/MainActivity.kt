package com.example.qingyun_todo

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "qingyun_todo/system",
    ).setMethodCallHandler { call, result ->
      if (call.method == "openNotificationSettings") {
        // 跳转本应用的通知设置页（权限被拒后的修复入口）
        runCatching {
          val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          startActivity(intent)
        }
        result.success(null)
      } else {
        result.notImplemented()
      }
    }
  }
}
