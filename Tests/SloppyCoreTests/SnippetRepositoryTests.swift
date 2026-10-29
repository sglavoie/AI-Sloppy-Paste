import Foundation
import Testing
@testable import SloppyCore

@Suite struct SnippetRepositoryRecordUseTests {
    let now: Int64 = 1_700_000_000_000

    @Test func recordsUsageAndHistoryWithOneTimestamp() throws {
        var repo = SnippetRepository()
        let snippet = repo.addSnippet(title: "Test", content: "Content", now: 1)

        try repo.recordUse(id: snippet.id, placeholderValues: [.init(key: "name", value: "Ada", isSaved: true)], now: now)

        let stored = try #require(repo.snippet(id: snippet.id))
        #expect(stored.useCount == 1)
        #expect(stored.lastUsedAt == now)
        #expect(stored.updatedAt == now)
        #expect(repo.data.placeholderHistory(forKey: "name") == [
            PlaceholderHistoryValue(value: "Ada", useCount: 1, lastUsed: now, createdAt: now),
        ])
    }

    @Test func skipsBlankAndOptedOutValues() throws {
        var repo = SnippetRepository()
        let snippet = repo.addSnippet(title: "Test", content: "Content", now: 1)

        try repo.recordUse(id: snippet.id, placeholderValues: [
            .init(key: "blank", value: "  ", isSaved: true),
            .init(key: "not-saved", value: "value", isSaved: false),
        ], now: now)

        #expect(repo.snippets[0].useCount == 1)
        #expect(repo.data.placeholderHistory(forKey: "blank").isEmpty)
        #expect(repo.data.placeholderHistory(forKey: "not-saved").isEmpty)
    }

    @Test(arguments: ["\u{FEFF}", " \u{FEFF}\n"])
    func historyRejectsValuesThatRenderAsBlank(blank: String) throws {
        var repo = SnippetRepository()
        let snippet = repo.addSnippet(title: "Test", content: "{{name}}", now: 1)
        try repo.recordUse(id: snippet.id, placeholderValues: [.init(key: "name", value: blank)], now: now)
        #expect(repo.data.placeholderHistory.isEmpty)
        let added = repo.data.addPlaceholderValue(key: "name", value: blank, now: now)
        #expect(!added)

        let valid = "\u{FEFF}Ada\u{FEFF}"
        repo.data.addPlaceholderValue(key: "name", value: valid, now: now)
        #expect(throws: StorageError.emptyPlaceholderValue) {
            try repo.data.updatePlaceholderValue(key: "name", oldValue: valid, newValue: blank)
        }
        #expect(repo.data.placeholderHistory(forKey: "name").map(\.value) == [valid])
    }

    @Test func deduplicatesRepeatedPairsWithinOneUse() throws {
        var repo = SnippetRepository()
        let snippet = repo.addSnippet(title: "Test", content: "Content", now: 1)

        try repo.recordUse(id: snippet.id, placeholderValues: [
            .init(key: "name", value: "Ada"), .init(key: "name", value: "Ada"),
        ], now: now)

        #expect(repo.data.placeholderHistory(forKey: "name").map(\.useCount) == [1])
    }

    @Test func updatesExistingHistoryWithTheNewTimestamp() throws {
        var repo = SnippetRepository()
        let snippet = repo.addSnippet(title: "Test", content: "Content", now: now)
        let other = repo.addSnippet(title: "History", content: "Content", now: now)
        try repo.recordUse(id: other.id, placeholderValues: [.init(key: "name", value: "Ada")], now: now)

        try repo.recordUse(id: snippet.id, placeholderValues: [.init(key: "name", value: "Ada")], now: now + 1_000)

        #expect(repo.data.placeholderHistory(forKey: "name") == [
            PlaceholderHistoryValue(value: "Ada", useCount: 2, lastUsed: now + 1_000, createdAt: now),
        ])
    }

    @Test func missingSnippetChangesNothing() throws {
        var repo = SnippetRepository()
        let other = repo.addSnippet(title: "History", content: "Content", now: 1)
        try repo.recordUse(id: other.id, placeholderValues: [.init(key: "existing", value: "keep")], now: 2)
        let before = repo

        #expect(throws: StorageError.snippetNotFound) {
            try repo.recordUse(id: "missing", placeholderValues: [.init(key: "new", value: "value")], now: 3)
        }
        #expect(repo == before)
        #expect(StorageError.snippetNotFound.localizedDescription == "Snippet not found")
    }
}

