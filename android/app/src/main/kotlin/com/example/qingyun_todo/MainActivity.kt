package com.example.qingyun_todo

import android.content.Intent
import android.net.Uri
import android.os.Build
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
      when (call.method) {
        // 跳转本应用的通知设置页（权限被拒后的修复入口）
        "openNotificationSettings" -> {
          startSystemIntent(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
              .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
          )
          result.success(null)
        }
        // 跳转应用信息页：国产 ROM 的「自启动 / 耗电管理」入口都挂在这里
        "openAppSettings" -> {
          startSystemIntent(
            Intent(
              Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
              Uri.fromParts("package", packageName, null),
            )
          )
          result.success(null)
        }
        // 厂商标识：「通知收不到？」引导页据此给出对应厂商的设置路径
        "getBrand" -> result.success(Build.MANUFACTURER)
        else -> result.notImplemented()
      }
    }
  }

  /// 统一以 NEW_TASK 启动系统设置页；失败静默（Dart 侧会提示手动路径）
  private fun startSystemIntent(intent: Intent) {
    runCatching {
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      startActivity(intent)
    }
  }
}
