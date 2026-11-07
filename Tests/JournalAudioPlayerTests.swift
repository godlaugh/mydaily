import AVFoundation
import XCTest
@testable import ALog

@MainActor
final class JournalAudioPlayerTests: XCTestCase {
    private func silentFile() throws -> String {
        let name = "player-test-\(UUID().uuidString).wav"
        let url = FileHelper.fullAudioURL(for: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000))
        buffer.frameLength = 48000
        buffer.floatChannelData?[0].update(repeating: 0, count: 48000)
        let output = try AVAudioFile(forWriting: url, settings: format.settings)
        try output.write(from: buffer)
        return name
    }

    func testPauseResumeAndCloseKeepThenClearTheCorrectPosition() throws {
        let file = try silentFile()
        defer { try? FileManager.default.removeItem(at: FileHelper.fullAudioURL(for: file)) }
        let player = AudioPlayer()
        defer { player.stop() }
        player.toggle(file: file, title: "原记录")
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentFile, file)
        player.seek(to: 1)
        player.pause()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 1, accuracy: 0.05)
        player.toggle(file: file, title: "原记录")
        player.pause()
        XCTAssertEqual(player.currentTime, 1, accuracy: 0.1)
        player.stop()
        XCTAssertNil(player.currentFile)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertFalse(player.isPlaying)
    }

    func testSwitchingRecordingsResetsPositionAndMissingAudioDoesNotRemainSelected() throws {
        let first = try silentFile(), second = try silentFile()
        defer { for file in [first, second] { try? FileManager.default.removeItem(at: FileHelper.fullAudioURL(for: file)) } }
        let player = AudioPlayer()
        defer { player.stop() }
        player.toggle(file: first, title: "第一段")
        player.seek(to: 2)
        player.pause()
        player.toggle(file: second, title: "第二段")
        XCTAssertEqual(player.currentFile, second)
        XCTAssertEqual(player.currentTitle, "第二段")
        XCTAssertLessThan(player.currentTime, 0.1)
        player.play(file: "missing-\(UUID().uuidString).wav")
        XCTAssertNil(player.currentFile)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.errorMessage)
    }
}
