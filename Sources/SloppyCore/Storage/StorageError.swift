import Foundation

public enum StorageError: Error, Equatable, LocalizedError {
    case unsupportedStorageVersion(Int)
    case unsupportedExportVersion(String)
    case invalidStorageVersion
    case invalidCurrentStorageData(String)
    case duplicateStoredSnippetID(String)
    case dataChangedSinceRead
    case concurrentWriteNeedsRecovery(URL)
    case dataFileDisappeared
    case snippetNotFound
    case tagNotFound
    case cannotMergeTagWithItself
    case invalidTag(tag: String, reason: String)
    case emptyPlaceholderValue
    case placeholderKeyNotFound
    case placeholderValueNotFound
    case duplicatePlaceholderValue

    public var errorDescription: String? {
        switch self {
        case .unsupportedStorageVersion(let version):
            "Storage version \(version) is newer than supported version \(StorageConstants.currentVersion). Update Sloppy Paste to open this file. The file has been left unchanged."
        case .unsupportedExportVersion(let version):
            "Export version \(version) is newer than supported version \(StorageConstants.currentVersion).0.0. Update Sloppy Paste to import this file. The file has been left unchanged."
        case .invalidStorageVersion:
            "The file has an invalid storage version. It has been left unchanged."
        case .invalidCurrentStorageData(let field):
            "The current-version data file has an invalid or missing field at \(field). It has been left unchanged. Repair the file and try again."
        case .duplicateStoredSnippetID(let id):
            "The data file contains multiple snippets with ID \"\(id)\". It has been left unchanged. Repair the duplicate ID and try again."
        case .dataChangedSinceRead:
            "The data file changed while the operation was running. No changes were saved; try again."
        case .concurrentWriteNeedsRecovery(let url):
            "The data file changed during a save and could not be restored automatically. A displaced version is preserved at \(url.path). Review both files before editing again."
        case .dataFileDisappeared:
            "The data file disappeared after it was loaded. No changes were saved; restore it or restart the app."
        case .snippetNotFound: "Snippet not found"
        case .tagNotFound: "Tag not found"
        case .cannotMergeTagWithItself: "Cannot merge a tag with itself"
        case .invalidTag(let tag, let reason): "Cannot use tag \"\(tag)\": \(reason). No tags were changed."
        case .emptyPlaceholderValue: "New value cannot be empty"
        case .placeholderKeyNotFound: "Placeholder key not found"
        case .placeholderValueNotFound: "Value not found"
        case .duplicatePlaceholderValue: "A value with this name already exists"
        }
    }
}