@Suite struct SnippetRepositorySnippetTests {
    @Test func newSnippetIDsUseTheRaycastFormat() {
        var repo = SnippetRepository()
        let snippet = repo.addSnippet(title: "T", content: "C", now: 1_700_000_000_000)
        #expect(snippet.id.wholeMatch(of: /snippet-1700000000000-[0-9a-z]{9}/) != nil)
        #expect(snippet.createdAt == 1_700_000_000_000)
        #expect(snippet.lastUsedAt == nil)
    }

    @Test func updateNormalizesChangedTagsAndBumpsUpdatedAt() throws {
        var repo = SnippetRepository()
        let snippet = repo.addSnippet(title: "T", content: "C", now: 1)

        let updated = try repo.updateSnippet(id: snippet.id, now: 5) {
            $0.title = "New"
            $0.tags = ["Work", "work/projects"]
        }

        #expect(updated.title == "New")
        #expect(updated.tags == ["work/projects"])
        #expect(updated.updatedAt == 5)
        #expect(updated.createdAt == 1)
        #expect(repo.snippets == [updated])
    }

    @Test func duplicateResetsUsageAndFlags() throws {
        var repo = SnippetRepository()
        let snippet = repo.addSnippet(title: "T", content: "C", tags: ["a"], now: 1)
        try repo.recordUse(id: snippet.id, now: 2)
        try repo.toggle(\.isPinned, id: snippet.id, now: 3)

        let copy = try repo.duplicateSnippet(id: snippet.id, now: 10, newID: "copy")

        #expect(copy == Snippet(id: "copy", title: "T (Copy)", content: "C", tags: ["a"], createdAt: 10, updatedAt: 10))
        #expect(repo.snippets.count == 2)
    }

    @Test(arguments: [193, 194, 195, 200])
    func duplicateKeepsLongTitlesValid(length: Int) throws {
        var repo = SnippetRepository()
        let title = String(repeating: "👩‍💻", count: length)
        let original = repo.addSnippet(title: title, content: "Content", now: 1, id: "original")

        let copy = try repo.duplicateSnippet(id: original.id, now: 2, newID: "copy")

        #expect(Validation.validateTitle(copy.title).isValid)
        #expect(copy.title.hasSuffix(" (Copy)"))
        #expect(copy.title == String(title.prefix(min(length, 193))) + " (Copy)")
        #expect(repo.snippet(id: original.id)?.title == title)
        #expect(SnippetDraft(snippet: copy).errors.isEmpty)
    }

    @Test func toggleFlipsFlagAndReturnsNewValue() throws {
        var repo = SnippetRepository()
        let snippet = repo.addSnippet(title: "T", content: "C", now: 1)

        let favorited = try repo.toggle(\.isFavorite, id: snippet.id, now: 2)
        let unfavorited = try repo.toggle(\.isFavorite, id: snippet.id, now: 3)
        let archived = try repo.toggle(\.isArchived, id: snippet.id, now: 4)
        #expect(favorited)
        #expect(!unfavorited)
        #expect(archived)
        #expect(repo.snippets[0].updatedAt == 4)
    }

    @Test func deleteRemovesSnippet() {
        var repo = SnippetRepository()
        let snippet = repo.addSnippet(title: "T", content: "C", now: 1)
        let deleted = repo.deleteSnippet(id: snippet.id)
        #expect(deleted)
        #expect(repo.snippets.isEmpty)
    }

    @Test func deleteMissingSnippetChangesNothing() {
        var repo = SnippetRepository()
        repo.addSnippet(title: "Keep", content: "C", now: 1, id: "keep")
        let before = repo
        let deleted = repo.deleteSnippet(id: "deleted-externally")
        #expect(!deleted)
        #expect(repo == before)
    }

    @Test func deleteOnlyRemovesOneSnippetWhenGivenDuplicateIDsInMemory() {
        let first = Snippet(id: "duplicate", title: "First", content: "one", createdAt: 1, updatedAt: 1)
        var second = first
        second.title = "Second"
        var repo = SnippetRepository(data: StorageData(snippets: [first, second]))

        let deleted = repo.deleteSnippet(id: "duplicate")
        #expect(deleted)
        #expect(repo.snippets == [second])
    }
}

