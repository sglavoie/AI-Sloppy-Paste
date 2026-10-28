import Foundation
import Observation
import SloppyCore

/// The app's single source of truth for snippet data, backed by the JSON file.
/// Mutations go through `SnippetRepository` and are saved immediately.
@MainActor
@Observable
final class SnippetStore {
    private(set) var data: StorageData = .empty
    /// Set when the last load moved an undecodable file aside.
    private(set) var quarantinedURL: URL?
    /// The last load or save error, for display.
    private(set) var lastError: String?

    @ObservationIgnored let file: StorageFile
    @ObservationIgnored var now: () -> Int64
    @ObservationIgnored private var hasLoadedFile = false
    @ObservationIgnored private var watcher: FileWatcher?
    /// Called when the startup load moved an undecodable file aside.
    @ObservationIgnored var onQuarantine: ((URL) -> Void)?

    init(file: StorageFile = StorageFile(), now: @escaping () -> Int64 = { Date().epochMilliseconds }) {
        self.file = file
        self.now = now
    }

    var snippets: [Snippet] { data.snippets }

    /// Loads the file from disk, migrating and quarantining as needed.
    func load() {
        do {
            let (result, filePresent) = try file.withExclusiveLock {
                let result = try file.load(now: now())
                return (result, FileManager.default.fileExists(atPath: file.url.path))
            }
            data = result.data
            if let quarantined = result.quarantinedURL {
                quarantinedURL = quarantined
                onQuarantine?(quarantined)
            }
            lastError = nil
            hasLoadedFile = filePresent
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reloads as soon as another process (an editor, `sloppyctl`, a sync
    /// tool) changes the file, not only when the picker next opens.
    func startWatching() {
        guard watcher == nil else { return }
        watcher = FileWatcher(url: file.url) { [weak self] in
            // A write notification is sufficient evidence of a change even
            // when an editor or sync tool preserves the modification date.
            _ = try? self?.requireCurrentData()
        }
    }

    /// Refreshes from disk before presenting data. External writers can replace
    /// the file while preserving its modification date, so that date alone
    /// cannot tell us whether the displayed snippets are current.
    func reloadIfChanged() {
        _ = try? requireCurrentData()
    }

    /// Always reads before deriving data that will be written back to disk.
    /// External writers may preserve modification dates, so both presentation
    /// and mutation use the file contents as the source of truth.
    @discardableResult
    func requireCurrentData() throws -> StorageFile.Snapshot {
        do {
            let snapshot = try file.readSnapshot()
            if hasLoadedFile && snapshot.bytes == nil { throw StorageError.dataFileDisappeared }
            data = snapshot.data
            lastError = nil
            hasLoadedFile = snapshot.bytes != nil
            return snapshot
        } catch {
            lastError = error.localizedDescription
            throw ReloadFailure(reason: error.localizedDescription)
        }
    }

    private struct ReloadFailure: LocalizedError, CustomStringConvertible {
        var reason: String
        var errorDescription: String? { description }
        var description: String {
            "Could not reload the data file. No changes were saved. Check the file and try again. \(reason)"
        }
    }

    /// Reloads first, then applies a repository mutation and saves the result.
    @discardableResult
    func mutate<T>(_ body: (inout SnippetRepository, Int64) throws -> T) throws -> T {
        try file.withExclusiveLock {
            let snapshot = try requireCurrentData()
            var repository = SnippetRepository(data: snapshot.data)
            let result = try body(&repository, now())
            try save(repository.data, ifUnchangedFrom: snapshot)
            return result
        }
    }

    /// Bumps useCount and lastUsedAt, and saves the placeholder values to history.
    func recordUse(id: String, placeholderValues: [PlaceholderValueToRecord] = []) throws {
        try mutate { repository, now in
            try repository.recordUse(id: id, placeholderValues: placeholderValues, now: now)
        }
    }

    /// Replaces the data wholesale (imports) and saves it.
    private func save(_ next: StorageData, ifUnchangedFrom snapshot: StorageFile.Snapshot) throws {
        do {
            try file.save(next, ifUnchangedFrom: snapshot)
            data = next
            lastError = nil
            hasLoadedFile = true
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Imports into the current data (reloaded first); a replace backs the
    /// file up to `data.json.bak` before writing.
    func importPayload(_ payload: ImportPayload, mode: ImportMode, expectedCurrent: StorageData? = nil) throws {
        try file.withExclusiveLock {
            let snapshot = try requireCurrentData()
            if let expectedCurrent, data != expectedCurrent {
                let error = ImportConflict()
                lastError = error.localizedDescription
                throw error
            }
            do {
                data = try file.importPayload(payload, into: snapshot.data, mode: mode, ifUnchangedFrom: snapshot)
                lastError = nil
                hasLoadedFile = true
            } catch {
                lastError = error.localizedDescription
                throw error
            }
        }
    }

    private struct ImportConflict: LocalizedError {
        var errorDescription: String? {
            "The snippet data changed while the import dialog was open. No changes were saved. Review the import again."
        }
    }

    func clearQuarantineNotice() {
        quarantinedURL = nil
    }
}
