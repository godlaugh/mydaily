import Foundation

enum ModelInstallState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case installed
    case failed(String)
}

struct LocalModelFiles: Sendable {
    let modelURL: URL
    let tokensURL: URL
}

enum ModelInstallError: LocalizedError {
    case notInstalled
    case modelInUse
    case invalidResponse
    case invalidSize(String)
    case invalidChecksum(String)
    case invalidInstallation

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return L(.error_model_not_installed)
        case .modelInUse:
            return L(.error_model_in_use)
        case .invalidResponse:
            return L(.error_model_download_response)
        case .invalidSize(let filename):
            return L(.error_model_download_size, filename)
        case .invalidChecksum(let filename):
            return L(.error_model_download_checksum, filename)
        case .invalidInstallation:
            return L(.error_model_installation)
        }
    }
}
