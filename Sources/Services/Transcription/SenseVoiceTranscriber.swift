import Foundation

/// Performs local inference off the main actor. There are deliberately no suspension points
/// while a recognizer is in use, serializing prepare/decode/unload and preventing handle races.
actor SenseVoiceTranscriber {
    static let shared = SenseVoiceTranscriber()

    private var recognizer: SenseVoiceRecognizer?
    private var cachedModelURL: URL?
    private var cachedTokensURL: URL?
    private var cachedLanguage: String?

    private init() {}

    /// Loads and caches the model without running dummy audio through it.
    func prepare(modelURL: URL, tokensURL: URL, language: String = "auto") async throws {
        try Task.checkCancellation()
        try loadRecognizer(modelURL: modelURL, tokensURL: tokensURL, language: Self.normalizedLanguage(language))
        try Task.checkCancellation()
    }

    func transcribe(voiceURL: URL, modelURL: URL, tokensURL: URL, language: String) async throws -> String {
        try Task.checkCancellation()
        let language = try Self.normalizedLanguage(language)
        let reader = try SenseVoiceAudioReader(url: voiceURL)
        try loadRecognizer(modelURL: modelURL, tokensURL: tokensURL, language: language)
        guard let recognizer else { throw SenseVoiceError.modelLoadFailed }

        var parts: [String] = []
        while let samples = try reader.nextChunk() {
            try Task.checkCancellation()
            let part = Self.cleanTranscript(try recognizer.decode(samples: samples))
            if !part.isEmpty { parts.append(part) }
        }
        try Task.checkCancellation()
        return parts.joined(separator: " ")
    }

    func unload() {
        recognizer = nil
        cachedModelURL = nil
        cachedTokensURL = nil
        cachedLanguage = nil
    }

    nonisolated static func cleanTranscript(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedLanguage(_ language: String) throws -> String {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["auto", "zh", "en", "yue", "ja", "ko"].contains(normalized) else {
            throw SenseVoiceError.unsupportedLanguage(language)
        }
        return normalized
    }

    private func loadRecognizer(modelURL: URL, tokensURL: URL, language: String) throws {
        for url in [modelURL, tokensURL] {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard url.isFileURL, values?.isRegularFile == true, (values?.fileSize ?? 0) > 0,
                  FileManager.default.isReadableFile(atPath: url.path) else {
                throw SenseVoiceError.missingModelFile(url.lastPathComponent)
            }
        }
        let modelURL = modelURL.standardizedFileURL
        let tokensURL = tokensURL.standardizedFileURL
        guard recognizer == nil || cachedModelURL != modelURL || cachedTokensURL != tokensURL
                || cachedLanguage != language else { return }

        // v2.0.1's SetConfig resets SenseVoice-specific feature extraction settings. Rebuild
        // when the language changes instead, retaining one native model at a time.
        // Release the previous model before allocating another one on memory-constrained devices.
        unload()
        let loaded = try SenseVoiceRecognizer(modelURL: modelURL, tokensURL: tokensURL, language: language)
        try Task.checkCancellation()
        recognizer = loaded
        cachedModelURL = modelURL
        cachedTokensURL = tokensURL
        cachedLanguage = language
    }
}
