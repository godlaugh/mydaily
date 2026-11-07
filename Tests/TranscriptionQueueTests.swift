import CoreData
import XCTest
@testable import ALog

@MainActor
final class TranscriptionQueueTests: XCTestCase {
    func testQueuedLocalJobKeepsProviderLanguageAndVariantAfterSettingsChange() async throws {
        let fixture = try QueueMemoFixture()
        let settings = QueueSettingsBox(provider: .senseVoice, language: .en)
        settings.value.localModel = .senseVoiceSmallFP32
        let probe = QueueExecutionProbe()
        let firstStarted = expectation(description: "First local job starts")
        let secondStarted = expectation(description: "Queued local job starts")
        probe.onStart = { call in
            if call.filename == "first.m4a" { firstStarted.fulfill() }
            if call.filename == "second.m4a" { secondStarted.fulfill() }
        }
        let queue = makeQueue(settings: settings, probe: probe)
        let firstFinished = expectation(description: "First local job finishes")
        let secondFinished = expectation(description: "Queued local job finishes")
        queue.transcribe(fixture.memo(filename: "first.m4a")) { result in
            XCTAssertEqual(try? result.get(), "first.m4a")
            firstFinished.fulfill()
        }
        queue.transcribe(fixture.memo(filename: "second.m4a")) { result in
            XCTAssertEqual(try? result.get(), "second.m4a")
            secondFinished.fulfill()
        }

        // Change settings before either queued task executes. No Config/UserDefaults
        // are touched, and the injected executor never opens audio or uses a network.
        settings.value = .init(provider: .openai, language: .ja, usesAppServer: false)
        await fulfillment(of: [firstStarted], timeout: 2)
        XCTAssertEqual(probe.calls.count, 1)
        probe.finish("first.m4a")
        await fulfillment(of: [secondStarted], timeout: 2)
        XCTAssertEqual(probe.calls.map(\.provider), [.senseVoice, .senseVoice])
        XCTAssertEqual(probe.calls.map(\.language), [.en, .en])
        XCTAssertEqual(probe.calls.map(\.localModel), [.senseVoiceSmallFP32, .senseVoiceSmallFP32])
        probe.finish("second.m4a")
        await fulfillment(of: [firstFinished, secondFinished], timeout: 2)
    }

    func testLocalJobWaitsForCloudJobsAndBlocksLaterCloudJobs() async throws {
        let fixture = try QueueMemoFixture()
        let settings = QueueSettingsBox(provider: .openai, language: .en)
        let probe = QueueExecutionProbe()
        let firstCloudStarted = expectation(description: "First cloud job starts")
        let secondCloudStarted = expectation(description: "Second cloud job starts")
        let localStarted = expectation(description: "Local job starts after both cloud jobs")
        let laterCloudStarted = expectation(description: "Later cloud job starts after local job")
        probe.onStart = { call in
            switch call.filename {
            case "cloud-a.m4a": firstCloudStarted.fulfill()
            case "cloud-b.m4a": secondCloudStarted.fulfill()
            case "local.m4a": localStarted.fulfill()
            case "cloud-after.m4a": laterCloudStarted.fulfill()
            default: XCTFail("Unexpected queued job")
            }
        }
        let queue = makeQueue(settings: settings, probe: probe)
        let firstCloudFinished = expectation(description: "First cloud job finishes")
        let secondCloudFinished = expectation(description: "Second cloud job finishes")
        let localFinished = expectation(description: "Local job finishes")
        let laterCloudFinished = expectation(description: "Later cloud job finishes")
        queue.transcribe(fixture.memo(filename: "cloud-a.m4a")) { _ in firstCloudFinished.fulfill() }
        queue.transcribe(fixture.memo(filename: "cloud-b.m4a")) { _ in secondCloudFinished.fulfill() }
        settings.value = .init(provider: .senseVoice, language: .zh_hans, usesAppServer: false)
        queue.transcribe(fixture.memo(filename: "local.m4a")) { _ in localFinished.fulfill() }
        settings.value = .init(provider: .openai, language: .en, usesAppServer: false)
        queue.transcribe(fixture.memo(filename: "cloud-after.m4a")) { _ in laterCloudFinished.fulfill() }

        await fulfillment(of: [firstCloudStarted, secondCloudStarted], timeout: 2)
        XCTAssertEqual(Set(probe.calls.map(\.filename)), ["cloud-a.m4a", "cloud-b.m4a"])
        probe.finish("cloud-a.m4a")
        await fulfillment(of: [firstCloudFinished], timeout: 2)
        XCTAssertEqual(probe.calls.count, 2, "One remaining cloud job must still block the local job.")
        probe.finish("cloud-b.m4a")
        await fulfillment(of: [localStarted], timeout: 2)
        XCTAssertEqual(probe.calls.count, 3)
        XCTAssertEqual(probe.calls.last?.filename, "local.m4a")
        probe.finish("local.m4a")
        await fulfillment(of: [laterCloudStarted], timeout: 2)
        XCTAssertEqual(probe.calls.last?.filename, "cloud-after.m4a")
        XCTAssertFalse(probe.localJobOverlappedAnotherJob)
        probe.finish("cloud-after.m4a")
        await fulfillment(of: [secondCloudFinished, localFinished, laterCloudFinished], timeout: 2)
    }

