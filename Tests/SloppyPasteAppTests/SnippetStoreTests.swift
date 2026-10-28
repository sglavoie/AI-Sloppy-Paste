import Foundation
import Testing
import SloppyCore
@testable import SloppyPasteApp

@Suite @MainActor struct SnippetStoreTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "SloppyStoreTests-\(UUID().uuidString)")

    @Test func openFormRejectsExternalContentChangesButAllowsMetadataChanges() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let original = StorageData(snippets: [
            Snippet(id: "a", title: "A", content: "Hello {{name}}", createdAt: 1, updatedAt: 1)
        ])
        try file.save(original)
        let store = SnippetStore(file: file, now: { 10 })
        store.load()

        var external = original
        external.snippets[0].title = "Renamed"
        try file.save(external)
        try store.requireUnchangedSnippetContent(id: "a", expectedContent: original.snippets[0].content)

        external.snippets[0].content = "Changed {{name}}"
        try file.save(external)
        #expect(throws: (any Error).self) {
            try store.requireUnchangedSnippetContent(id: "a", expectedContent: original.snippets[0].content)
        }
        #expect(store.snippets[0].content == "Changed {{name}}")
        #expect(try file.read() == external)

        external.snippets.removeAll()
        try file.save(external)
        #expect(throws: (any Error).self) {
            try store.requireUnchangedSnippetContent(id: "a", expectedContent: original.snippets[0].content)
        }
    }

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
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: directory.path)) == ["data.json", "data.json.lock"])
        #expect(store.data == original)
    }

    @Test func malformedCurrentFieldKeepsLastGoodDataAndBlocksWrites() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let original = StorageData(snippets: [Snippet(id: "a", title: "A", content: "Keep", createdAt: 1, updatedAt: 1)])
        try file.save(original)
        let store = SnippetStore(file: file, now: { 10 })
        store.load()

        let malformed = Data(#"{"version":7,"snippets":[{"id":"a","title":"A","content":"Keep","description":"","tags":"work","createdAt":1,"updatedAt":1,"useCount":0,"isFavorite":false,"isArchived":false,"isPinned":false}],"tags":[],"placeholderHistory":{}}"#.utf8)
        try malformed.write(to: file.url, options: .atomic)
        store.reloadIfChanged()

        #expect(store.data == original)
        #expect(store.lastError?.contains("snippets[0].tags") == true)
        #expect(store.quarantinedURL == nil)
        #expect(throws: (any Error).self) { try store.recordUse(id: "a") }
        #expect(throws: (any Error).self) {
            try store.importPayload(ImportPayload(snippets: []), mode: .replace)
        }
        #expect(try Data(contentsOf: file.url) == malformed)
        #expect(!FileManager.default.fileExists(atPath: file.backupURL.path))
    }

    @Test func duplicateIDsFromExternalEditKeepLastGoodDataAndBlockMutations() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let snippet = Snippet(id: "same-id", title: "First", content: "one", createdAt: 1, updatedAt: 1)
        let original = StorageData(snippets: [snippet])
        try file.save(original)
        let store = SnippetStore(file: file, now: { 10 })
        store.load()

        var duplicate = snippet
        duplicate.title = "Second"
        let bytes = try StorageCoding.encode(StorageData(snippets: [snippet, duplicate]))
        try bytes.write(to: file.url, options: .atomic)
        store.reloadIfChanged()

        #expect(store.data == original)
        #expect(store.lastError?.contains("same-id") == true)
        #expect(store.quarantinedURL == nil)
        #expect(throws: (any Error).self) { try store.recordUse(id: "same-id") }
        #expect(throws: (any Error).self) {
            try store.importPayload(ImportPayload(snippets: []), mode: .replace)
        }
        #expect(try Data(contentsOf: file.url) == bytes)
        #expect(!FileManager.default.fileExists(atPath: file.backupURL.path))

        try file.save(original)
        try store.recordUse(id: "same-id")
        #expect(store.lastError == nil)
        #expect(store.snippets[0].useCount == 1)
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

    @Test func pickerRefreshSeesExternalEditWithUnchangedModificationDate() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let original = StorageData(snippets: [
            Snippet(id: "a", title: "A", content: "Original", createdAt: 1, updatedAt: 1)
        ])
        try file.save(original)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: file.url.path)
        let store = SnippetStore(file: file, now: { 10 })
        store.load()
        let modified = try #require(file.modificationDate())

        var external = original
        external.snippets[0].content = "External edit"
        try file.save(external)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.url.path)
        #expect(file.modificationDate() == modified)

        store.reloadIfChanged()
        #expect(store.snippets[0].content == "External edit")
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

    @Test(arguments: ["{unfinished", #"{"version":7}"#])
    func partialExternalWritePreservesLoadedDataAndBlocksEdits(incomplete: String) throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let original = StorageData(snippets: [Snippet(id: "a", title: "A", content: "Keep", createdAt: 1, updatedAt: 1)])
        try file.save(original)
        let store = SnippetStore(file: file, now: { 10 })
        store.load()

        try Data(incomplete.utf8).write(to: file.url)
        #expect(throws: (any Error).self) { try store.requireCurrentData() }
        #expect(store.data == original)
        #expect(store.quarantinedURL == nil)
        #expect(try String(contentsOf: file.url, encoding: .utf8) == incomplete)
        #expect(throws: (any Error).self) { try store.recordUse(id: "a") }

        try file.save(original)
        try store.recordUse(id: "a")
        #expect(store.snippets[0].useCount == 1)
    }

    @Test func disappearedExternalFileDoesNotBecomeAnEmptyStore() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let original = StorageData(snippets: [Snippet(id: "a", title: "A", content: "Keep", createdAt: 1, updatedAt: 1)])
        try file.save(original)
        let store = SnippetStore(file: file, now: { 10 })
        store.load()

        try FileManager.default.removeItem(at: file.url)
        #expect(throws: (any Error).self) { try store.recordUse(id: "a") }
        #expect(store.data == original)
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test func uncoordinatedWriteDuringMutationIsNotOverwritten() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let original = StorageData(snippets: [Snippet(id: "a", title: "A", content: "Keep", createdAt: 1, updatedAt: 1)])
        var external = original
        external.snippets[0].content = "External"
        try file.save(original)
        let store = SnippetStore(file: file, now: { 10 })
        store.load()

        #expect(throws: StorageError.dataChangedSinceRead) {
            try store.mutate { repository, now in
                try file.save(external)
                try repository.recordUse(id: "a", now: now)
            }
        }
        #expect(try file.read() == external)
        #expect(store.lastError != nil)
    }
}
