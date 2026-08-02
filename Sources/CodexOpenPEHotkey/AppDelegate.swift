import AppKit
import ApplicationServices
import CodexOpenPEHotkeyCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyController: HotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let accessibilityTrusted = AXIsProcessTrusted()

        do {
            let configuration = try RuntimeConfiguration(
                environment: ProcessInfo.processInfo.environment,
                localeIdentifier: Locale.current.identifier,
                userName: NSUserName()
            )
            let controller = HotKeyController(configuration: configuration)
            try controller.start()
            hotKeyController = controller
            let accessibilityState = accessibilityTrusted ? "available" : "unavailable"
            Diagnostics.log(
                "started with \(configuration.hotKeyShortcut.displayName); accessibility=\(accessibilityState)"
            )
        } catch {
            Diagnostics.log("startup failed: \(error.localizedDescription)")
            NSSound.beep()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyController?.stop()
    }
}
