import AppKit
import Carbon.HIToolbox
import Testing
@testable import SloppyPasteApp

@Suite @MainActor struct KeyRouterTests {
    @Test func copyPreservesSelectedTextBeforeUsingTheScreenShortcut() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let text = NSTextView(frame: window.contentView!.bounds)
        text.string = "Snippet content"
        text.isEditable = false
        text.isSelectable = true
        window.contentView = text
        #expect(window.makeFirstResponder(text))

        var copiedTitle = false
        let router = KeyRouter(navigator: Navigator(), onEscapeAtRoot: {})
        router.start(for: window)
        defer { router.stop() }
        router.setBindings([
            KeyBinding(id: "copyTitle", title: "Copy Title", chord: KeyChord(.character("c"), .command)) {
                copiedTitle = true
            },
        ], for: .root, owner: UUID())
        let copy = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false,
            keyCode: UInt16(kVK_ANSI_C)))

        text.setSelectedRange(NSRange(location: 0, length: 7))
        #expect(!router.handle(copy), "Selected text must receive the native Copy command")
        #expect(!copiedTitle)

        text.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(router.handle(copy))
        #expect(copiedTitle)
    }

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

    @Test func heldSubmitDoesNotRepeatWhileNavigationDoes() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var submits = 0
        var moves = 0
        var closes = 0
        let router = KeyRouter(navigator: Navigator()) { closes += 1 }
        router.start(for: window)
        defer { router.stop() }
        router.setBindings([
            KeyBinding(id: "submit", title: "Copy and Keep Open", chord: KeyChord(.return)) { submits += 1 },
            KeyBinding(id: "up", title: "Previous", chord: KeyChord(.upArrow), allowsKeyRepeat: true) { moves += 1 },
        ], for: .root, owner: UUID())

        #expect(router.handle(try event(kVK_Return, window: window)))
        #expect(router.handle(try event(kVK_Return, window: window, isARepeat: true)))
        #expect(router.handle(try event(kVK_UpArrow, window: window, isARepeat: true)))
        #expect(router.handle(try event(kVK_Escape, window: window, isARepeat: true)))
        #expect(submits == 1)
        #expect(moves == 1)
        #expect(closes == 0)

        router.actionMenu.open([
            KeyBinding(id: "delete", title: "Delete") { submits += 1 },
        ], returningFocusTo: nil)
        #expect(router.handle(try event(kVK_Return, window: window, isARepeat: true)))
        #expect(router.actionMenu.isOpen)
        #expect(submits == 1)
    }

    private func event(_ code: Int, window: NSWindow, isARepeat: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: isARepeat, keyCode: UInt16(code)))
    }
}
