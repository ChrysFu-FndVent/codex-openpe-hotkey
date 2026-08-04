import AppKit
import CodexOpenPEHotkeyCore
import Foundation

final class UpdateChecker {
    private static let endpoint = URL(
        string: "https://api.github.com/repos/ChrysFu-FndVent/codex-openpe-hotkey/releases/latest"
    )!
    private static let lastCheckKey = "OpenPEHotkeyLastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private var task: URLSessionDataTask?

    func scheduleIfNeeded() {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastCheck) >= Self.checkInterval else { return }
        defaults.set(Date(), forKey: Self.lastCheckKey)

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 10
        request.setValue("Codex-OpenPE-Hotkey/\(ReleaseInstaller.releaseVersion)", forHTTPHeaderField: "User-Agent")
        task = URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let data,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
                  !release.prerelease,
                  let current = ReleaseVersion(ReleaseInstaller.releaseVersion),
                  let latest = ReleaseVersion(release.tagName),
                  current < latest,
                  let url = URL(string: release.htmlURL) else {
                return
            }
            DispatchQueue.main.async { self.presentUpdate(release.tagName, url: url) }
        }
        task?.resume()
    }

    private func presentUpdate(_ version: String, url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "OpenPE Hotkey \(version) is available"
        alert.informativeText = "Download the new installer from GitHub Releases to update. Automatic installation is not enabled."
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case prerelease
    }
}
