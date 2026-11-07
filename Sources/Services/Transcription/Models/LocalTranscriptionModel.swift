import Foundation

enum LocalTranscriptionModel: String, CaseIterable, Sendable {
    case senseVoiceSmall
    case senseVoiceSmallFP32

    var displayName: String {
        switch self {
        case .senseVoiceSmall: return "SenseVoice Small INT8"
        case .senseVoiceSmallFP32: return "SenseVoice Small FP32"
        }
    }
    var downloadBytes: Int64 { manifest.artifacts.reduce(0) { $0 + $1.byteCount } }

    var manifest: LocalModelManifest {
        // Keep the receipt revision stable for existing installations. Both hosts
        // serve the same bytes, pinned to immutable revisions and checked against
        // the original sherpa-onnx export's size and SHA-256 before installation.
        let revision = "2365baeacb507f821a0c8120fcee3d484dba7a07"
        let origin = "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/\(revision)/"
        let mirrorRevision = "59ee0bceb05d61d4148341323e509db2899bd9a2"
        let mirror = "https://modelscope.cn/models/WEAAEW/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/\(mirrorRevision)/"
        guard let baseURL = URL(string: mirror), let fallbackURL = URL(string: origin) else {
            preconditionFailure("The bundled model URL must be valid")
        }
        let directoryName: String
        let model: ModelArtifact
        switch self {
        case .senseVoiceSmall:
            // Keep the original directory and manifest so existing installations
            // remain usable when the FP32 option is added.
            directoryName = "sensevoice-small-2024-07-17-int8"
            model = ModelArtifact(
                filename: "model.int8.onnx",
                remoteURL: baseURL.appendingPathComponent("model.int8.onnx"),
                byteCount: 239_233_841,
                sha256: "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51",
                fallbackURLs: [fallbackURL.appendingPathComponent("model.int8.onnx")]
            )
        case .senseVoiceSmallFP32:
            directoryName = "sensevoice-small-2024-07-17-fp32"
            model = ModelArtifact(
                filename: "model.onnx",
                remoteURL: baseURL.appendingPathComponent("model.onnx"),
                byteCount: 937_617_178,
                sha256: "977016bd9c79f9eb343430b5cc305e07ab64d5212dff41b0dcfa1694bee9a8cb",
                fallbackURLs: [fallbackURL.appendingPathComponent("model.onnx")]
            )
        }
        return LocalModelManifest(
            directoryName: directoryName,
            revision: revision,
            model: model,
            tokens: ModelArtifact(
                filename: "tokens.txt",
                remoteURL: baseURL.appendingPathComponent("tokens.txt"),
                byteCount: 315_894,
                sha256: "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc",
                fallbackURLs: [fallbackURL.appendingPathComponent("tokens.txt")]
            )
        )
    }
}
