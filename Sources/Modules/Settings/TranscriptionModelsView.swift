import SwiftUI

@MainActor
struct TranscriptionModelsView: View {
    @EnvironmentObject private var config: Config

    private var cloudModels: [TranscriptionModel] {
        config.serverType == .app
            ? TranscriptionModel.defaultServerModels
            : TranscriptionModel.customServerModels
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(JournalText.string("models_heading")).font(.title.bold())
                    Text(JournalText.string("models_subtitle")).font(.subheadline).foregroundStyle(JournalTheme.secondary)
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(LocalTranscriptionModel.allCases, id: \.self) { model in
                    LocalTranscriptionModelSection(model: model, store: TranscriptionModelStore.store(for: model))
                        .listRowBackground(JournalTheme.surface)
                }
            } header: {
                Label("SenseVoice Small", systemImage: "waveform")
            } footer: {
                Text(L(.trans_model_sensevoice_languages) + "\n" + JournalText.string("model_family_note"))
            }

            Section {
                Button(action: selectApple) {
                    TranscriptionModelOptionRow(
                        title: "Apple Speech",
                        detail: L(.trans_model_apple_description),
                        badge: L(.trans_model_system),
                        isSelected: config.transProvider == .apple
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(config.transProvider == .apple ? .isSelected : [])
                .accessibilityIdentifier("transcription_model_apple")
            } header: {
                Text(L(.trans_model_system))
            } footer: {
                Text(L(.trans_provider_apple_notice))
            }

            Section {
                Button(action: selectOpenAI) {
                    TranscriptionModelOptionRow(
                        title: "OpenAI",
                        detail: L(.trans_model_server, config.serverType.displayName),
                        badge: L(.trans_model_cloud),
                        isSelected: config.transProvider == .openai
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(config.transProvider == .openai ? .isSelected : [])
                .accessibilityIdentifier("transcription_model_openai")

                if config.transProvider == .openai {
                    Picker(L(.settings_trans_model), selection: $config.transModel) {
                        ForEach(cloudModels, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .accessibilityIdentifier("transcription_cloud_model_picker")

                    if config.serverType == .custom {
                        NavigationLink {
                            ServerSettingsView()
                        } label: {
                            Text(L(.settings_server_settings))
                        }
                    }
                }
            } header: {
                Text(L(.trans_model_cloud))
            } footer: {
                Text(L(.trans_model_cloud_description))
            }
        }
        .navigationTitle(L(.transcription_models))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(JournalTheme.paper)
        .tint(JournalTheme.accent)
    }

    private func selectApple() {
        config.transProvider = .apple
    }

    private func selectOpenAI() {
        if !TranscriptionModel.isModelAvailable(config.transModel, for: config.serverType) {
            config.transModel = .whisper_1
        }
        config.transProvider = .openai
    }
}
