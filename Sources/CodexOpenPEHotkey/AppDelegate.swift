import AppKit
import ApplicationServices
import CodexOpenPEHotkeyCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arguments: [String]
    private var hotKeyController: HotKeyController?
    private var setupWindowController: SetupWindowController?
    private var updateChecker: UpdateChecker?

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ReleaseInstaller.isPackagedRelease {
            do {
                if try ReleaseInstaller.relaunchFromInstalledLocationIfNeeded() {
                    NSApp.terminate(nil)
                    return
                }
            } catch {
                presentStartupError(error)
                return
            }

            if arguments.contains("--setup") || ReleaseInstaller.requiresSetup {
                showSetupWindow()
                return
            }
        }

        startHotKeyHelper()
    }

    private func startHotKeyHelper() {
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
            let checker = UpdateChecker()
            checker.scheduleIfNeeded()
            updateChecker = checker
        } catch {
            Diagnostics.log("startup failed: \(error.localizedDescription)")
            NSSound.beep()
            NSApp.terminate(nil)
        }
    }

    private func showSetupWindow() {
        NSApp.setActivationPolicy(.regular)
        let controller = SetupWindowController {
            NSApp.terminate(nil)
        }
        setupWindowController = controller
        controller.showWindow(nil)
        controller.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentStartupError(_ error: Error) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "OpenPE Hotkey could not start"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyController?.stop()
    }
}
