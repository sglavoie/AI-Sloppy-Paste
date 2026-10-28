import AppKit
import SloppyCore
import Testing
@testable import SloppyPasteApp

@Suite @MainActor struct PickerTargetTests {
    @Test func ownAppAndMissingFrontmostAppHaveNoPasteTarget() {
        let current = NSRunningApplication.current
        let ownPID = current.processIdentifier

        #expect(PickerPanelController.pasteTarget(frontmost: current, ownPID: ownPID) == nil)
        #expect(PickerPanelController.pasteTarget(frontmost: nil, ownPID: ownPID) == nil)
        #expect(PickerPanelController.pasteTarget(frontmost: current, ownPID: ownPID + 1)?.processIdentifier == ownPID)
    }

    @Test func directDeliveryRejectsContentChangedAfterSelection() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appending(path: "SloppyDeliveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let selected = Snippet(id: "a", title: "A", content: "Old text", createdAt: 1, updatedAt: 1)
        try file.save(StorageData(snippets: [selected]))
        let store = SnippetStore(file: file, now: { 10 })
        store.load()
        let picker = PickerPanelController(store: store, accessibility: AccessibilityPermission())

        var edited = selected
        edited.content = "New text"
        try file.save(StorageData(snippets: [edited]))
        let accepted = picker.deliver(
            PreparedSnippet(content: selected.content), snippetID: selected.id,
            expectedContent: selected.content, mode: .copy)

        #expect(!accepted)
        #expect(store.snippets.first?.content == edited.content)
        #expect(try file.read().snippets.first?.content == edited.content)

        // A failed reload leaves the last good row visible, but must not let
        // that cached row reach the clipboard either.
        try Data(#"{"version":7,"snippets":[]"#.utf8).write(to: file.url, options: .atomic)
        let acceptedDuringFailure = picker.deliver(
            PreparedSnippet(content: edited.content), snippetID: edited.id,
            expectedContent: edited.content, mode: .copy)
        #expect(!acceptedDuringFailure)
        #expect(store.lastError != nil)
        #expect(store.snippets.first?.content == edited.content)
    }
}
