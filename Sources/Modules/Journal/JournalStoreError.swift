import Foundation

enum JournalStoreError: LocalizedError {
    case emptyEntry
    case missingParent

    var errorDescription: String? {
        JournalText.string(self == .emptyEntry ? "empty_error" : "missing_parent")
    }
}
