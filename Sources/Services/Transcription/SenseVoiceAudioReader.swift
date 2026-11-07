import AVFoundation

/// Decodes AAC/PCM incrementally, keeping at most one 30-second inference chunk in memory.
/// This is offline segmentation, not a streaming speech recognizer or a VAD model.
final class SenseVoiceAudioReader {
    static let sampleRate = 16_000
    static let maximumChunkFrames = sampleRate * 30

    private let converter: AVAudioConverter
    private let input: ConversionInput
    private let outputBuffer: AVAudioPCMBuffer
    private var pending: [Float] = []
    private var reachedEnd = false

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let inputFormat = file.processingFormat
        guard inputFormat.sampleRate.isFinite, inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(Self.sampleRate),
                channels: 1,
                interleaved: false
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 8_192),
              let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(Self.sampleRate)
              ) else {
            throw SenseVoiceError.invalidAudioFormat
        }
        self.converter = converter
        input = ConversionInput(file: file, buffer: inputBuffer)
        self.outputBuffer = outputBuffer
        converter.downmix = true
        pending.reserveCapacity(Self.maximumChunkFrames)
    }

    /// Every converted sample is returned exactly once; a final short chunk is retained.
    func nextChunk() throws -> [Float]? {
        try Task.checkCancellation()
        while pending.count < Self.maximumChunkFrames && !reachedEnd {
            try Task.checkCancellation()
            try readConvertedFrames(maximum: Self.maximumChunkFrames - pending.count)
        }
        guard !pending.isEmpty else { return nil }

        let end = reachedEnd ? pending.count : preferredBoundary(in: pending)
        let chunk = Array(pending[..<end])
        pending.removeFirst(end)
        return chunk
    }

    private func readConvertedFrames(maximum: Int) throws {
        outputBuffer.frameLength = 0
        // The converter retains its resampling state across all reads and chunk boundaries.
        // A temporary smaller output buffer is only needed when a previous quiet split left a tail.
        let output: AVAudioPCMBuffer
        if maximum < Int(outputBuffer.frameCapacity) {
            guard let smaller = AVAudioPCMBuffer(
                pcmFormat: outputBuffer.format, frameCapacity: AVAudioFrameCount(maximum)
            ) else { throw SenseVoiceError.audioConversionFailed }
            output = smaller
        } else {
            output = outputBuffer
        }

        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { [input] count, inputStatus in
            input.read(count: count, status: inputStatus)
        }
        if let readError = input.error { throw readError }
        if let conversionError { throw conversionError }
        guard status != .error else { throw SenseVoiceError.audioConversionFailed }

        if output.frameLength > 0 {
            guard let channel = output.floatChannelData?[0] else { throw SenseVoiceError.invalidAudioFormat }
            for index in 0..<Int(output.frameLength) {
                let sample = channel[index]
                pending.append(sample.isFinite ? min(1, max(-1, sample)) : 0)
            }
        }
        if status == .endOfStream {
            reachedEnd = true
        } else if output.frameLength == 0 {
            // The input block is synchronous and never reports noDataNow, so no progress is an error.
            throw SenseVoiceError.audioConversionFailed
        }
    }

    private func preferredBoundary(in samples: [Float]) -> Int {
        // Prefer the last >=120 ms quiet interval in the final five seconds, avoiding a hard
        // cut inside a word when a pause is available. Continuous speech still has a 30 s cap.
        let window = Self.sampleRate / 50
        let minimumQuietWindows = 6
        let searchStart = max(0, samples.count - Self.sampleRate * 5)
        var quietStart: Int?
        var quietWindows = 0
        var boundary: Int?

        for start in stride(from: searchStart, through: samples.count - window, by: window) {
            var energy: Float = 0
            for sample in samples[start..<(start + window)] {
                energy += sample * sample
            }
            if energy / Float(window) < 0.0001 {
                if quietStart == nil { quietStart = start }
                quietWindows += 1
                if quietWindows >= minimumQuietWindows, let quietStart {
                    boundary = quietStart + (start + window - quietStart) / 2
                }
            } else {
                quietStart = nil
                quietWindows = 0
            }
        }
        return boundary ?? samples.count
    }

    /// AVAudioConverter's input block is annotated Sendable, but convert(to:error:withInputFrom:)
    /// invokes it synchronously. This bridge is private to one reader on the transcriber actor;
    /// neither its file nor buffer is accessed until convert returns, or from another thread.
    private final class ConversionInput: @unchecked Sendable {
        let file: AVAudioFile
        let buffer: AVAudioPCMBuffer
        private(set) var error: Error?

        init(file: AVAudioFile, buffer: AVAudioPCMBuffer) {
            self.file = file
            self.buffer = buffer
        }

        func read(count: AVAudioPacketCount, status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            do {
                try Task.checkCancellation()
                // Reading AVAudioFile again at EOF can throw a nil NSError rather than return
                // zero frames. Signal EOF explicitly and let the converter drain its tail.
                let remaining = file.length - file.framePosition
                guard remaining > 0 else {
                    status.pointee = .endOfStream
                    return nil
                }
                let frames = AVAudioFrameCount(min(remaining, AVAudioFramePosition(min(count, buffer.frameCapacity))))
                try file.read(into: buffer, frameCount: frames)
                status.pointee = buffer.frameLength == 0 ? .endOfStream : .haveData
                return buffer.frameLength == 0 ? nil : buffer
            } catch {
                self.error = error
                status.pointee = .endOfStream
                return nil
            }
        }
    }
}
