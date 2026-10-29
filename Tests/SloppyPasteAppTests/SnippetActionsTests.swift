import Foundation
import Testing
import SloppyCore
@testable import SloppyPasteApp

@Suite @MainActor struct SnippetActionsTests {
    @Test func externallyChangedSnippetCannotBeDeletedFromStaleConfirmation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SloppyActionsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let confirmed = Snippet(id: "selected", title: "Selected", content: "Old text", createdAt: 1, updatedAt: 1)
        try file.save(StorageData(snippets: [confirmed]))
        let store = SnippetStore(file: file, now: { 10 })
        store.load()

        var changed = confirmed
        changed.content = "New text from another process"
        changed.updatedAt = 2
        try file.save(StorageData(snippets: [changed]))
        let externalBytes = try Data(contentsOf: file.url)
        let toasts = ToastCenter()
        let actions = SnippetActions(store: store, toasts: toasts)

        #expect(!actions.delete(confirmed))
        #expect(toasts.current?.message?.contains("changed") == true)
        #expect(try Data(contentsOf: file.url) == externalBytes)
        #expect(store.snippets == [changed])

        #expect(actions.delete(changed))
        #expect(try file.read().snippets.isEmpty)
    }

    @Test func externallyDeletedSnippetDoesNotReportSuccessOrRewriteData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SloppyActionsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let snippet = Snippet(id: "selected", title: "Selected", content: "Text", createdAt: 1, updatedAt: 1)
        try file.save(StorageData(snippets: [snippet]))
        let store = SnippetStore(file: file, now: { 10 })
        store.load()

        // An external writer removes the row while the picker still holds it.
        try file.save(.empty)
        let externalBytes = try Data(contentsOf: file.url)
        let toasts = ToastCenter()
        let deleted = SnippetActions(store: store, toasts: toasts).delete(snippet)

        #expect(!deleted)
        #expect(toasts.current?.style == .failure)
        #expect(toasts.current?.title == "Failed to delete snippet")
        #expect(store.snippets.isEmpty)
        #expect(try Data(contentsOf: file.url) == externalBytes)
    }
}
