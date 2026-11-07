import SwiftUI

struct JournalAudioChip: View {
    @ObservedObject var memo: MemoEntity
    @ObservedObject private var player = AudioPlayer.shared

    var body: some View {
        if let file = memo.file {
            Button { player.toggle(file: file, title: memo.journalTitle) } label: {
                HStack(spacing: 5) {
                    Image(systemName: player.currentFile == file && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption2)
                    Text(memo.journalDuration).font(.caption).monospacedDigit()
                }
                .frame(minWidth: 60, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(player.currentFile == file ? JournalTheme.accent : JournalTheme.secondary)
            .accessibilityLabel(JournalText.string(player.currentFile == file && player.isPlaying ? "pause" : "play"))
            .accessibilityValue(memo.journalDuration)
            .accessibilityIdentifier("journal_audio_\(memo.id ?? "")")
            .task(id: file) { await loadDuration(file) }
        }
    }

    @MainActor private func loadDuration(_ file: String) async {
        guard memo.duration <= 0 else { return }
        let duration = await FileHelper.getAudioDuration(FileHelper.fullAudioURL(for: file))
        guard !Task.isCancelled, !memo.isDeleted, duration.isFinite, duration > 0 else { return }
        memo.duration = duration
        try? memo.managedObjectContext?.save()
    }
}
