import SwiftUI
import CoreData

struct RecordingCompletedView: View {
    @StateObject private var vm: RecordingCompletedViewModel
    @StateObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var discard = false

    init(voiceURL: URL, parentID: NSManagedObjectID? = nil) {
        _vm = StateObject(wrappedValue: RecordingCompletedViewModel(voicePath: voiceURL, parentID: parentID))
        _player = StateObject(wrappedValue: AudioPlayer(voiceURL))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(JournalText.string("recording_complete")).font(.title2)
                Spacer()
                Button(role: .destructive) { discard = true } label: {
                    Label(JournalText.string("discard_action"), systemImage: "trash")
                        .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
                }
            }
            HStack(spacing: 12) {
                Button { player.isPlaying ? player.pause() : player.play() } label: {
                    Label(JournalText.string(player.isPlaying ? "pause" : "play"), systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                        .labelStyle(.iconOnly).frame(width: 48, height: 48)
                        .background(JournalTheme.soft, in: Circle())
                }
                Text(MemoEntity.durationLabel(vm.duration)).font(.subheadline).monospacedDigit()
                Spacer()
                if vm.isTranscribing { ProgressView(L(.transcribing)).font(.caption) }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $vm.content)
                    .font(.body).lineSpacing(7).scrollContentBackground(.hidden)
                    .disabled(vm.isTranscribing)
                    .accessibilityLabel(JournalText.string("thought"))
                if vm.content.isEmpty && !vm.isTranscribing {
                    Text(JournalText.string("placeholder"))
                        .font(.body).foregroundStyle(JournalTheme.secondary)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            if let error = vm.transcriptionError {
                Text(error).font(.footnote).foregroundStyle(JournalTheme.secondary)
                Button { vm.transcribe() } label: { Label(L(.try_again), systemImage: "arrow.clockwise") }
            }
            Button { hideKeyboard(); vm.save() } label: {
                Text(L(.save)).frame(maxWidth: .infinity).frame(minHeight: 50)
                    .foregroundStyle(.white).background(JournalTheme.record, in: Capsule())
            }
            .disabled(!vm.canBeSaved || vm.isTranscribing)
            .accessibilityIdentifier("journal_save_recording")
        }
        .padding(24).foregroundStyle(JournalTheme.ink).background(JournalTheme.paper)
        .buttonStyle(.plain)
        .onChange(of: vm.saved) { saved in if saved { dismiss() } }
        .task {
            await vm.prepare()
            if Config.shared.autoSave { vm.save() }
            else { vm.transcribe() }
        }
        .onDisappear { vm.cancelTranscription(); player.stop() }
        .alert(JournalText.string("error"), isPresented: Binding(get: { vm.saveError != nil }, set: { if !$0 { vm.saveError = nil } })) { } message: { Text(vm.saveError ?? "") }
        .confirmationDialog(JournalText.string("discard"), isPresented: $discard, titleVisibility: .visible) {
            Button(JournalText.string("discard_action"), role: .destructive) { vm.delete(); dismiss() }
            Button(L(.cancel), role: .cancel) { }
        }
    }
}