@Suite struct SnippetRepositoryTagTests {
    private func externallyEditedTags() -> SnippetRepository {
        var r = repo([["work"], ["work/admin"], ["workshop"]])
        r.data.snippets[0].tags = [" Work ", "WORK"]
        r.data.snippets[1].tags = ["Work/Admin", "OFFICE/Admin"]
        r.data.snippets[2].tags = ["Workshop"]
        return r
    }

    @Test func tagListNormalizesExternalEditsWithoutChangingStorage() {
        let r = externallyEditedTags()
        #expect(r.tags == ["office/admin", "work", "work/admin", "workshop"])
        #expect(r.snippets[0].tags == [" Work ", "WORK"])
    }

    @Test func deleteMatchesNormalizedTagButKeepsDescendants() throws {
        var r = externallyEditedTags()
        try r.deleteTag(" work ", now: 2)
        #expect(r.snippets.map(\.tags) == [[], ["Work/Admin", "OFFICE/Admin"], ["Workshop"]])
        #expect(r.snippets.map(\.updatedAt) == [2, 1, 1])
    }

    @Test(arguments: [false, true])
    func retagMatchesExternalCaseVariantsAndDeduplicates(merge: Bool) throws {
        var r = externallyEditedTags()
        let affected = if merge {
            try r.mergeTags(" WORK ", into: "Office", now: 2)
        } else {
            try r.renameTag(" WORK ", to: "Office", now: 2)
        }
        #expect(affected == 2)
        #expect(r.snippets.map(\.tags) == [["office"], ["office/admin"], ["Workshop"]])
        #expect(r.snippets.map(\.updatedAt) == [2, 2, 1])
    }

