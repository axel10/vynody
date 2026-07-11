import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Setup method channel for file opening on macOS
    let channel = FlutterMethodChannel(
      name: "vynody/file_opener",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.setupMethodChannel(channel)
    }

    super.awakeFromNib()
  }
}
