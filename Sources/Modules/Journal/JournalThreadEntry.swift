import SwiftUI

struct JournalThreadEntry: View {
    @ObservedObject var memo: MemoEntity
    let first: Bool
    let last: Bool
    let connected: Bool
    let delete: () -> Void
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var timeline: TimelineViewModel
    @EnvironmentObject private var config: Config
    @ObservedObject private var player = AudioPlayer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(memo.journalDate).font(.caption).monospacedDigit().foregroundStyle(JournalTheme.secondary)
                Spacer(minLength: 8)
                Menu {
                    Button { appState.activeSheet = .editMemo(memo) } label: { Label(L(.edit), systemImage: "square.and.pencil") }
                    ShareLink(item: memo.viewContent) { Label(L(.share), systemImage: "square.and.arrow.up") }
                    if let file = memo.file {
                        ShareLink(item: FileHelper.fullAudioURL(for: file)) { Label(L(.share_audio), systemImage: "waveform") }
                    }
                    Button { timeline.toggleVisibility(memo) } label: { Label(L(memo.isHidden ? .show : .hide), systemImage: memo.isHidden ? "eye" : "eye.slash") }
                    Button(role: .destructive, action: delete) { Label(L(.delete), systemImage: "trash") }
                } label: { Label(L(.edit), systemImage: "ellipsis").labelStyle(.iconOnly).frame(width: 44, height: 44) }
                .accessibilityIdentifier("journal_entry_menu_\(memo.id ?? "")")
            }
            if first {
                Text(memo.journalTitle).font(JournalTheme.headline).lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
            }
            if timeline.transcribingMemos.contains(memo) {
                ProgressView(L(.transcribing)).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let text = first ? memo.journalExcerpt : memo.journalPreview
                if !text.isEmpty {
                    Text(text).font(.body).lineSpacing(8)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if memo.file != nil {
                if first || player.currentFile == memo.file {
                    JournalAudioDetail(memo: memo).padding(.top, 6)
                } else { JournalAudioChip(memo: memo) }
                if config.transEnabled {
                    HStack {
                        Spacer()
                        Button { timeline.transcribe(memo) } label: {
                            Label(L(memo.transcribed ? .retranscribe : .transcribe), systemImage: "arrow.clockwise")
                        }
                        .font(.caption).frame(minHeight: 44)
                        .disabled(timeline.transcribingMemos.contains(memo))
                        .accessibilityIdentifier("journal_transcribe_\(memo.id ?? "")")
                    }
                }
            }
            if let error = timeline.failedMemos[memo] {
                Text(ErrorHelper.desc(error)).font(.caption).foregroundStyle(JournalTheme.accent)
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 24).padding(.bottom, last ? 16 : 26)
        .background(alignment: .topLeading) {
            if connected {
                Rectangle().fill(JournalTheme.line).frame(width: 1, height: last ? 22 : nil)
                    .padding(.leading, 3).padding(.top, first ? 22 : 0)
            }
        }
        .overlay(alignment: .topLeading) {
            Circle().fill(last ? JournalTheme.accent : JournalTheme.secondary)
                .frame(width: 7, height: 7).padding(.top, 18)
                .accessibilityHidden(true)
        }
    }
}
