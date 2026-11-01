import Cocoa
import FlutterMacOS

// 通知由 flutter_local_notifications 插件接管：它会把自己注册为
// UNUserNotificationCenter 的 delegate，用于前台呈现与点击回调。
// 这里不要再设置 delegate —— 两处都设会互相覆盖，表现为通知时有时无、
// 点击通知没有反应。
@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        if window is MainFlutterWindow {
          window.makeKeyAndOrderFront(self)
          NSApp.activate(ignoringOtherApps: true)
          return false
        }
      }
    }
    return true
  }
}
