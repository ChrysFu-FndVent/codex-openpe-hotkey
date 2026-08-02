import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CodexOpenPEHotkeyCore

final class HotKeyController {
    private let configuration: RuntimeConfiguration
    private let client: OpenPEClient
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var activeSession: ActiveSession?

    init(configuration: RuntimeConfiguration) {
        self.configuration = configuration
        self.client = OpenPEClient(configuration: configuration)
    }

    func start() throws {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                controller.handleHotKey()
                return noErr
            },
            1,
            &eventSpec,
            context,
            &eventHandler
        )
        guard handlerStatus == noErr else {
            throw HotKeyError.eventHandlerRegistrationFailed(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4F504551), id: 1)
        let registrationStatus = RegisterEventHotKey(
            configuration.hotKeyShortcut.carbonKeyCode,
            configuration.hotKeyShortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registrationStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            throw HotKeyError.hotKeyRegistrationFailed(
                registrationStatus,
                configuration.hotKeyShortcut.displayName
            )
        }
    }

    func stop() {
        activeSession?.cancel()
        activeSession = nil
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
    }

    private func handleHotKey() {
        Diagnostics.log("hotkey received")
        guard activeSession == nil else {
            Diagnostics.log("ignored hotkey while request is active")
            NSSound.beep()
            return
        }
        guard AXIsProcessTrusted() else {
            Diagnostics.log("accessibility permission unavailable")
            NSSound.beep()
            return
        }
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApplication.bundleIdentifier,
              configuration.allowedBundleIdentifiers.contains(bundleIdentifier) else {
            Diagnostics.log("frontmost application is not allowed")
            NSSound.beep()
            return
        }

        do {
            let slot = try InlineSelectionSlot.capture()
            guard slot.processIdentifier == frontmostApplication.processIdentifier else {
                throw HotKeyError.focusedApplicationMismatch
            }
            guard let token = KeychainStore.string(
                service: configuration.serverTokenService,
                account: configuration.keychainAccount
            ) else {
                throw HotKeyError.serverTokenUnavailable
            }

            let prompt = slot.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            let session = ActiveSession(slot: slot, expectedProcessIdentifier: slot.processIdentifier)
            let initialProgress = progressText(for: session)
            guard slot.replaceProgress(with: initialProgress) else {
                throw HotKeyError.inlineProgressUnavailable
            }
            session.inlineActive = true
            activeSession = session
            startProgressTimer(for: session)

            session.task = try client.enhance(prompt: prompt, bearerToken: token) { [weak self, weak session] result in
                DispatchQueue.main.async {
                    guard let self, let session, self.activeSession === session else { return }
                    self.finish(session: session, result: result)
                }
            }
            Diagnostics.log("enhancement request started")
        } catch {
            Diagnostics.log("hotkey failed: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    private func startProgressTimer(for session: ActiveSession) {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self, weak session] _ in
            guard let self, let session, self.activeSession === session else { return }
            self.updateProgress(for: session)
        }
        session.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateProgress(for session: ActiveSession) {
        guard session.inlineActive else {
            session.timer?.invalidate()
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == session.expectedProcessIdentifier else {
            session.timer?.invalidate()
            session.inlineActive = false
            let restored = session.slot.restoreOriginalText()
            Diagnostics.log(restored
                ? "focus changed; original text restored while request continues"
                : "focus changed; inline ownership lost while request continues")
            return
        }

        session.frameIndex += 1
        let nextProgress = progressText(for: session)
        guard session.slot.replaceProgress(with: nextProgress) else {
            session.timer?.invalidate()
            session.inlineActive = false
            Diagnostics.log("inline selection changed; result will be copied only")
            return
        }
    }

    private func finish(session: ActiveSession, result: Result<String, Error>) {
        session.timer?.invalidate()
        session.timer = nil

        switch result {
        case .success(let enhancedPrompt):
            let sameApplication = NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                session.expectedProcessIdentifier
            if session.inlineActive, sameApplication,
               session.slot.replaceWithFinalText(enhancedPrompt) {
                Diagnostics.log("enhanced text applied inline")
            } else {
                if session.inlineActive {
                    _ = session.slot.restoreOriginalText()
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(enhancedPrompt, forType: .string)
                Diagnostics.log("enhanced text copied; inline replacement skipped")
                NSSound.beep()
            }
        case .failure(let error):
            if session.inlineActive {
                _ = session.slot.restoreOriginalText()
            }
            Diagnostics.log("enhancement request failed: \(error.localizedDescription)")
            NSSound.beep()
        }

        session.inlineActive = false
        session.task = nil
        activeSession = nil
    }

    private func progressText(for session: ActiveSession) -> String {
        let elapsed = Int(Date().timeIntervalSince(session.startedAt))
        return ProgressIndicator(
            elapsedSeconds: elapsed,
            frameIndex: session.frameIndex,
            language: configuration.progressLanguage
        ).text
    }
}

private final class ActiveSession {
    let slot: InlineSelectionSlot
    let expectedProcessIdentifier: pid_t
    let startedAt = Date()
    var frameIndex = 0
    var inlineActive = false
    var timer: Timer?
    var task: URLSessionDataTask?

    init(slot: InlineSelectionSlot, expectedProcessIdentifier: pid_t) {
        self.slot = slot
        self.expectedProcessIdentifier = expectedProcessIdentifier
    }

    func cancel() {
        timer?.invalidate()
        task?.cancel()
        if inlineActive {
            _ = slot.restoreOriginalText()
        }
    }
}

enum HotKeyError: LocalizedError {
    case eventHandlerRegistrationFailed(OSStatus)
    case hotKeyRegistrationFailed(OSStatus, String)
    case focusedApplicationMismatch
    case serverTokenUnavailable
    case inlineProgressUnavailable

    var errorDescription: String? {
        switch self {
        case .eventHandlerRegistrationFailed(let status):
            return "Could not register the keyboard event handler (OSStatus \(status))"
        case .hotKeyRegistrationFailed(let status, let shortcut):
            return "Could not register \(shortcut) (OSStatus \(status))"
        case .focusedApplicationMismatch:
            return "Focused text control does not belong to the frontmost application"
        case .serverTokenUnavailable:
            return "OpenPE server token is missing from Keychain"
        case .inlineProgressUnavailable:
            return "Selected text could not be replaced with inline progress"
        }
    }
}

private extension HotKeyShortcut {
    var carbonModifiers: UInt32 {
        modifiers.reduce(UInt32(0)) { result, modifier in
            switch modifier {
            case .command: return result | UInt32(cmdKey)
            case .control: return result | UInt32(controlKey)
            case .option: return result | UInt32(optionKey)
            case .shift: return result | UInt32(shiftKey)
            }
        }
    }

    var carbonKeyCode: UInt32 {
        let keyCodes: [String: Int] = [
            "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C,
            "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
            "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I,
            "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
            "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O,
            "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R,
            "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U,
            "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
            "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2,
            "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
            "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
            "9": kVK_ANSI_9,
            "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4,
            "F5": kVK_F5, "F6": kVK_F6, "F7": kVK_F7, "F8": kVK_F8,
            "F9": kVK_F9, "F10": kVK_F10, "F11": kVK_F11, "F12": kVK_F12
        ]
        return UInt32(keyCodes[key]!)
    }
}