    @Test func mergingCaseVariantsOfSameTagThrowsWithoutMutation() {
        var r = externallyEditedTags()
        let before = r
        #expect(throws: StorageError.cannotMergeTagWithItself) {
            try r.mergeTags(" WORK ", into: "work", now: 2)
        }
        #expect(r == before)
    }

    @Test func missingTagActionsDoNotChangeSnippets() {
        var r = repo([["keep"]])
        let before = r
        #expect(throws: StorageError.tagNotFound) { try r.deleteTag("gone", now: 2) }
        #expect(throws: StorageError.tagNotFound) { try r.renameTag("gone", to: "new", now: 2) }
        #expect(throws: StorageError.tagNotFound) { try r.mergeTags("gone", into: "keep", now: 2) }
        #expect(r == before)
    }

    @Test(arguments: ["a/b/c/d/e", String(repeating: "x", count: 48)], [false, true])
    func retagRejectsInvalidDescendantsWithoutPartialChanges(target: String, merge: Bool) throws {
        var r = repo([["work"], ["work/child"], [target]])
        let before = r
        #expect(Validation.validateTag(target).isValid)
        let invalidTag = target + "/child"
        let reason = try #require(Validation.validateTag(invalidTag).error)
        #expect(throws: StorageError.invalidTag(tag: invalidTag, reason: reason)) {
            if merge {
                try r.mergeTags("work", into: target, now: 2)
            } else {
                try r.renameTag("work", to: target, now: 2)
            }
        }
        #expect(r == before)
    }

    @Test(arguments: ["a/b/c/d", String(repeating: "x", count: 44)], [false, true])
    func retagAllowsDescendantsAtValidationLimits(target: String, merge: Bool) throws {
        var r = repo([["work"], ["work/child"], [target]])
        let affected = if merge {
            try r.mergeTags("work", into: target, now: 2)
        } else {
            try r.renameTag("work", to: target, now: 2)
        }
        #expect(affected == 2)
        #expect(r.snippets.map(\.tags) == [[target], [target + "/child"], [target]])
        #expect(r.snippets.map(\.updatedAt) == [2, 2, 1])
        #expect(r.snippets.allSatisfy { SnippetDraft(snippet: $0).errors.isEmpty })
    }

    func repo(_ tagLists: [[String]]) -> SnippetRepository {
        var repo = SnippetRepository()
        for (index, tags) in tagLists.enumerated() {
            repo.addSnippet(title: "Test \(index + 1)", content: "Content", tags: tags, now: 1, id: "s\(index)")
        }
        return repo
    }

    @Test(arguments: [
        ([], []),
        ([["work", "important"], ["personal", "work"]], ["important", "personal", "work"]),
        ([[], ["work"]], ["work"]),
        ([["zebra", "apple", "banana"]], ["apple", "banana", "zebra"]),
        ([["work/projects"]], ["work/projects"]),
    ] as [([[String]], [String])])
    func tagsAreUniqueAndSorted(tagLists: [[String]], expected: [String]) {
        #expect(repo(tagLists).tags == expected)
    }

    @Test(arguments: [
        (["work", "work/projects"], ["work/projects"]),
        (["work", "work/projects", "work/projects/client-a"], ["work/projects/client-a"]),
        (["work/projects"], ["work/projects"]),
        (["work/projects", "personal/notes"], ["personal/notes", "work/projects"]),
        (["work", "personal"], ["personal", "work"]),
    ])
    func addRemovesRedundantParents(tags: [String], expected: [String]) {
        #expect(repo([tags]).snippets[0].tags == expected)
    }

    @Test func deleteTagRemovesFromAllSnippets() throws {
        var r = repo([["work", "important"], ["work", "personal"]])
        try r.deleteTag("work", now: 2)
        #expect(r.snippets.map(\.tags) == [["important"], ["personal"]])
        #expect(r.tags == ["important", "personal"])
    }

    @Test func deleteTagOnlyBumpsAffectedSnippets() throws {
        var r = repo([["work"], ["personal"]])
        try r.deleteTag("work", now: 5)
        #expect(r.snippets.map(\.updatedAt) == [5, 1])
        #expect(r.snippets[1].tags == ["personal"])
    }

    @Test(arguments: [
        ([["work"], ["important", "work"]], "work", "office", 2, [["office"], ["important", "office"]]),
        ([["work", "work/projects", "work/projects/client-a"]], "work", "office", 1, [["office/projects/client-a"]]),
        ([["work", "work/projects"]], "work/projects", "work/tasks", 1, [["work/tasks"]]),
        ([["work"], ["work/admin"], ["personal"]], "work", "office", 2, [["office"], ["office/admin"], ["personal"]]),
        ([["work/admin", "office/admin"]], "work", "office", 1, [["office/admin"]]),
        ([["work"], ["personal"]], "work", "office", 1, [["office"], ["personal"]]),
    ] as [([[String]], String, String, Int, [[String]])])
    func renameTagCascadesToDescendants(
        tagLists: [[String]], from: String, to: String, affected: Int, expected: [[String]]
    ) throws {
        var r = repo(tagLists)
        let count = try r.renameTag(from, to: to, now: 2)
        #expect(count == affected)
        #expect(r.snippets.map(\.tags) == expected)
    }

    @Test(arguments: [
        ([["work"], ["office"]], 1, [["office"], ["office"]]),
        ([["work", "office"]], 1, [["office"]]),
        ([["work", "important"], ["office", "important"], ["work", "office"]], 2, [["important", "office"], ["important", "office"], ["office"]]),
        ([["work"], ["personal"]], 1, [["office"], ["personal"]]),
        ([["work"], ["work/projects"], ["work/projects/client-a"], ["personal"]], 3,
         [["office"], ["office/projects"], ["office/projects/client-a"], ["personal"]]),
        ([["work/admin", "office/admin"]], 1, [["office/admin"]]),
    ] as [([[String]], Int, [[String]])])
    func mergeTagsIntoOffice(tagLists: [[String]], affected: Int, expected: [[String]]) throws {
        var r = repo(tagLists)
        let count = try r.mergeTags("work", into: "office", now: 2)
        #expect(count == affected)
        #expect(r.snippets.map(\.tags) == expected)
    }

    @Test func mergeTagsUpdatesTagList() throws {
        var r = repo([["work"], ["office"]])
        try r.mergeTags("work", into: "office", now: 2)
        #expect(r.tags == ["office"])
    }

    @Test func mergingATagWithItselfThrows() {
        var r = repo([["work"]])
        #expect(throws: StorageError.cannotMergeTagWithItself) { try r.mergeTags("work", into: "work", now: 2) }
    }

    @Test func operationsInSequence() throws {
        var r = repo([["work", "urgent"], ["work", "important"]])
        try r.renameTag("work", to: "office", now: 2)
        try r.deleteTag("urgent", now: 3)
        try r.mergeTags("important", into: "office", now: 4)
        #expect(r.tags == ["office"])
        #expect(r.snippets.map(\.tags) == [["office"], ["office"]])
    }
}

