import Cocoa
import FlutterMacOS
import macos_window_utils

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let windowFrame = self.frame
    let macOSWindowUtilsViewController = MacOSWindowUtilsViewController()
    self.contentViewController = macOSWindowUtilsViewController
    self.setFrame(windowFrame, display: true)

    // 在窗口首次显示前同步配置外观，避免启动瞬间闪过一个
    // 未隐藏标题栏的默认窗口（Dart 侧配置是异步的，赶不上首帧）。
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    // macos_ui 的现代窗口外观：原生毛玻璃背景 + 侧栏 vibrancy。
    MainFlutterWindowManipulator.start(mainFlutterWindow: self)

    RegisterGeneratedPlugins(registry: macOSWindowUtilsViewController.flutterViewController)

    super.awakeFromNib()
  }
}
