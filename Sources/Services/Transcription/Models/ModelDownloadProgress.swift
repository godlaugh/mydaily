import Foundation

struct ModelDownloadProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case connecting
        case downloading
        case verifying
    }

    let phase: Phase
    let receivedBytes: Int64
    let totalBytes: Int64
    let bytesPerSecond: Double
    let sourceHost: String
}
