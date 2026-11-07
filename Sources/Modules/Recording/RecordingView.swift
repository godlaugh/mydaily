import CoreData
import SwiftUI
import DSWaveformImage
import DSWaveformImageViews

struct RecordingView: View {
    let parentID: NSManagedObjectID?
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var config: Config
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @StateObject private var recorder = AudioRecorder()
    @State private var started = false
    @State private var discard = false
    @State private var parentTitle: String?

    init(parentID: NSManagedObjectID? = nil) { self.parentID = parentID }

    var body: some View {
        Group {
            if recorder.isCompleted, let url = recorder.voiceFile {
                RecordingCompletedView(voiceURL: url, parentID: parentID)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button { discard = true } label: {
                            Label(L(.cancel), systemImage: "xmark").labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                        }
                        Spacer()
                        HStack(spacing: 7) {
                            Circle().fill(JournalTheme.accent).frame(width: 5, height: 5)
                            Text(JournalText.string(recorder.isRecording ? "recording" : "preparing")).font(.caption)
                        }
                        Spacer()
                        Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                    }
                    Spacer()
                    Text(JournalText.string("recording_prompt")).font(.title3)
                    if let parentTitle {
                        Text(parentTitle).font(.caption).foregroundStyle(JournalTheme.secondary).padding(.top, 12)
                    }
                    Text(recorder.formattedTime)
                        .font(.system(.largeTitle, design: .monospaced).weight(.light))
                        .scaleEffect(1.6).padding(.vertical, 36)
                        .accessibilityIdentifier("journal_recording_time")
                    WaveformLiveCanvas(samples: recorder.samples, configuration: .init(
                        style: .striped(.init(color: UIColor(red: 0.94, green: 0.63, blue: 0.54, alpha: 1), width: 3, spacing: 4))
                    ))
                    .frame(height: 120).accessibilityHidden(true)
                    Label(privacyLabel, systemImage: config.transProvider == .openai ? "cloud" : "lock")
                        .font(.caption).foregroundStyle(JournalTheme.secondary)
                        .multilineTextAlignment(.center).padding(.top, 26)
                    if let error = recorder.recordingError {
                        Text(error).font(.footnote).foregroundStyle(JournalTheme.accent).padding(.top, 18)
                    }
                    Spacer()
                    Button(action: recorder.stopRecording) {
                        Image(systemName: "stop.fill").font(.title2)
                            .foregroundStyle(Color(red: 0.14, green: 0.13, blue: 0.12))
                            .frame(width: 62, height: 62)
                            .background(JournalTheme.accent, in: Circle())
                            .padding(8)
                            .overlay(Circle().strokeBorder(JournalTheme.secondary.opacity(0.6), lineWidth: 1))
                    }
                    .disabled(!recorder.isRecording)
                    .accessibilityLabel(JournalText.string("finish_recording"))
                    .accessibilityIdentifier("journal_recording_stop")
                    Text(JournalText.string("finish_recording")).font(.subheadline).padding(.top, 12)
                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 28).padding(.top, 12)
                .foregroundStyle(JournalTheme.ink)
                .background(JournalTheme.paper)
                .preferredColorScheme(.dark)
                .buttonStyle(.plain)
                .confirmationDialog(JournalText.string("discard"), isPresented: $discard, titleVisibility: .visible) {
                    Button(JournalText.string("discard_action"), role: .destructive) { recorder.terminate(); dismiss() }
                    Button(JournalText.string("keep_recording"), role: .cancel) { }
                }
            }
        }
        .task {
            guard !started else { return }
            started = true
            if let parentID, let memo = try? context.existingObject(with: parentID) as? MemoEntity {
                parentTitle = memo.journalTitle
            }
            recorder.startRecording()
        }
        .onChange(of: appState.micPermission) { permission in if permission == .denied { dismiss() } }
        .onChange(of: recorder.isRecording) { UIApplication.shared.isIdleTimerDisabled = $0 }
        .onDisappear {
            if !recorder.isCompleted { recorder.terminate() }
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var privacyLabel: String {
        if config.transEnabled && config.transProvider == .openai { return JournalText.string("cloud_recording") }
        if config.transEnabled && config.transProvider == .senseVoice {
            return JournalText.string("local_recording") + " · " + config.localTranscriptionModel.displayName
        }
        return JournalText.string("local_recording")
    }
}
