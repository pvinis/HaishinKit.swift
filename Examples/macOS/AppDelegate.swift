import Cocoa
import AudioToolbox

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window:NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        let viewController:LiveViewController = LiveViewController()
        viewController.title = "HaishinKit"
        window = NSWindow(contentViewController: viewController)
        window.delegate = viewController
        window.makeKeyAndOrderFront(self)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }
}
