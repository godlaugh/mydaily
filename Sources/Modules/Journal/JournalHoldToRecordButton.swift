import SwiftUI

struct JournalHoldToRecordButton: View {
    @ObservedObject var timeline: TimelineViewModel
    @ObservedObject private var recorder: AudioRecorder
    @EnvironmentObject private var appState: AppState
    @GestureState private var touching = false
    @State private var started = false
    @State private var canceling = false

    init(timeline: TimelineViewModel) {
        self.timeline = timeline
        self.recorder = timeline.recorder
    }

    var body: some View {
        Image(systemName: canceling ? "xmark" : "mic")
            .font(.title2).foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(JournalTheme.record, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(started ? 0.8 : 0), lineWidth: 3))
            .contentShape(Circle())
            .overlay(alignment: .top) {
                if started {
                    VStack(spacing: 8) {
                        Text(recorder.formattedTime).monospacedDigit()
                        Text(JournalText.string(canceling ? "release_cancel" : "release_save"))
                    }
                    .font(.caption).foregroundStyle(JournalTheme.ink)
                    .fixedSize().padding(14)
                    .background(JournalTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .offset(y: -90)
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { value in
                    if !started {
                        guard appState.canStartRecording() else { return }
                        started = true
                        timeline.beginHoldToRecord()
                    }
                    canceling = value.translation.height < -60
                }
                .onEnded { _ in
                    guard started else { return }
                    started = false
                    canceling ? timeline.cancelHoldToRecord() : timeline.endHoldToRecord()
                    canceling = false
                })
            .onChange(of: touching) { value in
                if !value && started {
                    started = false
                    canceling = false
                    timeline.cancelHoldToRecord()
                }
            }
            .onChange(of: recorder.recordingError) { error in
                if let error { timeline.recordingError = error; timeline.cancelHoldToRecord() }
            }
            .onDisappear { if started { timeline.cancelHoldToRecord() } }
            .accessibilityLabel(JournalText.string("record"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { appState.startRecording() }
            .accessibilityIdentifier("microphone")
    }
}
