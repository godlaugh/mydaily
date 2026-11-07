import SwiftUI

@MainActor
struct LocalTranscriptionModelSection: View {
    @EnvironmentObject private var config: Config
    let model: LocalTranscriptionModel
    @ObservedObject var store: TranscriptionModelStore

    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var isInstalled: Bool { store.state == .installed }
    private var isCurrentModel: Bool {
        config.transProvider == .senseVoice && config.localTranscriptionModel == model
    }
    private var isSelected: Bool { isCurrentModel && isInstalled }

    private var modelDescription: String {
        let size = ByteCountFormatter.string(fromByteCount: model.downloadBytes, countStyle: .file)
        let specification: String
        switch model {
        case .senseVoiceSmall:
            specification = L(.trans_model_int8_specification, size)
        case .senseVoiceSmallFP32:
            specification = L(.trans_model_fp32_specification, size)
        }
        return specification
    }

    private func identifier(_ name: String) -> String {
        model == .senseVoiceSmall ? name : name + "_fp32"
    }

    private var statusLabel: String {
        switch store.state {
        case .installed: return L(.trans_model_downloaded)
        case .downloading:
            return TranscriptionModelDownloadProgressView.phaseLabel(store.downloadProgress?.phase ?? .connecting)
        case .notDownloaded, .failed: return L(.trans_model_download_required)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: selectModel) {
                TranscriptionModelOptionRow(
                    title: model == .senseVoiceSmall ? "INT8" : "FP32",
                    detail: modelDescription,
                    badge: statusLabel,
                    isSelected: isSelected
                )
            }
            .buttonStyle(.plain)
            .disabled(!isInstalled || isDeleting)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier(identifier("transcription_model_sensevoice"))

            switch store.state {
            case .notDownloaded:
                Button(action: store.download) {
                    Label(L(.trans_model_download), systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier(identifier("transcription_model_download"))

            case .downloading:
                TranscriptionModelDownloadProgressView(
                    progress: store.downloadProgress,
                    totalBytes: model.downloadBytes,
                    identifier: identifier("transcription_model_download_progress")
                )
                Button(L(.trans_model_cancel_download), action: store.cancelDownload)
                    .accessibilityIdentifier(identifier("transcription_model_cancel_download"))

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: store.download) {
                    Label(L(.try_again), systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier(identifier("transcription_model_retry"))

            case .installed:
                Button(role: .destructive, action: requestDeletion) {
                    Label(L(.trans_model_delete), systemImage: "trash")
                }
                .disabled(isDeleting || store.activeTranscriptions > 0)
                .accessibilityIdentifier(identifier("transcription_model_delete"))
                .confirmationDialog(
                    L(.trans_model_delete_title, model.displayName),
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(L(.trans_model_delete), role: .destructive, action: deleteModel)
                        .accessibilityIdentifier(identifier("transcription_model_confirm_delete"))
                    Button(L(.cancel), role: .cancel) { }
                } message: {
                    Text(isCurrentModel
                         ? L(.trans_model_delete_selected_message)
                         : L(.trans_model_delete_message))
                }

                if isDeleting {
                    ProgressView(L(.trans_model_deleting))
                } else if store.activeTranscriptions > 0 {
                    Text(L(.trans_model_in_use))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert(L(.error), isPresented: $showError) {
            Button(L(.ok), role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func selectModel() {
        guard isInstalled, !isDeleting else { return }
        config.localTranscriptionModel = model
        config.transProvider = .senseVoice
    }

    private func requestDeletion() {
        showDeleteConfirmation = true
    }

    private func deleteModel() {
        guard !isDeleting, store.activeTranscriptions == 0 else { return }
        isDeleting = true
        Task {
            do {
                try store.remove()
                if isCurrentModel {
                    config.transProvider = .apple
                    await SenseVoiceTranscriber.shared.unload()
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isDeleting = false
        }
    }
}