    func testDeletedQueuedMemoIsSkippedAndFollowingJobStillRuns() async throws {
        let fixture = try QueueMemoFixture()
        let settings = QueueSettingsBox(provider: .senseVoice, language: .auto)
        let probe = QueueExecutionProbe()
        let firstStarted = expectation(description: "First job starts")
        let followingStarted = expectation(description: "Following job starts")
        probe.onStart = { call in
            if call.filename == "first.m4a" { firstStarted.fulfill() }
            if call.filename == "following.m4a" { followingStarted.fulfill() }
        }
        let queue = makeQueue(settings: settings, probe: probe)
        let firstFinished = expectation(description: "First job finishes")
        let deletedFinished = expectation(description: "Deleted job is cancelled")
        let followingFinished = expectation(description: "Following job finishes")
        let deletedMemo = fixture.memo(filename: "deleted.m4a")
        queue.transcribe(fixture.memo(filename: "first.m4a")) { _ in firstFinished.fulfill() }
        queue.transcribe(deletedMemo) { result in
            if case .failure(let error) = result {
                XCTAssertTrue(error is CancellationError)
            } else {
                XCTFail("A deleted memo must not produce a transcription.")
            }
            deletedFinished.fulfill()
        }
        queue.transcribe(fixture.memo(filename: "following.m4a")) { _ in followingFinished.fulfill() }

        await fulfillment(of: [firstStarted], timeout: 2)
        fixture.context.delete(deletedMemo)
        fixture.context.processPendingChanges()
        probe.finish("first.m4a")
        await fulfillment(of: [deletedFinished, followingStarted], timeout: 2)
        XCTAssertEqual(probe.calls.map(\.filename), ["first.m4a", "following.m4a"])
        probe.finish("following.m4a")
        await fulfillment(of: [firstFinished, followingFinished], timeout: 2)
    }

    private func makeQueue(settings: QueueSettingsBox, probe: QueueExecutionProbe) -> Transcription {
        Transcription(queueSettings: { settings.value }, queueExecution: { url, provider, language, localModel in
            await probe.execute(filename: url.lastPathComponent, provider: provider, language: language, localModel: localModel)
        })
    }
}

@MainActor
private final class QueueSettingsBox {
    var value: Transcription.QueueSettings

    init(provider: TranscriptionProvider, language: TranscriptionLang) {
        value = .init(provider: provider, language: language, usesAppServer: false)
    }
}

@MainActor
private final class QueueExecutionProbe {
    struct Call {
        let filename: String
        let provider: TranscriptionProvider
        let language: TranscriptionLang
        let localModel: LocalTranscriptionModel
    }
    private(set) var calls: [Call] = []
    private(set) var localJobOverlappedAnotherJob = false
    var onStart: ((Call) -> Void)?
    private var active: [String: TranscriptionProvider] = [:]
    private var continuations: [String: CheckedContinuation<String, Never>] = [:]

    func execute(filename: String, provider: TranscriptionProvider, language: TranscriptionLang,
                 localModel: LocalTranscriptionModel) async -> String {
        if (provider == .senseVoice && !active.isEmpty) || active.values.contains(.senseVoice) {
            localJobOverlappedAnotherJob = true
        }
        let call = Call(filename: filename, provider: provider, language: language, localModel: localModel)
        calls.append(call)
        active[filename] = provider
        defer { active[filename] = nil }
        return await withCheckedContinuation { continuation in
            continuations[filename] = continuation
            onStart?(call)
        }
    }

    func finish(_ filename: String) {
        guard let continuation = continuations.removeValue(forKey: filename) else {
            XCTFail("Job \(filename) did not start")
            return
        }
        continuation.resume(returning: filename)
    }
}

@MainActor
private final class QueueMemoFixture {
    let context: NSManagedObjectContext
    private let entity: NSEntityDescription

    init() throws {
        entity = NSEntityDescription()
        entity.name = "MemoEntity"
        entity.managedObjectClassName = NSStringFromClass(MemoEntity.self)
        let file = NSAttributeDescription()
        file.name = "file"
        file.attributeType = .stringAttributeType
        file.isOptional = true
        entity.properties = [file]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
    }

    func memo(filename: String) -> MemoEntity {
        let memo = MemoEntity(entity: entity, insertInto: context)
        memo.file = filename
        // Never save: these fixtures must not notify the app's global timeline
        // observers or cause production transcription work to be enqueued.
        return memo
    }
}
