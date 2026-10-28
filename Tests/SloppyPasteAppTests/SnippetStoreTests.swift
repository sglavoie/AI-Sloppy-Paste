import Foundation
import Testing
import SloppyCore
@testable import SloppyPasteApp

@Suite @MainActor struct SnippetStoreTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "SloppyStoreTests-\(UUID().uuidString)")

    @Test func failedReloadBlocksMutationsAndImportsUntilAReadSucceeds() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let original = StorageData(snippets: [Snippet(id: "a", title: "A", content: "Original", createdAt: 1, updatedAt: 1)])
        try file.save(original)
        let store = SnippetStore(file: file, now: { 10 })
        store.load()
        let modified = try #require(file.modificationDate())

        // A directory at the file path reliably causes a read error on macOS.
        try FileManager.default.removeItem(at: file.url)
        try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: false)
        store.load()
        #expect(store.lastError != nil)
        #expect(store.data == original)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.url.path)

        var ranMutation = false
        #expect(throws: (any Error).self) {
            try store.mutate { repository, _ in
                ranMutation = true
                repository.deleteSnippet(id: "a")
            }
        }
        #expect(!ranMutation)
        let payload = ImportPayload(snippets: [])
        #expect(throws: (any Error).self) { try store.importPayload(payload, mode: .replace) }
        #expect(!FileManager.default.fileExists(atPath: file.backupURL.path))
        #expect(store.data == original)

        try FileManager.default.removeItem(at: file.url)
        var external = original
        external.snippets[0].content = "External edit"
        try file.save(external)
        // A previous read error must trigger a retry even with the old timestamp.
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.url.path)
        try store.recordUse(id: "a")
        #expect(store.lastError == nil)
        #expect(store.snippets[0].content == "External edit")
        #expect(store.snippets[0].useCount == 1)
        #expect(try file.read() == store.data)
    }

    @Test func mutationLoadsExistingDataEvenBeforeInitialLoad() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        try file.save(StorageData(snippets: [Snippet(id: "a", title: "A", content: "Keep", createdAt: 1, updatedAt: 1)]))
        let store = SnippetStore(file: file, now: { 10 })
        try store.mutate { repository, now in
            repository.addSnippet(title: "B", content: "New", now: now, id: "b")
        }
        #expect(store.snippets.map(\.id) == ["a", "b"])
    }

    @Test func futureStorageVersionBlocksEditsAndImportsWithoutChangingFile() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let original = StorageData(snippets: [Snippet(id: "a", title: "A", content: "Keep", createdAt: 1, updatedAt: 1)])
        try file.save(original)
        let store = SnippetStore(file: file, now: { 10 })
        store.load()

        let future = Data(#"{"version":99,"snippets":{"newFormat":true},"unknown":"preserve"}"#.utf8)
        try future.write(to: file.url, options: .atomic)
        store.load()
        #expect(store.lastError?.contains("99") == true)
        #expect(store.data == original)
        #expect(store.quarantinedURL == nil)

        var ranMutation = false
        #expect(throws: (any Error).self) {
            try store.mutate { repository, _ in
                ranMutation = true
                repository.deleteSnippet(id: "a")
            }
        }
        #expect(!ranMutation)
        for mode in ImportMode.allCases {
            #expect(throws: (any Error).self) {
                try store.importPayload(ImportPayload(snippets: []), mode: mode)
            }
        }
        #expect(try Data(contentsOf: file.url) == future)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["data.json"])
        #expect(store.data == original)
    }

    @Test(arguments: [false, true])
    func writesPreserveExternalEditsWithUnchangedModificationDate(importing: Bool) throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let original = StorageData(snippets: [Snippet(id: "a", title: "A", content: "Original", createdAt: 1, updatedAt: 1)])
        try file.save(original)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: file.url.path)
        let store = SnippetStore(file: file, now: { 10 })
        store.load()
        let modified = try #require(file.modificationDate())

        var external = original
        external.snippets[0].content = "Modified"
        try file.save(external)
        // Sync tools can preserve timestamps when replacing the data file.
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.url.path)
        #expect(file.modificationDate() == modified)

        if importing {
            try store.importPayload(ImportPayload(snippets: []), mode: .merge)
        } else {
            try store.recordUse(id: "a")
        }
        #expect(store.snippets[0].content == "Modified")
        #expect(try file.read().snippets[0].content == "Modified")
    }

    @Test func replaceImportRejectsChangesMadeAfterConfirmation() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let original = StorageData(snippets: [Snippet(id: "a", title: "A", content: "Original", createdAt: 1, updatedAt: 1)])
        try file.save(original)
        let store = SnippetStore(file: file, now: { 10 })
        try store.requireCurrentData()
        let confirmed = store.data

        var external = original
        external.snippets.append(Snippet(id: "b", title: "B", content: "External", createdAt: 2, updatedAt: 2))
        try file.save(external)
        let replacement = ImportPayload(snippets: [])

        #expect(throws: (any Error).self) {
            try store.importPayload(replacement, mode: .replace, expectedCurrent: confirmed)
        }
        #expect(store.lastError?.contains("changed while the import dialog") == true)
        #expect(try file.read() == external)
        #expect(!FileManager.default.fileExists(atPath: file.backupURL.path))

        try store.importPayload(replacement, mode: .replace, expectedCurrent: external)
        #expect(store.lastError == nil)
        #expect(try file.read().snippets.isEmpty)
        #expect(try Data(contentsOf: file.backupURL) == StorageCoding.encode(external))
    }
}
