import Foundation

/// An import file as decoded leniently: snippets may be legacy-shaped and
/// only `snippets` and `placeholderHistory` are imported. Newer versions are rejected.
public struct ImportPayload: Decodable, Sendable, Hashable {
    public var snippets: [LegacySnippet]
    public var placeholderHistory: PlaceholderHistory?

    public init(snippets: [LegacySnippet], placeholderHistory: PlaceholderHistory? = nil) {
        self.snippets = snippets
        self.placeholderHistory = placeholderHistory
    }

    public init(_ export: ExportData) {
        self.init(snippets: export.snippets.map(LegacySnippet.init), placeholderHistory: export.placeholderHistory)
    }

    private enum CodingKeys: String, CodingKey {
        case version, snippets, placeholderHistory
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try StorageMigrations.requireSupportedVersion(in: c, forKey: .version)
        let majorVersion = (try? c.decode(Int.self, forKey: .version))
            ?? (try? c.decode(String.self, forKey: .version)).flatMap { Int($0.split(separator: ".")[0]) }
        if majorVersion == StorageConstants.currentVersion {
            // Keep missing fields compatible with older exports, but never
            // silently replace malformed current fields with legacy defaults.
            _ = try c.decode([CurrentImportSnippetShape].self, forKey: .snippets)
        }
        snippets = try c.decode([LegacySnippet].self, forKey: .snippets)
        placeholderHistory = try c.decodeIfPresent(PlaceholderHistory.self, forKey: .placeholderHistory)
        try ImportExport.validate(self)
    }
}

public enum ImportValidationError: Error, Sendable, Equatable, LocalizedError {
    case duplicateSnippetID(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateSnippetID(let id):
            "The import contains more than one snippet with ID \"\(id)\". No snippets were imported."
        }
    }
}

/// Checks the type of every present current-version snippet field. Legacy
/// files still use `LegacySnippet`'s permissive decoding and backfilling.
private struct CurrentImportSnippetShape: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, title, content, description, tags, category, createdAt, updatedAt
        case lastUsedAt, useCount, isFavorite, isArchived, isPinned
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _ = try c.decode(String.self, forKey: .id)
        _ = try c.decode(String.self, forKey: .title)
        _ = try c.decode(String.self, forKey: .content)
        try checkIfPresent(String.self, forKey: .description, in: c)
        try checkIfPresent([String].self, forKey: .tags, in: c)
        _ = try c.decodeIfPresent(String.self, forKey: .category)
        try checkIfPresent(Int64.self, forKey: .createdAt, in: c)
        try checkIfPresent(Int64.self, forKey: .updatedAt, in: c)
        _ = try c.decodeIfPresent(Int64.self, forKey: .lastUsedAt)
        try checkIfPresent(Int.self, forKey: .useCount, in: c)
        try checkIfPresent(Bool.self, forKey: .isFavorite, in: c)
        try checkIfPresent(Bool.self, forKey: .isArchived, in: c)
        try checkIfPresent(Bool.self, forKey: .isPinned, in: c)
    }

    private func checkIfPresent<T: Decodable>(
        _ type: T.Type, forKey key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>
    ) throws {
        if container.contains(key) { _ = try container.decode(type, forKey: key) }
    }
}

public enum ImportMode: String, Sendable, CaseIterable {
    /// Adds snippets whose id is not already stored.
    case merge
    /// Replaces all data with the import.
    case replace
}

public enum ImportExport {
    public static func validate(_ payload: ImportPayload) throws {
        var ids = Set<String>()
        for snippet in payload.snippets where !ids.insert(snippet.id).inserted {
            throw ImportValidationError.duplicateSnippetID(snippet.id)
        }
    }

    public static func makeExport(_ data: StorageData, now: Int64) -> ExportData {
        ExportData(
            version: "\(StorageConstants.currentVersion).0.0",
            exportedAt: now,
            snippets: data.snippets,
            tags: data.tags,
            placeholderHistory: data.placeholderHistory
        )
    }

    public static func encodeExport(_ export: ExportData) throws -> Data {
        try StorageCoding.encode(export)
    }

    public static func decodeImport(_ json: Data) throws -> ImportPayload {
        try JSONDecoder().decode(ImportPayload.self, from: json)
    }

    public static func apply(_ payload: ImportPayload, to current: StorageData, mode: ImportMode) throws -> StorageData {
        switch mode {
        case .merge: try merge(payload, into: current)
        case .replace: try replace(with: payload)
        }
    }

    /// Adds imported snippets whose id is not already stored (so importing the
    /// same file twice adds nothing) and merges placeholder history.
    public static func merge(_ payload: ImportPayload, into current: StorageData) throws -> StorageData {
        try validate(payload)
        var ids = Set(current.snippets.map(\.id))
        let newSnippets = payload.snippets
            .filter { ids.insert($0.id).inserted }
            .map { $0.normalized() }

        var data = current
        data.snippets += newSnippets
        if let imported = payload.placeholderHistory {
            data.placeholderHistory = PlaceholderHistoryMerge.merge(current.placeholderHistory, imported)
        }
        return data
    }

    /// Replaces everything with the import; the stored `tags` list is reset.
    /// Rejects duplicate IDs and uses the same history limits as merge.
    public static func replace(with payload: ImportPayload) throws -> StorageData {
        try merge(payload, into: .empty)
    }
}

/// What an import will do, for the confirmation and the result message.
public struct ImportSummary: Sendable, Hashable {
    public var mode: ImportMode
    /// Snippets in the file.
    public var fileCount: Int
    /// Snippets that end up added (merge) or stored (replace).
    public var importedCount: Int
    /// Snippets currently stored.
    public var currentCount: Int

    public init(_ payload: ImportPayload, current: StorageData, mode: ImportMode) throws {
        self.mode = mode
        fileCount = payload.snippets.count
        currentCount = current.snippets.count
        importedCount = try ImportExport.apply(payload, to: current, mode: mode).snippets.count
            - (mode == .merge ? current.snippets.count : 0)
    }

    /// The success message, e.g. "Imported 3 snippets" or "Added 2 new snippets (1 already present)".
    public var resultMessage: String {
        switch mode {
        case .replace:
            return "Imported \(Self.snippets(importedCount))"
        case .merge:
            let skipped = fileCount - importedCount
            let added = "Added \(importedCount) new \(importedCount == 1 ? "snippet" : "snippets")"
            return skipped == 0 ? added : "\(added) (\(skipped) already present)"
        }
    }

    public static func snippets(_ count: Int) -> String {
        "\(count) \(count == 1 ? "snippet" : "snippets")"
    }
}

extension ImportExport {
    /// `ai-sloppy-paste-2026-01-05T09-30-00-000Z.json`, the extension's ISO
    /// timestamp with `:` and `.` replaced so it is a safe file name.
    public static func exportFileName(now: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let timestamp = formatter.string(from: Date(epochMilliseconds: now))
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "ai-sloppy-paste-\(timestamp).json"
    }
}

/// Shared JSON encoding: pretty-printed with sorted keys so files diff cleanly.
public enum StorageCoding {
    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
