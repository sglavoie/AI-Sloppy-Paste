import Foundation
import Testing
@testable import SloppyCore

@Suite struct StorageFileTests {
    let directory: URL
    let file: StorageFile

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "SloppyCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        file = StorageFile(url: directory.appending(path: "nested/data.json"))
    }

    func contents() throws -> String {
        String(decoding: try Data(contentsOf: file.url), as: UTF8.self)
    }

    @Test func defaultLocationIsApplicationSupport() {
        #expect(StorageFile.defaultURL.path.hasSuffix("Library/Application Support/SloppyPaste/data.json"))
    }

    @Test func missingFileLoadsEmpty() throws {
        let result = try file.load(now: 1)
        #expect(result.data == .empty)
        #expect(!result.didMigrate)
        #expect(result.quarantinedURL == nil)
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test func saveWritesPrettyPrintedJSONAndLoadsBack() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = StorageData(snippets: [Snippet(id: "a", title: "A", content: "x/y", createdAt: 1, updatedAt: 1)])

        try file.save(data)

        #expect(try contents().contains("\n  \"placeholderHistory\""))
        #expect(try contents().contains("\"x/y\""))
        #expect(try file.load(now: 2).data == data)
        #expect(file.modificationDate() != nil)
        #expect(file.size() > 0)
    }

    @Test func legacyFileIsMigratedAndSavedBack() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = #"{"version": 1, "snippets": [{"id": "a", "title": "A", "content": "x", "category": "Work", "createdAt": 1, "updatedAt": 1}], "tags": []}"#
        try Data(legacy.utf8).write(to: file.url)

        let result = try file.load(now: 2)

        #expect(result.didMigrate)
        #expect(result.data.snippets.first?.tags == ["work"])
        #expect(try contents().contains("\"version\" : 7"))
        #expect(try !contents().contains("category"))
    }

    @Test func readMigratesWithoutChangingBytesOrModificationDate() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = #"{"version":1,"snippets":[{"id":"a","title":"A","content":"x","category":"Work","createdAt":1,"updatedAt":1}]}"#
        try Data(legacy.utf8).write(to: file.url)
        let modified = file.modificationDate()

        let data = try file.read()

        #expect(data.version == StorageConstants.currentVersion)
        #expect(data.snippets.first?.tags == ["work"])
        #expect(try contents() == legacy)
        #expect(file.modificationDate() == modified)
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.url.deletingLastPathComponent().path) == ["data.json"])
    }

    @Test func readRejectsCorruptionWithoutQuarantining() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: file.url)

        #expect(throws: (any Error).self) { try file.read() }

        #expect(try contents() == "{broken")
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.url.deletingLastPathComponent().path) == ["data.json"])
    }

    @Test func snapshotRejectsAnUncoordinatedChange() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = StorageData(snippets: [Snippet(id: "a", title: "A", content: "first", createdAt: 1, updatedAt: 1)])
        try file.save(original)
        let snapshot = try file.readSnapshot()
        var external = original
        external.snippets[0].content = "second"
        try file.save(external)

        #expect(throws: StorageError.dataChangedSinceRead) {
            try file.save(original, ifUnchangedFrom: snapshot)
        }
        #expect(try file.read() == external)
    }

    @Test func atomicCommitRestoresAnUncoordinatedWrite() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = StorageData(snippets: [Snippet(id: "a", title: "A", content: "first", createdAt: 1, updatedAt: 1)])
        try file.save(original)
        let snapshot = try file.readSnapshot()
        var external = original
        external.snippets[0].content = "external"
        let externalBytes = try StorageCoding.encode(external)

        #expect(throws: StorageError.dataChangedSinceRead) {
            try file.save(original, ifUnchangedFrom: snapshot) {
                try externalBytes.write(to: file.url, options: .atomic)
            }
        }
        #expect(try Data(contentsOf: file.url) == externalBytes)
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: file.url.deletingLastPathComponent().path))
            == ["data.json"])
    }

    @Test func atomicCreateDoesNotReplaceACompetingNewFile() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = try file.readSnapshot()
        let external = Data("external".utf8)

        #expect(throws: StorageError.dataChangedSinceRead) {
            try file.save(.empty, ifUnchangedFrom: snapshot) {
                try external.write(to: file.url, options: .atomic)
            }
        }
        #expect(try Data(contentsOf: file.url) == external)
    }

    @Test func sidecarLockSerializesConcurrentTransactions() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let secondAttempting = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)
        let firstFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            defer { firstFinished.signal() }
            try? file.withExclusiveLock {
                firstEntered.signal()
                releaseFirst.wait()
            }
        }
        #expect(firstEntered.wait(timeout: .now() + 5) == .success)
        DispatchQueue.global().async {
            secondAttempting.signal()
            _ = try? file.withExclusiveLock { secondEntered.signal() }
        }
        #expect(secondAttempting.wait(timeout: .now() + 5) == .success)
        #expect(secondEntered.wait(timeout: .now() + 0.1) == .timedOut)
        releaseFirst.signal()
        #expect(firstFinished.wait(timeout: .now() + 5) == .success)
        #expect(secondEntered.wait(timeout: .now() + 5) == .success)
    }

    @Test func readMissingFileDoesNotCreateItsDirectory() throws {
        #expect(try file.read() == .empty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test(arguments: ["99", #""99""#, #""99.0.0""#], ["[]", #"{"futureShape": true}"#])
    func futureVersionIsNeitherRewrittenNorQuarantined(version: String, snippets: String) throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"version":\#(version),"snippets":\#(snippets),"futureField":"keep me"}"#.utf8)
        try original.write(to: file.url)

        #expect(throws: StorageError.unsupportedStorageVersion(99)) { try file.read() }
        #expect(throws: StorageError.unsupportedStorageVersion(99)) { try file.load(now: 1) }

        #expect(try Data(contentsOf: file.url) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.url.deletingLastPathComponent().path) == ["data.json"])
    }

    @Test func invalidNumericVersionIsLeftUntouched() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"version":8.5,"snippets":[]}"#.utf8)
        try original.write(to: file.url)

        #expect(throws: StorageError.invalidStorageVersion) { try file.load(now: 1) }
        #expect(try Data(contentsOf: file.url) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.url.deletingLastPathComponent().path) == ["data.json"])
    }

    @Test func malformedCurrentFileIsNotQuarantinedOrChangedByImport() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let malformed = Data(#"{"version":7,"snippets":[{"id":"a","title":"A","content":"x","description":"","tags":"work","createdAt":1,"updatedAt":1,"useCount":3,"isFavorite":false,"isArchived":false,"isPinned":false}],"tags":[],"placeholderHistory":{}}"#.utf8)
        try malformed.write(to: file.url)

        #expect(throws: StorageError.invalidCurrentStorageData("snippets[0].tags")) { try file.load(now: 1) }
        #expect(throws: StorageError.invalidCurrentStorageData("snippets[0].tags")) { try file.read() }
        #expect(throws: StorageError.invalidCurrentStorageData("snippets[0].tags")) {
            try file.withExclusiveLock {
                let snapshot = try file.readSnapshot()
                _ = try file.importPayload(ImportPayload(snippets: []), into: snapshot.data,
                    mode: .merge, ifUnchangedFrom: snapshot)
            }
        }
        #expect(try Data(contentsOf: file.url) == malformed)
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: file.url.deletingLastPathComponent().path)) == ["data.json", "data.json.lock"])
    }

    @Test func duplicateIDsLeaveDataAndBackupUntouchedOnReplace() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = StorageData(snippets: [Snippet(id: "old", title: "Old", content: "old", createdAt: 1, updatedAt: 1)])
        try file.save(original)
        let bytes = try Data(contentsOf: file.url)
        let duplicate = LegacySnippet(id: "dup", title: "Duplicate", content: "text", createdAt: 1, updatedAt: 1)
        let payload = ImportPayload(snippets: [duplicate, duplicate])

        #expect(throws: ImportValidationError.duplicateSnippetID("dup")) {
            try file.importPayload(payload, into: original, mode: .replace)
        }
        #expect(try Data(contentsOf: file.url) == bytes)
        #expect(!FileManager.default.fileExists(atPath: file.backupURL.path))
    }

    @Test func duplicateIDsInStoredFileBlockReadsAndWritesWithoutMovingBytes() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let duplicate = Snippet(id: "same-id", title: "First", content: "one", createdAt: 1, updatedAt: 1)
        var second = duplicate
        second.title = "Second"
        let data = StorageData(snippets: [duplicate, second])
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)

        for version in [1, StorageConstants.currentVersion] {
            var document = data
            document.version = version
            let original = try StorageCoding.encode(document)
            try original.write(to: file.url, options: .atomic)

            #expect(throws: StorageError.duplicateStoredSnippetID("same-id")) { try file.read() }
            #expect(throws: StorageError.duplicateStoredSnippetID("same-id")) { try file.load(now: 10) }
            #expect(try Data(contentsOf: file.url) == original)
            #expect(!FileManager.default.fileExists(atPath: file.backupURL.path))
        }

        let beforeSave = try Data(contentsOf: file.url)
        #expect(throws: StorageError.duplicateStoredSnippetID("same-id")) { try file.save(data) }
        #expect(try Data(contentsOf: file.url) == beforeSave)
    }

    @Test func corruptFileIsQuarantinedNotOverwritten() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: file.url)

        let result = try file.load(now: 1234)

        let quarantined = try #require(result.quarantinedURL)
        #expect(quarantined.lastPathComponent == "data.corrupt-1234.json")
        #expect(String(decoding: try Data(contentsOf: quarantined), as: UTF8.self) == "{broken")
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
        #expect(result.data == .empty)
    }

    @Test func incompleteObjectIsQuarantinedNotRewritten() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let incomplete = Data(#"{"version":7}"#.utf8)
        try incomplete.write(to: file.url)

        let result = try file.load(now: 1234)

        let quarantined = try #require(result.quarantinedURL)
        #expect(try Data(contentsOf: quarantined) == incomplete)
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
        #expect(result.data == .empty)
    }

    @Test func secondQuarantineInTheSameMillisecondKeepsTheFirst() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{first".utf8).write(to: file.url)
        let first = try #require(try file.load(now: 1234).quarantinedURL)
        try Data("{second".utf8).write(to: file.url)
        let second = try #require(try file.load(now: 1234).quarantinedURL)

        #expect(second.lastPathComponent == "data.corrupt-1234-1.json")
        #expect(String(decoding: try Data(contentsOf: first), as: UTF8.self) == "{first")
        #expect(String(decoding: try Data(contentsOf: second), as: UTF8.self) == "{second")
    }

    @Test func emptyFileIsQuarantined() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: file.url)

        let result = try file.load(now: 5)

        #expect(result.quarantinedURL?.lastPathComponent == "data.corrupt-5.json")
        #expect(result.data == .empty)
    }

    @Test func modificationDateChangesWhenTheFileIsReplaced() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(file.modificationDate() == nil)
        try file.save(.empty)
        let first = try #require(file.modificationDate())
        try FileManager.default.setAttributes(
            [.modificationDate: first.addingTimeInterval(-60)], ofItemAtPath: file.url.path)
        #expect(file.modificationDate() != first)
    }

    @Test func replaceImportWritesBackupFirst() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = StorageData(snippets: [Snippet(id: "old", title: "Old", content: "x", createdAt: 1, updatedAt: 1)])
        try file.save(current)
        let before = try contents()
        let payload = ImportPayload(snippets: [LegacySnippet(id: "new", title: "New", content: "y", createdAt: 2, updatedAt: 2)])

        let next = try file.importPayload(payload, into: current, mode: .replace)

        #expect(next.snippets.map(\.id) == ["new"])
        #expect(String(decoding: try Data(contentsOf: file.backupURL), as: UTF8.self) == before)
        #expect(file.backupURL.lastPathComponent == "data.json.bak")
        #expect(try file.load(now: 3).data == next)
    }

    @Test func mergeImportDoesNotWriteBackup() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try file.save(.empty)
        let payload = ImportPayload(snippets: [LegacySnippet(id: "new", title: "New", content: "y", createdAt: 2, updatedAt: 2)])

        let next = try file.importPayload(payload, into: .empty, mode: .merge)

        #expect(next.snippets.count == 1)
        #expect(!FileManager.default.fileExists(atPath: file.backupURL.path))
    }
}
