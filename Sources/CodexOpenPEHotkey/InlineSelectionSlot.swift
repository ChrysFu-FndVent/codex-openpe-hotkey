import ApplicationServices
import Foundation

final class InlineSelectionSlot {
    let processIdentifier: pid_t
    let originalText: String

    private let element: AXUIElement
    private var selectedRange: CFRange
    private(set) var displayedText: String

    private init(element: AXUIElement, processIdentifier: pid_t, text: String, range: CFRange) {
        self.element = element
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
        return InlineSelectionSlot(element: element, processIdentifier: pid, text: text, range: range)
    }

    func replaceProgress(with text: String) -> Bool {
        guard ownsDisplayedText else { return false }
        return replaceSelectedText(with: text, selectReplacement: true)
    }

    func replaceWithFinalText(_ text: String) -> Bool {
        guard ownsDisplayedText else { return false }
        return replaceSelectedText(with: text, selectReplacement: false)
    }

    func restoreOriginalText() -> Bool {
        replaceWithFinalText(originalText)
    }

    private var ownsDisplayedText: Bool {
        guard let currentRange = try? Self.selectionRange(from: element),
              currentRange.location == selectedRange.location,
              currentRange.length == selectedRange.length,
              let currentText = try? Self.selectedText(from: element) else {
            return false
        }
        return currentText == displayedText
    }

    private func replaceSelectedText(with text: String, selectReplacement: Bool) -> Bool {
        let previousRange = selectedRange
        let previousText = displayedText
        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success else {
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
        guard Self.setSelectionRange(nextRange, on: element) else {
            _ = rollbackReplacement(
                replacementRange: replacementRange,
                previousText: previousText,
                previousRange: previousRange
            )
            return false
        }

        selectedRange = replacementRange
        displayedText = text
        return true
    }

    private func rollbackReplacement(
        replacementRange: CFRange,
        previousText: String,
        previousRange: CFRange
    ) -> Bool {
        guard Self.setSelectionRange(replacementRange, on: element),
              AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                previousText as CFString
              ) == .success else {
            return false
        }
        return Self.setSelectionRange(previousRange, on: element)
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

enum InlineSelectionError: LocalizedError {
    case focusedControlUnavailable
    case controlIsNotEditable
    case noSelectedText
    case selectedTextUnavailable
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
        case .selectionRangeUnavailable:
            return "Selected text range could not be read"
        case .processUnavailable:
            return "Focused application could not be identified"
        }
    }
}
