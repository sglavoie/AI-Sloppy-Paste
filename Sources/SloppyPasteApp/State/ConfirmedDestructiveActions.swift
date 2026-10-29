import Foundation
import SloppyCore

enum DestructiveActionConflict: LocalizedError, Equatable {
    case snippetChanged
    case tagMembershipChanged
    case historyChanged
    case historyValueChanged

    var errorDescription: String? {
        switch self {
        case .snippetChanged:
            "This snippet changed while the confirmation was open. Review it and try again."
        case .tagMembershipChanged:
            "The snippets carrying this tag changed while the confirmation was open. Review the tag and try again."
        case .historyChanged:
            "This placeholder history changed while the confirmation was open. Review it and try again."
        case .historyValueChanged:
            "This placeholder value changed while the confirmation was open. Review it and try again."
        }
    }
}

/// Compare the confirmed scope with freshly loaded data inside the store's
/// read-modify-write lock, before applying a destructive change.
@MainActor
struct ConfirmedDestructiveActions {
    let store: SnippetStore

    static func taggedSnippetIDs(in data: StorageData, tag: String) -> Set<String> {
        let normalized = TagNormalization.normalizeTag(tag)
        return Set(data.snippets.filter { snippet in
            snippet.tags.contains { TagNormalization.normalizeTag($0) == normalized }
        }.map(\.id))
    }

    func deleteTag(_ tag: String, expectedSnippetIDs: Set<String>) throws {
        try store.mutate { repository, now in
            guard Self.taggedSnippetIDs(in: repository.data, tag: tag) == expectedSnippetIDs else {
                throw DestructiveActionConflict.tagMembershipChanged
            }
            try repository.deleteTag(tag, now: now)
        }
    }

    @discardableResult
    func clearHistory(key: String, expectedValues: [PlaceholderHistoryValue]) throws -> Int {
        try store.mutate { repository, _ in
            guard let current = repository.data.placeholderHistory[key] else {
                throw StorageError.placeholderKeyNotFound
            }
            guard current == expectedValues else { throw DestructiveActionConflict.historyChanged }
            repository.data.clearPlaceholderHistory(forKey: key)
            return current.count
        }
    }

    func deleteHistoryValue(key: String, expectedValue: PlaceholderHistoryValue) throws {
        try store.mutate { repository, _ in
            guard let current = repository.data.placeholderHistory[key]?.first(where: { $0.value == expectedValue.value }) else {
                throw StorageError.placeholderValueNotFound
            }
            guard current == expectedValue else { throw DestructiveActionConflict.historyValueChanged }
            guard repository.data.deletePlaceholderValue(key: key, value: expectedValue.value) else {
                throw StorageError.placeholderValueNotFound
            }
        }
    }
}
