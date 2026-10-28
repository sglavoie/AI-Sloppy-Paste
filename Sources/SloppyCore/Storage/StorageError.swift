import Foundation

public enum StorageError: Error, Equatable, LocalizedError {
    case unsupportedStorageVersion(Int)
    case invalidStorageVersion
    case dataChangedSinceRead
    case dataFileDisappeared
    case snippetNotFound
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
        case .invalidStorageVersion:
            "The file has an invalid storage version. It has been left unchanged."
        case .dataChangedSinceRead:
            "The data file changed while the operation was running. No changes were saved; try again."
        case .dataFileDisappeared:
            "The data file disappeared after it was loaded. No changes were saved; restore it or restart the app."
        case .snippetNotFound: "Snippet not found"
        case .cannotMergeTagWithItself: "Cannot merge a tag with itself"
        case .invalidTag(let tag, let reason): "Cannot use tag \"\(tag)\": \(reason). No tags were changed."
        case .emptyPlaceholderValue: "New value cannot be empty"
        case .placeholderKeyNotFound: "Placeholder key not found"
        case .placeholderValueNotFound: "Value not found"
        case .duplicatePlaceholderValue: "A value with this name already exists"
        }
    }
}
