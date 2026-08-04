import AppKit

@main
enum ApplicationMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate(arguments: CommandLine.arguments)
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
