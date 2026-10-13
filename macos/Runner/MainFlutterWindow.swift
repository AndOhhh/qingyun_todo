import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 应用级 MethodChannel：跳转系统设置的通知面板（权限被拒后的修复入口）
    let channel = FlutterMethodChannel(
      name: "qingyun_todo/system",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, reply in
      if call.method == "openNotificationSettings" {
        if let url = URL(
          string: "x-apple.systempreferences:com.apple.preference.notifications"
        ) {
          NSWorkspace.shared.open(url)
        }
        reply(nil as Any?)
      } else {
        reply(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }
}
