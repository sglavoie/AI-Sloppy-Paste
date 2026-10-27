import Foundation

public enum StorageError: Error, Equatable, LocalizedError {
    case unsupportedStorageVersion(Int)
    case snippetNotFound
    case cannotMergeTagWithItself
    case emptyPlaceholderValue
    case placeholderKeyNotFound
    case placeholderValueNotFound
    case duplicatePlaceholderValue

    public var errorDescription: String? {
        switch self {
        case .unsupportedStorageVersion(let version):
            "Storage version \(version) is newer than supported version \(StorageConstants.currentVersion). Update Sloppy Paste to open this file. The file has been left unchanged."
        case .snippetNotFound: "Snippet not found"
        case .cannotMergeTagWithItself: "Cannot merge a tag with itself"
        case .emptyPlaceholderValue: "New value cannot be empty"
        case .placeholderKeyNotFound: "Placeholder key not found"
        case .placeholderValueNotFound: "Value not found"
        case .duplicatePlaceholderValue: "A value with this name already exists"
        }
    }
}
