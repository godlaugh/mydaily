import CoreData
import Foundation

/// A thread is created only when a diary receives its first addition.
/// Existing, ungrouped recordings remain individual diaries after migration.
struct JournalGroup: Identifiable {
    let id: String
    let entries: [MemoEntity]

    var first: MemoEntity { entries[0] }
    var latest: MemoEntity { entries[entries.count - 1] }
    var updatedAt: Date { latest.createdAt ?? .distantPast }
    var title: String { first.journalTitle }

    static func grouped(_ entries: [MemoEntity]) -> [JournalGroup] {
        let living = entries.filter { !$0.isDeleted }
        let buckets = Dictionary(grouping: living) { entry in
            entry.thread?.objectID.uriRepresentation().absoluteString
                ?? entry.objectID.uriRepresentation().absoluteString
        }
        return buckets.map { id, entries in
            JournalGroup(id: id, entries: entries.sorted {
                if $0.createdAt == $1.createdAt { return ($0.id ?? "") < ($1.id ?? "") }
                return ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            })
        }.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
            return $0.updatedAt > $1.updatedAt
        }
    }

    static func containing(_ entry: MemoEntity, in entries: [MemoEntity]) -> JournalGroup? {
        grouped(entries).first { $0.entries.contains(entry) }
    }
}
