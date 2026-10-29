import Foundation
import Testing
import SloppyCore
@testable import SloppyPasteApp

@Suite @MainActor struct ConfirmedDestructiveActionsTests {
    @Test func tagDeletionRejectsChangedMembershipEvenWhenCountIsTheSame() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ConfirmedTag-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let first = Snippet(id: "first", title: "First", content: "One", tags: ["work"], createdAt: 1, updatedAt: 1)
        let second = Snippet(id: "second", title: "Second", content: "Two", createdAt: 1, updatedAt: 1)
        try file.save(StorageData(snippets: [first, second]))
        let store = SnippetStore(file: file, now: { 10 })
        store.load()
        let confirmedIDs = ConfirmedDestructiveActions.taggedSnippetIDs(in: store.data, tag: "work")

        var external = store.data
        external.snippets[0].tags = []
        external.snippets[1].tags = ["work"]
        try file.save(external)
        let externalBytes = try Data(contentsOf: file.url)
        let actions = ConfirmedDestructiveActions(store: store)

        #expect(throws: DestructiveActionConflict.tagMembershipChanged) {
            try actions.deleteTag("work", expectedSnippetIDs: confirmedIDs)
        }
        #expect(try Data(contentsOf: file.url) == externalBytes)

        let currentIDs = ConfirmedDestructiveActions.taggedSnippetIDs(in: store.data, tag: "work")
        external.snippets[1].content = "Unrelated edit"
        try file.save(external)
        try actions.deleteTag("work", expectedSnippetIDs: currentIDs)
        #expect(try file.read().snippets[1].tags.isEmpty)
        #expect(try file.read().snippets[1].content == "Unrelated edit")
    }

    @Test func historyClearRejectsValuesAddedAfterConfirmation() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ConfirmedHistory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let old = PlaceholderHistoryValue(value: "old", useCount: 1, lastUsed: 1, createdAt: 1)
        let added = PlaceholderHistoryValue(value: "added", useCount: 1, lastUsed: 2, createdAt: 2)
        try file.save(StorageData(placeholderHistory: ["name": [old]]))
        let store = SnippetStore(file: file, now: { 10 })
        store.load()
        let confirmedValues = store.data.placeholderHistory(forKey: "name")

        var external = store.data
        external.placeholderHistory["name"] = [old, added]
        try file.save(external)
        let externalBytes = try Data(contentsOf: file.url)
        let actions = ConfirmedDestructiveActions(store: store)

        #expect(throws: DestructiveActionConflict.historyChanged) {
            try actions.clearHistory(key: "name", expectedValues: confirmedValues)
        }
        #expect(try Data(contentsOf: file.url) == externalBytes)
        #expect(try actions.clearHistory(key: "name", expectedValues: [old, added]) == 2)
        #expect(try file.read().placeholderHistory["name"] == nil)
    }

    @Test func valueDeletionRejectsUpdatedUseCount() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ConfirmedValue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StorageFile(url: directory.appending(path: "data.json"))
        let confirmed = PlaceholderHistoryValue(value: "Ada", useCount: 1, lastUsed: 1, createdAt: 1)
        let other = PlaceholderHistoryValue(value: "Bob", useCount: 1, lastUsed: 1, createdAt: 1)
        try file.save(StorageData(placeholderHistory: ["name": [confirmed, other]]))
        let store = SnippetStore(file: file, now: { 10 })
        store.load()

        var updated = confirmed
        updated.useCount = 2
        updated.lastUsed = 2
        try file.save(StorageData(placeholderHistory: ["name": [updated, other]]))
        let externalBytes = try Data(contentsOf: file.url)
        let actions = ConfirmedDestructiveActions(store: store)

        #expect(throws: DestructiveActionConflict.historyValueChanged) {
            try actions.deleteHistoryValue(key: "name", expectedValue: confirmed)
        }
        #expect(try Data(contentsOf: file.url) == externalBytes)
        try actions.deleteHistoryValue(key: "name", expectedValue: updated)
        #expect(try file.read().placeholderHistory["name"] == [other])
    }
}
