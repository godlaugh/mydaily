import CoreData
import Foundation

enum JournalStore {
    @discardableResult
    static func add(content: String, file: String? = nil, duration: Double = 0,
                    transcribed: Bool = false, parentID: NSManagedObjectID? = nil,
                    in context: NSManagedObjectContext) throws -> MemoEntity {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard file != nil || !text.isEmpty else { throw JournalStoreError.emptyEntry }
        let parent: MemoEntity?
        if let parentID {
            guard let entry = try context.existingObject(with: parentID) as? MemoEntity,
                  !entry.isDeleted else { throw JournalStoreError.missingParent }
            parent = entry
        } else {
            parent = nil
        }

        let entry = MemoEntity.newEntity(moc: context)
        entry.content = text
        entry.file = file
        entry.duration = duration.isFinite ? max(0, duration) : 0
        entry.transcribed = transcribed
        var newThread: JournalThreadEntity?
        if let parent {
            if let existing = parent.thread {
                entry.thread = existing
            } else {
                let thread = NSEntityDescription.insertNewObject(forEntityName: "JournalThreadEntity", into: context) as! JournalThreadEntity
                thread.id = UUID().uuidString.lowercased()
                thread.createdAt = parent.createdAt
                parent.thread = thread
                entry.thread = thread
                newThread = thread
            }
        }
        do {
            try context.save()
            return entry
        } catch {
            context.delete(entry)
            if let newThread {
                parent?.thread = nil
                context.delete(newThread)
            }
            throw error
        }
    }

    /// Remove only the chosen entries. Other dates in a thread remain intact.
    /// Audio is removed after the database save has succeeded.
    static func delete(_ entries: [MemoEntity], in context: NSManagedObjectContext) throws {
        let entries = entries.filter { !$0.isDeleted }
        let files = entries.compactMap(\.file)
        let threads = Set(entries.compactMap(\.thread))
        for entry in entries { context.delete(entry) }
        for thread in threads {
            let remaining = (thread.entries as? Set<MemoEntity> ?? []).filter { !$0.isDeleted }
            if remaining.isEmpty { context.delete(thread) }
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        if let current = AudioPlayer.shared.currentFile, files.contains(current) {
            AudioPlayer.shared.stop()
        }
        for file in files { try? FileManager.default.removeItem(at: FileHelper.fullAudioURL(for: file)) }
    }
}
