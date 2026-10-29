import AppKit
import Carbon.HIToolbox
import SloppyCore

/// Puts text on the clipboard and, when allowed, posts ⌘V into the target
/// app. It never restores the previous clipboard and never re-pastes.
@MainActor
final class Paster {
    static let delayDefaultsKey = "paste.delayMilliseconds"
    static let defaultDelayMilliseconds = 60
    static let maximumDelayMilliseconds = 1000

    private let accessibility: AccessibilityPermission

    init(accessibility: AccessibilityPermission) {
        self.accessibility = accessibility
    }

    /// Time for the target app to take key focus back before ⌘V; some apps need more.
    var delayMilliseconds: Int {
        let stored = UserDefaults.standard.object(forKey: Self.delayDefaultsKey) as? Int
        return Self.sanitizedDelayMilliseconds(stored)
    }

    static func sanitizedDelayMilliseconds(_ stored: Int?) -> Int {
        min(max(0, stored ?? defaultDelayMilliseconds), maximumDelayMilliseconds)
    }

    /// Copies `text`, then pastes it into `target` unless Accessibility is
    /// missing, Secure Input is on, or `target` is no longer live and
    /// frontmost when ⌘V would be posted, or another copy replaced the clipboard.
    /// The picker panel must already be hidden.
    func paste(_ text: String, into target: NSRunningApplication?) async throws -> PasteOutcome {
        let delay = delayMilliseconds
        var copiedChangeCount: Int?
        let sequence = PasteSequence<NSRunningApplication>(
            copy: {
                try Pasteboard.copy($0)
                copiedChangeCount = NSPasteboard.general.changeCount
            },
            isClipboardCurrent: { copiedChangeCount == NSPasteboard.general.changeCount },
            permission: { [accessibility] in
                accessibility.refresh()
                return PasteOutcome.decide(
                    accessibilityTrusted: accessibility.isTrusted, secureInputEnabled: IsSecureEventInputEnabled())
            },
            isSecureInputEnabled: { IsSecureEventInputEnabled() },
            isLive: { !$0.isTerminated },
            isFrontmost: { target in
                Self.targetHasFocus(
                    targetPID: target.processIdentifier,
                    frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                    ownKeyWindow: NSApp.keyWindow)
            },
            activate: { $0.activate() },
            wait: { try? await Task.sleep(for: .milliseconds(delay)) },
            postPaste: Self.postCommandV
        )
        return try await sequence.run(text, into: target)
    }

    /// A nonactivating panel can own keyboard focus without changing the
    /// frontmost application. Reopening the picker during the paste delay
    /// must not send the pending ⌘V into its search field or an editor.
    static func targetHasFocus(targetPID: pid_t, frontmostPID: pid_t?, ownKeyWindow: NSWindow?) -> Bool {
        frontmostPID == targetPID && ownKeyWindow?.isVisible != true
    }

    private static func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let keyCode = keyCode(producing: "v") ?? CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// The virtual key that types `character` in the current keyboard layout
    /// (Dvorak moves "v"), or nil when no key does (e.g. a Cyrillic layout).
    static func keyCode(producing character: String) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())

        return layoutData.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for keyCode in UInt16(0)..<128 {
                var deadKeyState: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDisplay), 0, keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                    characters.count, &length, &characters)
                if status == noErr, String(utf16CodeUnits: characters, count: length) == character {
                    return CGKeyCode(keyCode)
                }
            }
            return nil
        }
    }
}
