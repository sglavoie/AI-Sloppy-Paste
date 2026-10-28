import Foundation

/// Storage data as decoded before migration: metadata may be missing, but a
/// document must contain a snippets array to be recognized as storage data.
public struct LegacyStorageData: Decodable, Sendable, Hashable {
    public var version: Int?
    public var snippets: [LegacySnippet]
    public var tags: [String]
    public var placeholderHistory: PlaceholderHistory?

    public init(
        version: Int?,
        snippets: [LegacySnippet] = [],
        tags: [String] = [],
        placeholderHistory: PlaceholderHistory? = nil
    ) {
        self.version = version
        self.snippets = snippets
        self.tags = tags
        self.placeholderHistory = placeholderHistory
    }

    private enum CodingKeys: String, CodingKey {
        case version, snippets, tags, placeholderHistory
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try? c.decodeIfPresent(Int.self, forKey: .version)
        // Check before decoding fields whose shape may have changed in a newer
        // version, so an unsupported document is never treated as corrupt.
        try StorageMigrations.requireSupportedVersion(in: c, forKey: .version)
        if version == StorageConstants.currentVersion {
            // A file written by this app has a known, complete shape. Decoding
            // it as legacy data would silently discard malformed fields on the
            // next save (for example, a string in place of a tags array).
            let current: StorageData
            do {
                current = try StorageData(from: decoder)
            } catch DecodingError.keyNotFound(let key, let context) {
                // An incomplete startup write still follows the existing
                // quarantine path, which preserves the partial bytes aside.
                throw DecodingError.keyNotFound(key, context)
            } catch let error as DecodingError {
                throw StorageError.invalidCurrentStorageData(Self.fieldPath(in: error))
            }
            snippets = current.snippets.map(LegacySnippet.init)
            tags = current.tags
            placeholderHistory = current.placeholderHistory
            return
        }
        snippets = try c.decode([LegacySnippet].self, forKey: .snippets)
        tags = (try? c.decodeIfPresent([LossyString].self, forKey: .tags))?.compactMap(\.value) ?? []
        placeholderHistory = try c.decodeIfPresent(PlaceholderHistory.self, forKey: .placeholderHistory)
    }

    private static func fieldPath(in error: DecodingError) -> String {
        let path: [any CodingKey]
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            path = context.codingPath
        case .keyNotFound(let key, let context):
            path = context.codingPath + [key]
        @unknown default:
            return "the document"
        }
        let components = path.map { key in
            key.intValue.map { "[\($0)]" } ?? key.stringValue
        }
        return components.isEmpty ? "the document" : components.joined(separator: ".").replacingOccurrences(of: ".[", with: "[")
    }
}

/// Upgrades stored data to `StorageConstants.currentVersion`, one version at a time.
public enum StorageMigrations {
    public struct Result: Sendable, Hashable {
        public var data: StorageData
        public var didMigrate: Bool
    }

    /// Decodes and migrates raw file contents. Throws when the JSON is not a
    /// storage document at all (the caller quarantines the file), or when its
    /// storage version is newer than supported (the caller leaves it untouched).
    public static func migrate(json: Data) throws -> Result {
        try migrate(JSONDecoder().decode(LegacyStorageData.self, from: json))
    }

    public static func migrate(_ legacy: LegacyStorageData) throws -> Result {
        try requireSupportedVersion(legacy.version)
        var data = legacy
        var didMigrate = false
        // Snippets that went through a shape-normalising step; the rest keep
        // their stored tags and only get defaults filled in.
        var normalizedShape = false

        while let version = data.version, version < StorageConstants.currentVersion {
            guard let migration = migrations[version] else { break }
            migration(&data, &normalizedShape)
            data.version = version + 1
            didMigrate = true
        }

        if data.version != StorageConstants.currentVersion {
            data.version = StorageConstants.currentVersion
            didMigrate = true
        }

        let snippets = data.snippets.map { snippet in
            normalizedShape ? snippet.normalized() : snippet.filled(tags: snippet.sourceTags)
        }
        return Result(
            data: StorageData(
                version: StorageConstants.currentVersion,
                snippets: snippets,
                tags: data.tags,
                placeholderHistory: data.placeholderHistory ?? [:]
            ),
            didMigrate: didMigrate
        )
    }

    private typealias Migration = @Sendable (inout LegacyStorageData, inout Bool) -> Void

    static func requireSupportedVersion(_ version: Int?) throws {
        if let version, version < 0 { throw StorageError.invalidStorageVersion }
        if let version, version > StorageConstants.currentVersion {
            throw StorageError.unsupportedStorageVersion(version)
        }
    }

    /// Stored files use an integer; exports use a dotted string such as
    /// "7.0.0". Check both before decoding fields whose shape may have changed.
    /// This check does not opt exports into the stored-file migration steps.
    static func requireSupportedVersion<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>, forKey key: Key
    ) throws {
        guard container.contains(key), try !container.decodeNil(forKey: key) else { return }
        if let version = try? container.decode(Int.self, forKey: key) {
            try requireSupportedVersion(version)
        } else if let version = try? container.decode(String.self, forKey: key) {
            let components = version.split(separator: ".", omittingEmptySubsequences: false)
            guard components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }),
                let major = components.first.flatMap({ Int($0) })
            else { throw StorageError.invalidStorageVersion }
            try requireSupportedVersion(major)
        } else {
            throw StorageError.invalidStorageVersion
        }
    }

    /// Keyed by the version being migrated from. Steps that only backfill a
    /// default (v2 `isArchived`, v5 `description`) are covered by the final fill.
    private static let migrations: [Int: Migration] = [
        1: { data, normalized in
            data.snippets = data.snippets.map { LegacySnippet($0.normalized()) }
            normalized = true
        },
        2: { _, _ in },
        3: { data, _ in
            data.snippets = data.snippets.map { snippet in
                var copy = snippet
                copy.tags = TagNormalization.deduplicateTags(TagNormalization.normalizeTags(snippet.sourceTags))
                copy.category = nil
                return copy
            }
        },
        4: { data, _ in data.placeholderHistory = [:] },
        5: { _, _ in },
        6: { data, normalized in
            data.snippets = data.snippets.map { LegacySnippet($0.normalized()) }
            normalized = true
        },
    ]
}
