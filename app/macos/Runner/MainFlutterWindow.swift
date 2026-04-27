import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.styleMask.insert(.resizable)
    self.minSize = NSSize(width: 430, height: 780)
    self.contentMinSize = NSSize(width: 430, height: 780)
    self.title = "Nexdo"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
