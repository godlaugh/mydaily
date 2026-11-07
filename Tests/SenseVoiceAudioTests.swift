import AVFoundation
import XCTest
@testable import ALog

final class SenseVoiceAudioTests: XCTestCase {
    func testStereoPCMResamplesAndKeepsLongRecordingTail() throws {
        let url = temporaryURL(extension: "caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let inputRate = 44_100.0
        let inputFrames = Int(inputRate * 65.137)
        try writeAudio(to: url, sampleRate: inputRate, channels: 2, frames: inputFrames) { frame, channel in
            let amplitude = channel == 0 ? 0.25 : 0.75
            return Float(sin(Double(frame) * 2 * .pi * 440 / inputRate) * amplitude)
        }

        let chunks = try readChunks(url)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].count, SenseVoiceAudioReader.maximumChunkFrames)
        XCTAssertEqual(chunks[1].count, SenseVoiceAudioReader.maximumChunkFrames)
        let output = chunks.flatMap { $0 }
        let expectedFrames = Double(inputFrames) * 16_000 / inputRate
        XCTAssertEqual(Double(output.count), expectedFrames, accuracy: 2)
        XCTAssertFalse(chunks[2].isEmpty, "The short final chunk must not be discarded.")
        let center = output[1_000..<16_000]
        let rms = sqrt(center.reduce(0.0) { $0 + Double($1 * $1) } / Double(center.count))
        XCTAssertEqual(rms, 0.5 / sqrt(2), accuracy: 0.015, "Both stereo channels should contribute to mono.")
    }

    func testAACAtRecorderSampleRateConvertsTo16k() throws {
        let url = temporaryURL(extension: "m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeAudio(to: url, sampleRate: 24_000, channels: 1, frames: 24_000 * 3 + 1_234, aac: true) { frame, _ in
            Float(sin(Double(frame) * 2 * .pi * 220 / 24_000) * 0.4)
        }
        let decoded = try AVAudioFile(forReading: url)
        let expectedFrames = Double(decoded.length) * 16_000 / decoded.processingFormat.sampleRate
        let samples = try readChunks(url).flatMap { $0 }
        XCTAssertEqual(Double(samples.count), expectedFrames, accuracy: 2)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
        XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.2)
    }

    func testPauseBoundaryKeepsEverySampleExactlyOnce() throws {
        let url = temporaryURL(extension: "caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let quietStart = 28 * 16_000
        let quietEnd = quietStart + 6_400
        let frames = 31 * 16_000
        try writeAudio(to: url, sampleRate: 16_000, channels: 1, frames: frames) { frame, _ in
            (quietStart..<quietEnd).contains(frame) ? 0 : 0.25
        }
        let chunks = try readChunks(url)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue((quietStart..<quietEnd).contains(chunks[0].count))
        XCTAssertTrue(chunks.allSatisfy { $0.count <= SenseVoiceAudioReader.maximumChunkFrames })
        let output = chunks.flatMap { $0 }
        XCTAssertEqual(output.count, frames)
        XCTAssertTrue(output[..<quietStart].allSatisfy { $0 == 0.25 })
        XCTAssertTrue(output[quietStart..<quietEnd].allSatisfy { $0 == 0 })
        XCTAssertTrue(output[quietEnd...].allSatisfy { $0 == 0.25 })
    }

    func testSingleSampleTailIsNotLost() throws {
        let url = temporaryURL(extension: "caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = SenseVoiceAudioReader.maximumChunkFrames + 1
        try writeAudio(to: url, sampleRate: 16_000, channels: 1, frames: frames) { _, _ in 0.25 }
        let chunks = try readChunks(url)
        XCTAssertEqual(chunks.map { $0.count }, [SenseVoiceAudioReader.maximumChunkFrames, 1])
        XCTAssertEqual(chunks.last, [0.25])
    }

    func testMissingModelThrowsBeforeNativeInitialization() async {
        let missing = temporaryURL(extension: "onnx")
        do {
            try await SenseVoiceTranscriber.shared.prepare(modelURL: missing, tokensURL: missing)
            XCTFail("Missing models must throw an error.")
        } catch SenseVoiceError.missingModelFile {
            // Expected: a recoverable error rather than the upstream Swift wrapper's fatalError.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelledTranscriptionDoesNotOpenFilesOrInitializeModel() async {
        let missing = temporaryURL(extension: "onnx")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SenseVoiceTranscriber.shared.transcribe(
                voiceURL: missing, modelURL: missing, tokensURL: missing, language: "auto"
            )
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled transcription must throw.")
        } catch is CancellationError {
            // Expected before touching the missing files.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testModelControlTagsAreRemovedWithoutChangingWords() {
        let raw = " <|zh|><|NEUTRAL|><|Speech|><|withitn|>今天去了公园。 <|en|>Hello! "
        XCTAssertEqual(SenseVoiceTranscriber.cleanTranscript(raw), "今天去了公园。 Hello!")
        XCTAssertEqual(SenseVoiceTranscriber.cleanTranscript("<|nospeech|><|BGM|>"), "")
    }

    /// Opt-in integration test. Supply official model/sample paths in the test runner environment.
    func testOfficialModelTranscribesProvidedSample() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let model = environment["ALOG_SENSEVOICE_MODEL_PATH"],
              let tokens = environment["ALOG_SENSEVOICE_TOKENS_PATH"],
              let audio = environment["ALOG_SENSEVOICE_AUDIO_PATH"] else {
            throw XCTSkip("Set ALOG_SENSEVOICE_MODEL_PATH, ALOG_SENSEVOICE_TOKENS_PATH, and ALOG_SENSEVOICE_AUDIO_PATH for the local model smoke test.")
        }
        do {
            try await SenseVoiceTranscriber.shared.prepare(
                modelURL: URL(fileURLWithPath: model), tokensURL: URL(fileURLWithPath: tokens)
            )
            let result = try await SenseVoiceTranscriber.shared.transcribe(
                voiceURL: URL(fileURLWithPath: audio), modelURL: URL(fileURLWithPath: model),
                tokensURL: URL(fileURLWithPath: tokens), language: "auto"
            )
            XCTAssertFalse(result.isEmpty)
            XCTAssertFalse(result.contains("<|"))
            if let expected = environment["ALOG_SENSEVOICE_EXPECTED_TEXT"] {
                XCTAssertTrue(result.contains(expected), "Expected transcript fragment was not found.")
            }
            let tinyAudio = temporaryURL(extension: "caf")
            defer { try? FileManager.default.removeItem(at: tinyAudio) }
            try writeAudio(to: tinyAudio, sampleRate: 16_000, channels: 1, frames: 1) { _, _ in 0.1 }
            // A one-sample tail has to be padded before native feature extraction; it must not assert.
            _ = try await SenseVoiceTranscriber.shared.transcribe(
                voiceURL: tinyAudio, modelURL: URL(fileURLWithPath: model),
                tokensURL: URL(fileURLWithPath: tokens), language: "auto"
            )
            await SenseVoiceTranscriber.shared.unload()
        } catch {
            await SenseVoiceTranscriber.shared.unload()
            throw error
        }
    }

    private func temporaryURL(extension suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
    }

    private func readChunks(_ url: URL) throws -> [[Float]] {
        let reader = try SenseVoiceAudioReader(url: url)
        var chunks: [[Float]] = []
        while let chunk = try reader.nextChunk() { chunks.append(chunk) }
        return chunks
    }

    private func writeAudio(
        to url: URL, sampleRate: Double, channels: AVAudioChannelCount, frames: Int,
        aac: Bool = false, sample: (Int, Int) -> Float
    ) throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false
        ))
        let settings: [String: Any] = aac ? [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 64_000
        ] : [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_192))
        let data = try XCTUnwrap(buffer.floatChannelData)
        for start in stride(from: 0, to: frames, by: Int(buffer.frameCapacity)) {
            buffer.frameLength = AVAudioFrameCount(min(Int(buffer.frameCapacity), frames - start))
            for channel in 0..<Int(channels) {
                for offset in 0..<Int(buffer.frameLength) {
                    data[channel][offset] = sample(start + offset, channel)
                }
            }
            try file.write(from: buffer)
        }
    }
}
