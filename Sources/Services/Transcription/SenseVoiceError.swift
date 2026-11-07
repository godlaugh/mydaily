import Foundation

enum SenseVoiceError: LocalizedError {
    case missingModelFile(String)
    case modelLoadFailed
    case invalidAudioFormat
    case audioConversionFailed
    case streamCreationFailed
    case resultUnavailable
    case unsupportedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .missingModelFile(let name):
            return L(.error_local_model_missing_file, name)
        case .modelLoadFailed:
            return L(.error_local_model_load)
        case .invalidAudioFormat:
            return L(.error_local_model_audio_format)
        case .audioConversionFailed:
            return L(.error_local_model_audio_read)
        case .streamCreationFailed, .resultUnavailable:
            return L(.error_local_model_process)
        case .unsupportedLanguage(let language):
            return L(.error_local_model_language, language)
        }
    }
}
