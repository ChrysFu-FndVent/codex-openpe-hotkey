import CodexOpenPEHotkeyCore
import Darwin
import Foundation

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("PASS: \(message)")
    } else {
        failures += 1
        print("FAIL: \(message)")
    }
}

expect(
    ProgressIndicator(elapsedSeconds: 3, frameIndex: 0, language: .chinese).text ==
        "[OpenPE ⠋] 正在优化 3s",
    "Chinese progress starts in optimizing state"
)
expect(
    ProgressIndicator(elapsedSeconds: 20, frameIndex: 5, language: .chinese).text ==
        "[OpenPE ⠴] 仍在生成 20s",
    "Chinese progress exposes continued generation"
)
expect(
    ProgressIndicator(elapsedSeconds: 50, frameIndex: 7, language: .chinese).text ==
        "[OpenPE ⠧] 网络较慢 50s",
    "Chinese progress exposes slow network state"
)

do {
    let configuration = try RuntimeConfiguration(
        environment: [:],
        localeIdentifier: "zh_CN",
        userName: "tester"
    )
    expect(
        configuration.allowedBundleIdentifiers == Set(["com.openai.codex"]),
        "Default hotkey scope is Codex only"
    )
    expect(configuration.progressLanguage == .chinese, "Locale selects Chinese progress")
    expect(configuration.hotKeyShortcut.displayName == "Option+Q", "Default macOS hotkey is Option+Q")
} catch {
    failures += 1
    print("FAIL: Default configuration threw \(error)")
}

do {
    let configuration = try RuntimeConfiguration(
        environment: [
            "OPENPE_ENDPOINT": "http://localhost:19000/v1/prompt-enhance",
            "OPENPE_HOTKEY_TIMEOUT_SECONDS": "45",
            "OPENPE_ALLOWED_BUNDLE_IDS": "com.openai.codex, com.apple.TextEdit",
            "OPENPE_PROGRESS_LANGUAGE": "en",
            "OPENPE_HOTKEY": "command+shift+p"
        ],
        localeIdentifier: "zh_CN",
        userName: "tester"
    )
    expect(configuration.requestTimeout == 45, "Timeout override is parsed")
    expect(
        configuration.allowedBundleIdentifiers.contains("com.apple.TextEdit"),
        "Additional test application can be allowed explicitly"
    )
    expect(configuration.progressLanguage == .english, "Language override is parsed")
    expect(configuration.hotKeyShortcut.displayName == "Command+Shift+P", "Hotkey override is parsed")
} catch {
    failures += 1
    print("FAIL: Override configuration threw \(error)")
}

do {
    _ = try HotKeyShortcut("q")
    failures += 1
    print("FAIL: Modifier-free hotkey was accepted")
} catch {
    print("PASS: Modifier-free hotkey is rejected")
}

do {
    _ = try HotKeyShortcut("option+escape")
    failures += 1
    print("FAIL: Unsupported hotkey key was accepted")
} catch {
    print("PASS: Unsupported hotkey key is rejected")
}

do {
    _ = try HotKeyShortcut("option+alt+q")
    failures += 1
    print("FAIL: Duplicate macOS modifier alias was accepted")
} catch {
    print("PASS: Duplicate macOS modifier alias is rejected")
}

do {
    _ = try RuntimeConfiguration(
        environment: ["OPENPE_ENDPOINT": "not a URL"],
        localeIdentifier: "en_US",
        userName: "tester"
    )
    failures += 1
    print("FAIL: Invalid endpoint was accepted")
} catch {
    print("PASS: Invalid endpoint is rejected")
}

do {
    let data = Data(#"{"enhanced_prompt":"Review the login flow."}"#.utf8)
    let response = try JSONDecoder().decode(EnhancementResponse.self, from: data)
    expect(response.enhancedPrompt == "Review the login flow.", "OpenPE response contract decodes")
} catch {
    failures += 1
    print("FAIL: OpenPE response decoding threw \(error)")
}

if let current = ReleaseVersion("0.4.0"),
   let newer = ReleaseVersion("v0.5.0"),
   let equivalent = ReleaseVersion("0.4") {
    expect(current < newer, "Newer GitHub release versions are detected")
    expect(current == equivalent, "Missing release version components default to zero")
} else {
    failures += 1
    print("FAIL: Valid release versions were rejected")
}
expect(ReleaseVersion("release-latest") == nil, "Invalid release versions are rejected")

if failures > 0 {
    print("\(failures) self-test(s) failed")
    exit(EXIT_FAILURE)
}

print("All core self-tests passed")
