import Foundation
import Testing
import SloppyCore
@testable import SloppyPasteApp

@Suite @MainActor struct TagPickerModelTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "TagPickerTests-\(UUID().uuidString)")

    @Test(arguments: [["work", "external"], [String]()])
    func externalTagEditsAreNotOverwritten(tags: [String]) throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let snippet = Snippet(id: "a", title: "A", content: "Text", tags: ["work"], createdAt: 1, updatedAt: 1)
        try file.save(StorageData(snippets: [snippet]))
        let store = SnippetStore(file: file, now: { 10 })
        store.load()
        let toasts = ToastCenter()
        let model = TagPickerModel(snippet: snippet, store: store, toasts: toasts)
        let modified = try #require(file.modificationDate())

        var external = store.data
        external.snippets[0].tags = tags
        try file.save(external)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.url.path)
        let contents = try Data(contentsOf: file.url)

        model.toggle("local")

        #expect(try Data(contentsOf: file.url) == contents)
        #expect(model.selectedTags == ["work"])
        #expect(toasts.current?.style == .failure)
        #expect(toasts.current?.message?.contains("reopen") == true)
    }

    @Test func successiveTogglesPreserveUnrelatedExternalEdits() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let snippet = Snippet(id: "a", title: "A", content: "Text", tags: ["work"], createdAt: 1, updatedAt: 1)
        try file.save(StorageData(snippets: [snippet]))
        let store = SnippetStore(file: file, now: { 10 })
        store.load()
        let toasts = ToastCenter()
        let model = TagPickerModel(snippet: snippet, store: store, toasts: toasts)

        model.toggle("local")
        #expect(toasts.current?.style == .success)
        var external = try file.read()
        external.snippets[0].content = "External text"
        external.snippets[0].useCount = 5
        external.snippets[0].tags = ["WORK", "local"]
        try file.save(external)

        model.toggle("work")
        #expect(toasts.current?.style == .success)
        let saved = try file.read().snippets[0]
        #expect(saved.tags == ["local"])
        #expect(saved.content == "External text")
        #expect(saved.useCount == 5)
        #expect(model.selectedTags == saved.tags)
    }
}
