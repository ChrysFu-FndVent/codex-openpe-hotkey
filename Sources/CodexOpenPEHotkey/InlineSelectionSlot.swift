import AppKit
import ApplicationServices
import Foundation

final class InlineSelectionSlot {
    let processIdentifier: pid_t
    let originalText: String

    private var selectedRange: CFRange
    private(set) var displayedText: String

    private init(processIdentifier: pid_t, text: String, range: CFRange) {
        self.processIdentifier = processIdentifier
        self.originalText = text
        self.selectedRange = range
        self.displayedText = text
    }

    static func capture() throws -> InlineSelectionSlot {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else {
            throw InlineSelectionError.focusedControlUnavailable
        }

        let element = focusedValue as! AXUIElement
        guard isSettable(element, attribute: kAXSelectedTextAttribute as CFString),
              isSettable(element, attribute: kAXSelectedTextRangeAttribute as CFString) else {
            throw InlineSelectionError.controlIsNotEditable
        }

        let text = try selectedText(from: element)
        let range = try selectionRange(from: element)
        guard range.length > 0, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InlineSelectionError.noSelectedText
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            throw InlineSelectionError.processUnavailable
        }
        return InlineSelectionSlot(processIdentifier: pid, text: text, range: range)
    }

    func replaceProgress(with text: String) -> Bool {
        guard let element = ownedFocusedElement() else { return false }
        return pasteReplacingSelection(on: element, with: text, selectReplacement: true)
    }

    func replaceWithFinalText(_ text: String) -> Bool {
        guard let element = ownedFocusedElement() else { return false }
        return pasteReplacingSelection(on: element, with: text, selectReplacement: false)
    }

    func restoreOriginalText() -> Bool {
        replaceWithFinalText(originalText)
    }

    private func ownedFocusedElement() -> AXUIElement? {
        guard let element = Self.focusedEditableElement(for: processIdentifier) else { return nil }

        if let currentRange = try? Self.selectionRange(from: element),
           currentRange.location == selectedRange.location,
           currentRange.length == selectedRange.length,
           let currentText = try? Self.selectedText(from: element),
           currentText == displayedText {
            return element
        }

        // Codex can rebuild its contenteditable node after AXSelectedText changes. Recover
        // ownership from the text at the original UTF-16 range, then restore the selection.
        guard let currentRange = try? Self.selectionRange(from: element),
              currentRange.length == 0,
              currentRange.location == selectedRange.location + selectedRange.length,
              let value = try? Self.textValue(from: element),
              Self.text(in: value, at: selectedRange) == displayedText,
              Self.setSelectionRange(selectedRange, on: element),
              (try? Self.selectedText(from: element)) == displayedText else {
            return nil
        }
        return element
    }

    private func pasteReplacingSelection(
        on element: AXUIElement,
        with text: String,
        selectReplacement: Bool
    ) -> Bool {
        let previousRange = selectedRange
        guard Self.setSelectionRange(previousRange, on: element) else {
            return false
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string), Self.postPasteShortcut() else {
            snapshot.restore(to: pasteboard)
            return false
        }

        let replacementRange = CFRange(
            location: previousRange.location,
            length: (text as NSString).length
        )

        let nextRange: CFRange
        if selectReplacement {
            nextRange = replacementRange
        } else {
            nextRange = CFRange(
                location: replacementRange.location + replacementRange.length,
                length: 0
            )
        }
        let deadline = Date().addingTimeInterval(1)
        repeat {
            Thread.sleep(forTimeInterval: 0.02)
            if let currentElement = Self.focusedEditableElement(for: processIdentifier),
               let value = try? Self.textValue(from: currentElement),
               Self.text(in: value, at: replacementRange) == text,
               Self.setSelectionRange(nextRange, on: currentElement) {
                snapshot.restore(to: pasteboard)
                selectedRange = replacementRange
                displayedText = text
                return true
            }
        } while Date() < deadline

        snapshot.restore(to: pasteboard)
        return false
    }

    private static func postPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func focusedEditableElement(for processIdentifier: pid_t) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else {
            return nil
        }

        let element = focusedValue as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              pid == processIdentifier,
              isSettable(element, attribute: kAXSelectedTextAttribute as CFString),
              isSettable(element, attribute: kAXSelectedTextRangeAttribute as CFString) else {
            return nil
        }
        return element
    }

    private static func textValue(from element: AXUIElement) throws -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success,
        let text = value as? String else {
            throw InlineSelectionError.textValueUnavailable
        }
        return text
    }

    private static func text(in value: String, at range: CFRange) -> String? {
        guard range.location >= 0, range.length >= 0 else { return nil }
        let value = value as NSString
        let nsRange = NSRange(location: range.location, length: range.length)
        guard NSMaxRange(nsRange) <= value.length else { return nil }
        return value.substring(with: nsRange)
    }

    private static func selectedText(from element: AXUIElement) throws -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        ) == .success,
        let text = value as? String else {
            throw InlineSelectionError.selectedTextUnavailable
        }
        return text
    }

    private static func selectionRange(from element: AXUIElement) throws -> CFRange {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
        let value else {
            throw InlineSelectionError.selectionRangeUnavailable
        }
        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            throw InlineSelectionError.selectionRangeUnavailable
        }
        return range
    }

    private static func setSelectionRange(_ range: CFRange, on element: AXUIElement) -> Bool {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        ) == .success
    }

    private static func isSettable(_ element: AXUIElement, attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success && settable.boolValue
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}

enum InlineSelectionError: LocalizedError {
    case focusedControlUnavailable
    case controlIsNotEditable
    case noSelectedText
    case selectedTextUnavailable
    case textValueUnavailable
    case selectionRangeUnavailable
    case processUnavailable

    var errorDescription: String? {
        switch self {
        case .focusedControlUnavailable:
            return "Focused text control is unavailable"
        case .controlIsNotEditable:
            return "Focused control does not support inline text replacement"
        case .noSelectedText:
            return "Select prompt text before pressing the configured hotkey"
        case .selectedTextUnavailable:
            return "Selected text could not be read"
        case .textValueUnavailable:
            return "Text control value could not be read"
        case .selectionRangeUnavailable:
            return "Selected text range could not be read"
        case .processUnavailable:
            return "Focused application could not be identified"
        }
    }
}
