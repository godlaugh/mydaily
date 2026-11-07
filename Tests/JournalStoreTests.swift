import CoreData
import XCTest
@testable import ALog

@MainActor
final class JournalStoreTests: XCTestCase {
    private func container(url: URL? = nil, model: NSManagedObjectModel? = nil) throws -> NSPersistentContainer {
        let container: NSPersistentContainer
        if let model { container = NSPersistentContainer(name: "DataModel", managedObjectModel: model) }
        else { container = NSPersistentContainer(name: "DataModel") }
        let description = NSPersistentStoreDescription()
        description.type = url == nil ? NSInMemoryStoreType : NSSQLiteStoreType
        description.url = url
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadingError: Error?
        container.loadPersistentStores { _, error in loadingError = error }
        if let loadingError { throw loadingError }
        return container
    }

    private func close(_ container: NSPersistentContainer) throws {
        container.viewContext.reset()
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    func testAppendUsesOneThreadAndDoesNotChangeOriginal() throws {
        let store = try container(), context = store.viewContext
        let root = try JournalStore.add(content: "最初的想法", file: "original.m4a", duration: 84, transcribed: true, in: context)
        let date = root.createdAt, id = root.id
        let unrelated = try JournalStore.add(content: "另一件事", in: context)
        let reply = try JournalStore.add(content: "三个月之后", parentID: root.objectID, in: context)
        let later = try JournalStore.add(content: "一年之后", file: "later.m4a", duration: 38, parentID: reply.objectID, in: context)
        let groups = JournalGroup.grouped(try context.fetch(MemoEntity.all))
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(JournalGroup.containing(root, in: try context.fetch(MemoEntity.all))?.entries.count, 3)
        XCTAssertEqual(root.thread, reply.thread)
        XCTAssertEqual(root.thread, later.thread)
        XCTAssertNil(unrelated.thread)
        XCTAssertEqual(root.createdAt, date)
        XCTAssertEqual(root.id, id)
        XCTAssertEqual(root.content, "最初的想法")
        XCTAssertEqual(root.file, "original.m4a")
        XCTAssertEqual(root.duration, 84)
        XCTAssertTrue(root.transcribed)
    }

    func testThreadSurvivesStoreReopenAndOrdersByNewestAddition() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("journal.sqlite")
        let firstStore = try container(url: url), context = firstStore.viewContext
        let root = try JournalStore.add(content: "旧事", in: context)
        root.createdAt = Date(timeIntervalSince1970: 100)
        let unrelated = try JournalStore.add(content: "新事", in: context)
        unrelated.createdAt = Date(timeIntervalSince1970: 200)
        let reply = try JournalStore.add(content: "现在的感受", parentID: root.objectID, in: context)
        reply.createdAt = Date(timeIntervalSince1970: 300)
        try context.save()
        try close(firstStore)
        let reopened = try container(url: url)
        let groups = JournalGroup.grouped(try reopened.viewContext.fetch(MemoEntity.all))
        XCTAssertEqual(groups.map(\.entries.count), [2, 1])
        XCTAssertEqual(groups.first?.entries.map(\.content), ["旧事", "现在的感受"])
        XCTAssertEqual(groups.first?.first.createdAt, Date(timeIntervalSince1970: 100))
        try close(reopened)
    }

    func testDeletingOneDatePreservesOtherDatesAndCleansEmptyThread() throws {
        let store = try container(), context = store.viewContext
        let root = try JournalStore.add(content: "第一段", in: context)
        let second = try JournalStore.add(content: "第二段", parentID: root.objectID, in: context)
        let third = try JournalStore.add(content: "第三段", parentID: root.objectID, in: context)
        try JournalStore.delete([root], in: context)
        XCTAssertEqual(try context.count(for: MemoEntity.fetchRequest()), 2)
        XCTAssertEqual(second.thread, third.thread)
        XCTAssertEqual(JournalGroup.grouped(try context.fetch(MemoEntity.all)).count, 1)
        try JournalStore.delete([second, third], in: context)
        XCTAssertEqual(try context.count(for: MemoEntity.fetchRequest()), 0)
        XCTAssertEqual(try context.count(for: JournalThreadEntity.fetchRequest()), 0)
    }

    func testMissingParentAndBlankContentDoNotCreateEntries() throws {
        let store = try container(), context = store.viewContext
        let root = try JournalStore.add(content: "原记录", in: context)
        let id = root.objectID
        try JournalStore.delete([root], in: context)
        XCTAssertThrowsError(try JournalStore.add(content: "不能挂在已删除记录下", parentID: id, in: context))
        XCTAssertThrowsError(try JournalStore.add(content: " \n ", in: context))
        XCTAssertEqual(try context.count(for: MemoEntity.fetchRequest()), 0)
    }

    func testVersionThreeMigratesWithoutRewritingExistingRecordings() throws {
        let modelFolder = try XCTUnwrap(Bundle.main.url(forResource: "DataModel", withExtension: "momd"))
        let oldModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelFolder.appendingPathComponent("MemoDataModel 3.mom")))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("legacy.sqlite")
        let old = try container(url: url, model: oldModel)
        let original = NSEntityDescription.insertNewObject(forEntityName: "MemoEntity", into: old.viewContext)
        original.setValuesForKeys(["id": "legacy-entry", "content": "原始转录", "file": "untouched.m4a",
                                  "createdAt": Date(timeIntervalSince1970: 100), "day": Int32(19700101),
                                  "timezone": "Asia/Shanghai", "duration": 84.0, "transcribed": true, "isHidden": true])
        try old.viewContext.save()
        try close(old)
        let upgraded = try container(url: url)
        let entry = try XCTUnwrap(upgraded.viewContext.fetch(MemoEntity.all).first)
        XCTAssertNil(entry.thread)
        XCTAssertEqual(entry.id, "legacy-entry")
        XCTAssertEqual(entry.content, "原始转录")
        XCTAssertEqual(entry.file, "untouched.m4a")
        XCTAssertEqual(entry.createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(entry.duration, 84)
        XCTAssertTrue(entry.transcribed)
        XCTAssertTrue(entry.isHidden)
        _ = try JournalStore.add(content: "升级后追加", parentID: entry.objectID, in: upgraded.viewContext)
        XCTAssertEqual(JournalGroup.grouped(try upgraded.viewContext.fetch(MemoEntity.all)).first?.entries.count, 2)
        try close(upgraded)
    }
}
