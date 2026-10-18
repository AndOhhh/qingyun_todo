import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 前台到点能否弹通知取决于 willPresent 回调；FlutterAppDelegate 只有被显式设为
    // UNUserNotificationCenter 的 delegate 才能收到该回调（插件通过
    // addApplicationDelegate 链路拿到它）。缺少这一行时：前台到点 iOS 静默丢弃，
    // 而后台 / 杀进程不经过 willPresent，所以照常弹出——与实测现象完全一致。
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    // 插件官方示例要求：后台 action isolate（无头引擎）中的插件注册回调
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 应用级 MethodChannel：跳转系统通知设置（权限被拒后的修复入口）
    let channel = FlutterMethodChannel(
      name: "qingyun_todo/system",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, reply in
      if call.method == "openNotificationSettings" {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        reply(nil)
      } else if call.method == "openAppSettings" {
        // iOS 的本应用设置页同时承载通知开关（与通知设置同一入口）
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        reply(nil)
      } else {
        reply(FlutterMethodNotImplemented)
      }
    }
  }
}
