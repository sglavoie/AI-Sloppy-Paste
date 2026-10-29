import AppKit
import SloppyCore
import Testing
@testable import SloppyPasteApp

@Suite @MainActor struct PasterTests {
    @Test func reopeningNonactivatingPickerDuringDelayPreventsPaste() async throws {
        _ = NSApplication.shared
        let panel = PickerPanel(contentRect: NSRect(x: -10000, y: -10000, width: 100, height: 100))
        defer { panel.close() }
        var ownKeyWindow: NSWindow?
        var clipboard = ""
        var pasteCount = 0
        // A nonactivating picker can take keyboard focus while the target
        // application's PID remains frontmost in NSWorkspace.
        let sequence = PasteSequence<Int32>(
            copy: { clipboard = $0 },
            isClipboardCurrent: { true },
            permission: { .pasted },
            isSecureInputEnabled: { false },
            isLive: { _ in true },
            isFrontmost: { target in
                Paster.targetHasFocus(targetPID: target, frontmostPID: 42, ownKeyWindow: ownKeyWindow)
            },
            activate: { _ in true },
            wait: {
                panel.orderFront(nil)
                ownKeyWindow = panel
            },
            postPaste: { pasteCount += 1; return true })

        let outcome = try await sequence.run("Hello", into: 42)
        #expect(outcome == .copiedOnly(.targetUnavailable))
        #expect(clipboard == "Hello")
        #expect(pasteCount == 0)
    }

    @Test func hiddenPickerDoesNotBlockTheTarget() {
        _ = NSApplication.shared
        let panel = PickerPanel(contentRect: .zero)
        defer { panel.close() }
        #expect(Paster.targetHasFocus(targetPID: 42, frontmostPID: 42, ownKeyWindow: nil))
        #expect(Paster.targetHasFocus(targetPID: 42, frontmostPID: 42, ownKeyWindow: panel))
        #expect(!Paster.targetHasFocus(targetPID: 42, frontmostPID: 7, ownKeyWindow: nil))
        #expect(!Paster.targetHasFocus(targetPID: 42, frontmostPID: nil, ownKeyWindow: nil))
    }

    @Test func storedDelayStaysWithinSettingsRange() {
        #expect(Paster.sanitizedDelayMilliseconds(nil) == Paster.defaultDelayMilliseconds)
        #expect(Paster.sanitizedDelayMilliseconds(-10) == 0)
        #expect(Paster.sanitizedDelayMilliseconds(250) == 250)
        #expect(Paster.sanitizedDelayMilliseconds(Int.max) == Paster.maximumDelayMilliseconds)
    }
}
