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
}
