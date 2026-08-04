import AppKit
import CodexOpenPEHotkeyCore

final class SetupWindowController: NSWindowController, NSWindowDelegate {
    private let completion: () -> Void
    private let apiKeyField = NSSecureTextField()
    private let baseURLField = NSTextField(string: "https://api.openai.com/v1")
    private let modelField = NSTextField(string: "gpt-5.4-mini")
    private let hotKeyField = NSTextField(string: "Option+Q")
    private let languagePopup = NSPopUpButton()
    private let progressLanguagePopup = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "Ready to configure this Mac.")
    private let progressIndicator = NSProgressIndicator()
    private let installButton = NSButton(title: "Install", target: nil, action: nil)
    private let closeButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var installationFinished = false
    private var isInstalling = false
    private var didComplete = false

    init(completion: @escaping () -> Void) {
        self.completion = completion
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up OpenPE Hotkey"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildInterface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !isInstalling { completeOnce() }
        return !isInstalling
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }
        let title = NSTextField(labelWithString: "Codex OpenPE Hotkey")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString:
            "Configure prompt enhancement once. The helper then runs in the background with no Dock or menu bar icon."
        )
        subtitle.textColor = .secondaryLabelColor

        languagePopup.addItems(withTitles: ["Chinese", "English"])
        progressLanguagePopup.addItems(withTitles: ["Chinese", "English"])
        if !Locale.current.identifier.lowercased().hasPrefix("zh") {
            languagePopup.selectItem(at: 1)
            progressLanguagePopup.selectItem(at: 1)
        }

        let form = NSGridView(views: [
            [NSTextField(labelWithString: "API key"), apiKeyField],
            [NSTextField(labelWithString: "API base URL"), baseURLField],
            [NSTextField(labelWithString: "Model"), modelField],
            [NSTextField(labelWithString: "Hotkey"), hotKeyField],
            [NSTextField(labelWithString: "Output language"), languagePopup],
            [NSTextField(labelWithString: "Progress language"), progressLanguagePopup]
        ])
        form.rowSpacing = 12
        form.columnSpacing = 14
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .fill

        for field in [apiKeyField, baseURLField, modelField, hotKeyField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 390).isActive = true
        }

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        let statusRow = NSStackView(views: [progressIndicator, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8

        installButton.target = self
        installButton.action = #selector(install)
        installButton.keyEquivalent = "\r"
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        let buttons = NSStackView(views: [closeButton, installButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .centerY

        let root = NSStackView(views: [title, subtitle, form, statusRow, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 28, left: 30, bottom: 24, right: 30)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            subtitle.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -60)
        ])
    }

    @objc private func install() {
        let configuration: SetupConfiguration
        do {
            configuration = try validatedConfiguration()
        } catch {
            showError(error)
            return
        }

        setControlsEnabled(false)
        isInstalling = true
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "Starting installation..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try ReleaseInstaller.install(configuration: configuration) { message in
                    DispatchQueue.main.async { self?.statusLabel.stringValue = message }
                }
                DispatchQueue.main.async { self?.finish(result) }
            } catch {
                DispatchQueue.main.async {
                    self?.progressIndicator.stopAnimation(nil)
                    self?.isInstalling = false
                    self?.setControlsEnabled(true)
                    self?.showError(error)
                }
            }
        }
    }

    private func validatedConfiguration() throws -> SetupConfiguration {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hotKey = hotKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !baseURL.isEmpty, !model.isEmpty else {
            throw ReleaseInstallerError.missingRequiredValue
        }
        guard let url = URL(string: baseURL), url.scheme == "http" || url.scheme == "https" else {
            throw ReleaseInstallerError.invalidBaseURL
        }
        _ = try HotKeyShortcut(hotKey)
        return SetupConfiguration(
            apiKey: apiKey,
            baseURL: baseURL,
            model: model,
            language: languagePopup.indexOfSelectedItem == 0 ? "zh" : "en",
            progressLanguage: progressLanguagePopup.indexOfSelectedItem == 0 ? "zh" : "en",
            hotKey: hotKey
        )
    }

    private func finish(_ result: SetupResult) {
        progressIndicator.stopAnimation(nil)
        isInstalling = false
        installationFinished = true
        statusLabel.stringValue = result.serverHealthy && result.pluginInstalled
            ? "Installed and healthy. Shortcut: \(result.hotKeyDisplayName)"
            : "Installation completed with warnings."
        apiKeyField.stringValue = ""
        installButton.title = "Finish"
        installButton.target = self
        installButton.action = #selector(finishAndClose)
        closeButton.title = "Accessibility Settings"
        closeButton.target = self
        closeButton.action = #selector(openAccessibilitySettings)
        closeButton.isEnabled = true
        installButton.isEnabled = true
        ReleaseInstaller.requestAccessibilityPermission()
    }

    private func setControlsEnabled(_ enabled: Bool) {
        for control in [apiKeyField, baseURLField, modelField, hotKeyField, languagePopup, progressLanguagePopup] {
            control.isEnabled = enabled
        }
        installButton.isEnabled = enabled
        closeButton.isEnabled = enabled
    }

    private func showError(_ error: Error) {
        statusLabel.stringValue = "Installation did not complete."
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    @objc private func openAccessibilitySettings() {
        ReleaseInstaller.requestAccessibilityPermission()
    }

    @objc private func finishAndClose() {
        window?.close()
    }

    @objc private func closeWindow() {
        window?.close()
    }

    private func completeOnce() {
        guard !didComplete else { return }
        didComplete = true
        completion()
    }
}
