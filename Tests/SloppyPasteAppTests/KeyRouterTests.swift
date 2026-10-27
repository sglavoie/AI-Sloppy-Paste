import AppKit
import Carbon.HIToolbox
import Testing
@testable import SloppyPasteApp

@Suite @MainActor struct KeyRouterTests {
    @Test func compositionKeepsNavigationAndSubmissionKeysInTheTextEditor() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = NSTextView(frame: window.contentView!.bounds)
        window.contentView = editor
        #expect(window.makeFirstResponder(editor))

        let navigator = Navigator()
        var actions: [String] = []
        let router = KeyRouter(navigator: navigator) { actions.append("close") }
        router.start(for: window)
        defer { router.stop() }
        router.setBindings([
            KeyBinding(id: "submit", title: "Use Snippet", chord: KeyChord(.return)) { actions.append("submit") },
            KeyBinding(id: "next", title: "Next Snippet", chord: KeyChord(.downArrow)) { actions.append("next") },
            KeyBinding(id: "tab", title: "Next Field", chord: KeyChord(.tab)) { actions.append("tab") },
        ], for: .root, owner: UUID())

        editor.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        for code in [kVK_Return, kVK_DownArrow, kVK_Tab, kVK_Escape] {
            #expect(!router.handle(try event(code, window: window)))
        }
        #expect(actions.isEmpty)

        editor.unmarkText()
        #expect(router.handle(try event(kVK_Return, window: window)))
        #expect(router.handle(try event(kVK_Escape, window: window)))
        #expect(actions == ["submit", "close"])
    }

    @Test func compositionCannotActivateAnActionMenuSelection() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        window.contentView?.addSubview(field)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.isFieldEditor)

        let router = KeyRouter(navigator: Navigator(), onEscapeAtRoot: {})
        router.start(for: window)
        defer { router.stop() }
        var performed = false
        router.actionMenu.open([
            KeyBinding(id: "delete", title: "Delete Snippet") { performed = true },
        ], returningFocusTo: field)
        editor.setMarkedText("削除", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        #expect(!router.handle(try event(kVK_Return, window: window)))
        #expect(!router.handle(try event(kVK_Escape, window: window)))
        #expect(router.actionMenu.isOpen)
        #expect(!performed)

        editor.unmarkText()
        #expect(router.handle(try event(kVK_Return, window: window)))
        #expect(performed)
        #expect(!router.actionMenu.isOpen)
    }

    private func event(_ code: Int, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: UInt16(code)))
    }
}