@Suite struct PlaceholderHistoryMutationTests {
    @Test(arguments: [false, true])
    func recordingUseRestoresLimitForOversizedStoredHistory(existingValue: Bool) {
        let limit = StorageConstants.maxStoredValuesPerKey
        let history = (0..<(limit + 5)).map {
            PlaceholderHistoryValue(value: "v\($0)", useCount: 1, lastUsed: Int64($0), createdAt: 0)
        }
        var data = StorageData(placeholderHistory: ["k": history])
        let recorded = existingValue ? "v0" : "new"
        data.addPlaceholderValue(key: "k", value: recorded, now: 1_000)

        let values = data.placeholderHistory(forKey: "k")
        #expect(values.count == limit)
        #expect(values.contains { $0.value == recorded && $0.lastUsed == 1_000 })
        #expect(!values.contains { $0.value == "v1" })
        #expect(values.contains { $0.value == "v\(limit + 4)" })
    }

    @Test func addEvictsLeastRecentlyUsedPastLimit() {
        var data = StorageData()
        for i in 0..<StorageConstants.maxStoredValuesPerKey {
            data.addPlaceholderValue(key: "k", value: "v\(i)", now: Int64(i + 1))
        }
        data.addPlaceholderValue(key: "k", value: "v0", now: 500)
        data.addPlaceholderValue(key: "k", value: "new", now: 1_000)

        let values = data.placeholderHistory(forKey: "k").map(\.value)
        #expect(values.count == StorageConstants.maxStoredValuesPerKey)
        #expect(values.contains("v0"))
        #expect(!values.contains("v1"))
        #expect(values.contains("new"))
    }

    @Test func rejectsEmptyKeyOrBlankValue() {
        var data = StorageData()
        let emptyKey = data.addPlaceholderValue(key: "", value: "x", now: 1)
        let blankValue = data.addPlaceholderValue(key: "k", value: " \n", now: 1)
        #expect(!emptyKey)
        #expect(!blankValue)
        #expect(data.placeholderHistory.isEmpty)
    }

    @Test func usageUpdateDeleteAndClear() throws {
        var data = StorageData()
        data.addPlaceholderValue(key: "k", value: "a", now: 1)
        data.addPlaceholderValue(key: "k", value: "b", now: 1)
        data.addPlaceholderValue(key: "j", value: "c", now: 1)

        let bumped = data.updatePlaceholderValueUsage(key: "k", value: "a", now: 9)
        let missing = data.updatePlaceholderValueUsage(key: "k", value: "zzz", now: 9)
        #expect(bumped)
        #expect(!missing)
        #expect(data.placeholderHistory(forKey: "k")[0] == PlaceholderHistoryValue(value: "a", useCount: 2, lastUsed: 9, createdAt: 1))
        #expect(data.placeholderKeys == ["j", "k"])

        try data.updatePlaceholderValue(key: "k", oldValue: "a", newValue: "a2")
        #expect(data.placeholderHistory(forKey: "k").map(\.value) == ["a2", "b"])
        #expect(throws: StorageError.duplicatePlaceholderValue) { try data.updatePlaceholderValue(key: "k", oldValue: "a2", newValue: "b") }
        #expect(throws: StorageError.emptyPlaceholderValue) { try data.updatePlaceholderValue(key: "k", oldValue: "a2", newValue: " ") }
        #expect(throws: StorageError.placeholderKeyNotFound) { try data.updatePlaceholderValue(key: "x", oldValue: "a2", newValue: "z") }
        #expect(throws: StorageError.placeholderValueNotFound) { try data.updatePlaceholderValue(key: "k", oldValue: "nope", newValue: "z") }

        let beforeMissingDelete = data
        let removedMissingValue = data.deletePlaceholderValue(key: "k", value: "nope")
        #expect(!removedMissingValue)
        #expect(data == beforeMissingDelete)

        data.deletePlaceholderValue(key: "k", value: "a2")
        data.deletePlaceholderValue(key: "k", value: "b")
        #expect(data.placeholderHistory["k"] == nil)

        data.clearPlaceholderHistory(forKey: "j")
        #expect(data.placeholderHistory.isEmpty)
        data.addPlaceholderValue(key: "k", value: "a", now: 1)
        data.clearAllPlaceholderHistory()
        #expect(data.placeholderHistory.isEmpty)
    }
}
