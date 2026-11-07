import SwiftUI

struct JournalDock: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var config: Config
    @ObservedObject var timeline: TimelineViewModel
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        HStack(spacing: 8) {
            tab(0, "tab_journal", "book")
            if config.holdToRecordEnabled && !voiceOver {
                JournalHoldToRecordButton(timeline: timeline)
            } else {
                Button { appState.startRecording() } label: {
                    Label(JournalText.string("record"), systemImage: "mic")
                        .labelStyle(.iconOnly).font(.title2).foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(JournalTheme.record, in: Circle())
                        .contentShape(Circle())
                }
                .accessibilityIdentifier("microphone")
                .contextMenu {
                    Button(action: appState.startCreatingNote) { Label(JournalText.string("write"), systemImage: "square.and.pencil") }
                }
            }
            tab(1, "tab_review", "sparkles")
        }
        .buttonStyle(.plain)
        .padding(7)
        .background(JournalTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(JournalTheme.line, lineWidth: 1))
        .alert(JournalText.string("error"), isPresented: Binding(get: { timeline.recordingError != nil }, set: { if !$0 { timeline.recordingError = nil } })) { } message: { Text(timeline.recordingError ?? "") }
    }

    private func tab(_ index: Int, _ title: String, _ symbol: String) -> some View {
        Button { appState.activeTab = index } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.body)
                Text(JournalText.string(title)).font(.caption2)
            }
            .frame(maxWidth: .infinity).frame(minHeight: 50)
            .foregroundStyle(appState.activeTab == index ? JournalTheme.ink : JournalTheme.secondary)
        }
        .disabled(timeline.isHoldingToRecord)
        .accessibilityAddTraits(appState.activeTab == index ? .isSelected : [])
        .accessibilityIdentifier(index == 0 ? "journal_tab" : "review_tab")
    }
}
