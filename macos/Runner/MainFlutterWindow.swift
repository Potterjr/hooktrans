import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var screenChannel: AnyObject?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    if #available(macOS 14.0, *) {
      screenChannel = ScreenChannel(messenger: flutterViewController.engine.binaryMessenger)
    }

    super.awakeFromNib()
  }
}
