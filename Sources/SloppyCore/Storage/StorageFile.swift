import Foundation
import Darwin

/// The JSON data file: atomic pretty-printed writes, a `.bak` copy before a
/// replace-import, and quarantine instead of overwrite when it fails to decode.
public struct StorageFile: Sendable, Hashable {
    public var url: URL

    public init(url: URL = StorageFile.defaultURL) {
        self.url = url
    }

    /// `~/Library/Application Support/SloppyPaste/data.json`
    public static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "SloppyPaste", directoryHint: .isDirectory)
            .appending(path: "data.json", directoryHint: .notDirectory)
    }

    public var backupURL: URL { url.appendingPathExtension("bak") }
    public var lockURL: URL { url.appendingPathExtension("lock") }

    /// Bytes and decoded data from the same read. Keep the bytes until a write
    /// so an editor that does not use our lock cannot be silently overwritten.
    public struct Snapshot: Sendable, Hashable {
        public let data: StorageData
        public let bytes: Data?
    }

    /// A sidecar lock survives atomic replacement of data.json. Every app and
    /// CLI read-modify-write operation holds it from read through save.
    public func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    public struct LoadResult: Sendable, Hashable {
        public var data: StorageData
        /// The file was migrated to the current version and saved back.
        public var didMigrate: Bool
        /// Set when the file failed to decode and was moved aside; `data` is then empty.
        public var quarantinedURL: URL?
    }

    /// Reads and migrates in memory without writing, creating, or quarantining files.
    /// Missing files give empty data; malformed files throw and remain untouched.
    public func read() throws -> StorageData {
        try readSnapshot().data
    }

    /// Reads and migrates in memory, preserving malformed files for repair.
    public func readSnapshot() throws -> Snapshot {
        let contents: Data
        do {
            contents = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return Snapshot(data: .empty, bytes: nil)
        }
        return Snapshot(data: try StorageMigrations.migrate(json: contents).data, bytes: contents)
    }

    /// Loads and migrates the file, saving it back if it migrated. A missing
    /// file gives empty data; an undecodable one is renamed to
    /// `data.corrupt-<now>.json` and also gives empty data.
    /// A newer storage version throws without rewriting or quarantining the file.
    public func load(now: Int64) throws -> LoadResult {
        let contents: Data
        do {
            contents = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return LoadResult(data: .empty, didMigrate: false, quarantinedURL: nil)
        }

        let result: StorageMigrations.Result
        do {
            result = try StorageMigrations.migrate(json: contents)
        } catch let error as StorageError {
            // Unsupported versions must block writes, not start an empty store.
            throw error
        } catch {
            // An editor may have repaired or replaced the file while decoding.
            // Never quarantine bytes other than the ones that failed to decode.
            try verifyUnchanged(Snapshot(data: .empty, bytes: contents))
            let quarantined = quarantineURL(now: now)
            try FileManager.default.moveItem(at: url, to: quarantined)
            return LoadResult(data: .empty, didMigrate: false, quarantinedURL: quarantined)
        }

        if result.didMigrate {
            try save(result.data, ifUnchangedFrom: Snapshot(data: result.data, bytes: contents))
        }
        return LoadResult(data: result.data, didMigrate: result.didMigrate, quarantinedURL: nil)
    }

    /// `data.corrupt-<now>.json`, or `data.corrupt-<now>-<n>.json` when an
    /// earlier quarantine already took that name.
    func quarantineURL(now: Int64) -> URL {
        let directory = url.deletingLastPathComponent()
        let stem = "\(url.deletingPathExtension().lastPathComponent).corrupt-\(now)"
        var candidate = directory.appending(path: "\(stem).json")
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(stem)-\(suffix).json")
            suffix += 1
        }
        return candidate
    }

    /// Writes the data atomically, creating the directory if needed.
    public func save(_ data: StorageData) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try StorageCoding.encode(data).write(to: url, options: .atomic)
    }

    /// Fails when another writer changed the file since the data was read.
    /// Cooperative writers also hold `withExclusiveLock` around the operation.
    public func save(_ data: StorageData, ifUnchangedFrom snapshot: Snapshot) throws {
        try verifyUnchanged(snapshot)
        try save(data)
    }

    private func verifyUnchanged(_ snapshot: Snapshot) throws {
        let current: Data?
        do {
            current = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            current = nil
        }
        guard current == snapshot.bytes else { throw StorageError.dataChangedSinceRead }
    }

    /// Copies the current file to `backupURL`, replacing an older backup.
    /// Returns nil when there is no file to back up.
    @discardableResult
    public func writeBackup() throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try Data(contentsOf: url).write(to: backupURL, options: .atomic)
        return backupURL
    }

    /// Applies an import and saves it. A replace-import backs up the file first.
    public func importPayload(
        _ payload: ImportPayload, into current: StorageData, mode: ImportMode,
        ifUnchangedFrom snapshot: Snapshot? = nil
    ) throws -> StorageData {
        if let snapshot { try verifyUnchanged(snapshot) }
        if mode == .replace {
            try writeBackup()
        }
        let next = ImportExport.apply(payload, to: current, mode: mode)
        if let snapshot { try verifyUnchanged(snapshot) }
        try save(next)
        return next
    }

    /// Used to reload after external edits.
    public func modificationDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// Size of the data file in bytes, or 0 if it does not exist.
    public func size() -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}
