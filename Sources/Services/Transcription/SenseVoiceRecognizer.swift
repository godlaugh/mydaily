import Foundation
import SherpaOnnxC

/// Owned exclusively by SenseVoiceTranscriber. Native handles never cross its actor boundary.
final class SenseVoiceRecognizer {
    private let handle: OpaquePointer

    init(modelURL: URL, tokensURL: URL, language: String) throws {
        let recognizer = Self.withConfiguration(modelURL: modelURL, tokensURL: tokensURL, language: language) {
            SherpaOnnxCreateOfflineRecognizer(&$0)
        }
        guard let recognizer else { throw SenseVoiceError.modelLoadFailed }
        handle = recognizer
    }

    deinit {
        SherpaOnnxDestroyOfflineRecognizer(handle)
    }

    func decode(samples: [Float]) throws -> String {
        try Task.checkCancellation()
        guard let stream = SherpaOnnxCreateOfflineStream(handle) else {
            throw SenseVoiceError.streamCreationFailed
        }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        // SenseVoice uses 25 ms feature windows with snip_edges. A very short final chunk
        // must still contain enough frames for the feature extractor and LFR stacking.
        let minimumFrames = SenseVoiceAudioReader.sampleRate / 10
        let input = samples.count < minimumFrames
            ? samples + [Float](repeating: 0, count: minimumFrames - samples.count)
            : samples
        input.withUnsafeBufferPointer {
            SherpaOnnxAcceptWaveformOffline(stream, Int32(SenseVoiceAudioReader.sampleRate), $0.baseAddress, Int32($0.count))
        }
        try Task.checkCancellation()
        // The native decode call is synchronous. Cancellation takes effect at the next
        // boundary, and each native stream is capped at 30 seconds of audio.
        SherpaOnnxDecodeOfflineStream(handle, stream)
        try Task.checkCancellation()
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
            throw SenseVoiceError.resultUnavailable
        }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        guard let text = result.pointee.text else { throw SenseVoiceError.resultUnavailable }
        return String(cString: text)
    }

    private static func withConfiguration<Result>(
        modelURL: URL, tokensURL: URL, language: String,
        body: (inout SherpaOnnxOfflineRecognizerConfig) -> Result
    ) -> Result {
        // Each C string remains alive until the synchronous C API has copied the config.
        modelURL.path.withCString { model in
            tokensURL.path.withCString { tokens in
                language.withCString { language in
                    "cpu".withCString { provider in
                        "greedy_search".withCString { decodingMethod in
                            var config = SherpaOnnxOfflineRecognizerConfig()
                            config.feat_config.sample_rate = Int32(SenseVoiceAudioReader.sampleRate)
                            config.feat_config.feature_dim = 80
                            config.model_config.sense_voice.model = model
                            config.model_config.sense_voice.language = language
                            config.model_config.sense_voice.use_itn = 1
                            config.model_config.tokens = tokens
                            config.model_config.provider = provider
                            config.model_config.num_threads = Int32(min(2, ProcessInfo.processInfo.activeProcessorCount))
                            config.decoding_method = decodingMethod
                            return body(&config)
                        }
                    }
                }
            }
        }
    }
}
