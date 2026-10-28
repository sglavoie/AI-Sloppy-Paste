import Foundation
import Testing
import SloppyCore
@testable import SloppyPasteApp

@Suite @MainActor struct SnippetActionsTests {
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
