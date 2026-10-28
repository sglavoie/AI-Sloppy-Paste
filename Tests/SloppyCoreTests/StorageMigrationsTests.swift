import Foundation
import Testing
@testable import SloppyCore

@Suite struct StorageMigrationsTests {
    @Test func migratesV1CategoryDataIntoNormalizedTags() throws {
        let json = #"""
        {
          "version": 1,
          "snippets": [
            { "id": "snippet-1", "title": "Legacy", "content": "Content", "category": " Work ",
              "createdAt": 1000, "updatedAt": 1000 }
          ],
          "tags": []
        }
        """#
        let result = try StorageMigrations.migrate(json: Data(json.utf8))

        #expect(result.didMigrate)
        #expect(result.data.version == StorageConstants.currentVersion)
        #expect(result.data.placeholderHistory.isEmpty)
        #expect(result.data.snippets == [
            Snippet(id: "snippet-1", title: "Legacy", content: "Content", description: "", tags: ["work"],
                    createdAt: 1000, updatedAt: 1000, useCount: 0),
        ])
        let encoded = String(decoding: try StorageCoding.encode(result.data), as: UTF8.self)
        #expect(!encoded.contains("category"))
    }

    @Test func repairsV6SnippetsWhilePreservingExplicitFields() throws {
        let json = #"""
        {
          "version": 6,
          "snippets": [
            { "id": "snippet-1", "title": "Existing", "content": "Content", "tags": ["Personal", "personal"],
              "createdAt": 1000, "updatedAt": 1000, "useCount": 0, "isFavorite": true, "isArchived": true,
              "description": "Already described" }
          ],
          "tags": [],
          "placeholderHistory": {}
        }
        """#
        let snippet = try #require(try StorageMigrations.migrate(json: Data(json.utf8)).data.snippets.first)

        #expect(snippet.tags == ["personal"])
        #expect(snippet.useCount == 0)
        #expect(snippet.isFavorite)
        #expect(snippet.isArchived)
        #expect(!snippet.isPinned)
        #expect(snippet.description == "Already described")
    }

    @Test func v4AndEarlierDropPlaceholderHistory() throws {
        let history: PlaceholderHistory = ["name": [PlaceholderHistoryValue(value: "Ada", useCount: 1, lastUsed: 1, createdAt: 1)]]
        let old = try StorageMigrations.migrate(LegacyStorageData(version: 4, placeholderHistory: history))
        let newer = try StorageMigrations.migrate(LegacyStorageData(version: 5, placeholderHistory: history))

        #expect(old.data.placeholderHistory.isEmpty)
        #expect(newer.data.placeholderHistory == history)
    }

    @Test func currentVersionIsLeftAlone() throws {
        let data = StorageData(snippets: [
            Snippet(id: "a", title: "A", content: "x", tags: ["Mixed Case"], createdAt: 1, updatedAt: 2, lastUsedAt: 3, useCount: 4),
        ])
        let result = try StorageMigrations.migrate(json: StorageCoding.encode(data))

        #expect(!result.didMigrate)
        #expect(result.data == data)
    }

    @Test func missingVersionIsStampedCurrent() throws {
        let result = try StorageMigrations.migrate(LegacyStorageData(version: nil))
        #expect(result.didMigrate)
        #expect(result.data.version == StorageConstants.currentVersion)
    }

    @Test func unversionedDocumentWithSnippetsIsMigrated() throws {
        let result = try StorageMigrations.migrate(json: Data(#"{"snippets":[]}"#.utf8))
        #expect(result.didMigrate)
        #expect(result.data == .empty)
    }

    @Test(arguments: ["1.0.0", "7.0.0"])
    func readingExportsPreservesHistory(version: String) throws {
        let json = #"{"version":"\#(version)","snippets":[],"placeholderHistory":{"name":[{"value":"Ada","useCount":1,"lastUsed":2,"createdAt":1}]}}"#
        let result = try StorageMigrations.migrate(json: Data(json.utf8))
        #expect(result.data.placeholderHistory["name"]?.first?.value == "Ada")
    }

    @Test func futureVersionIsRejected() {
        #expect(throws: StorageError.unsupportedStorageVersion(99)) {
            try StorageMigrations.migrate(LegacyStorageData(version: 99))
        }
    }

    @Test func nonStringTagsAreDropped() throws {
        let json = #"{"version": 3, "snippets": [{"id": "a", "title": "A", "content": "x", "tags": ["Work", 3, null], "createdAt": 1, "updatedAt": 1}]}"#
        let result = try StorageMigrations.migrate(json: Data(json.utf8))
        #expect(result.data.snippets.first?.tags == ["work"])
    }

    @Test func invalidDocumentThrows() {
        #expect(throws: (any Error).self) { try StorageMigrations.migrate(json: Data("[1, 2]".utf8)) }
        #expect(throws: (any Error).self) { try StorageMigrations.migrate(json: Data("{not json".utf8)) }
        #expect(throws: (any Error).self) { try StorageMigrations.migrate(json: Data("{}".utf8)) }
        #expect(throws: (any Error).self) { try StorageMigrations.migrate(json: Data(#"{"version":7}"#.utf8)) }
        #expect(throws: (any Error).self) { try StorageMigrations.migrate(json: Data(#"{"snippets":null}"#.utf8)) }
    }
}
