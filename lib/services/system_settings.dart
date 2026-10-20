import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 极小的系统设置跳转通道（`qingyun_todo/system`）。
///
/// 不引入第三方插件（`app_settings` 仅支持 Swift Package Manager，
/// 与本项目 iOS 的 CocoaPods 集成冲突），三端原生实现各 10 行：
/// - Android：`Settings.ACTION_APP_NOTIFICATION_SETTINGS`
/// - iOS：`UIApplication.openSettingsURLString`
/// - macOS：系统设置的通知面板
class SystemSettings {
  const SystemSettings._();

  static const MethodChannel _channel = MethodChannel('qingyun_todo/system');

  /// 打开本应用的通知设置页；失败静默（由调用方提示手动路径）
  static Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } catch (error) {
      debugPrint('[system] 打开通知设置失败：$error');
    }
  }

  /// 打开本应用的系统设置详情页（Android = 应用信息；iOS = 本应用设置页）。
  ///
  /// 国产 ROM 的「自启动 / 耗电管理」入口都挂在应用信息页下，引导时直接送用户过去，
  /// 比让其在设置树里翻找更可靠。
  static Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (error) {
      debugPrint('[system] 打开应用设置失败：$error');
    }
  }

  /// 设备厂商标识（Android `Build.MANUFACTURER`，如 `OnePlus` / `Xiaomi`）；
  /// 非 Android 平台或读取失败返回 null。
  static Future<String?> getBrand() async {
    try {
      return await _channel.invokeMethod<String>('getBrand');
    } catch (error) {
      debugPrint('[system] 读取设备厂商失败：$error');
      return null;
    }
  }
}
