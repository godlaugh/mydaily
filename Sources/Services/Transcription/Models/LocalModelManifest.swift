import Foundation

struct ModelArtifact: Sendable {
    let filename: String
    let remoteURL: URL
    let byteCount: Int64
    let sha256: String
    let fallbackURLs: [URL]

    init(filename: String, remoteURL: URL, byteCount: Int64, sha256: String,
         fallbackURLs: [URL] = []) {
        self.filename = filename
        self.remoteURL = remoteURL
        self.byteCount = byteCount
        self.sha256 = sha256
        self.fallbackURLs = fallbackURLs
    }

    var downloadURLs: [URL] { [remoteURL] + fallbackURLs }
}

struct LocalModelManifest: Sendable {
    let directoryName: String
    let revision: String
    let model: ModelArtifact
    let tokens: ModelArtifact

    var artifacts: [ModelArtifact] { [model, tokens] }
}
