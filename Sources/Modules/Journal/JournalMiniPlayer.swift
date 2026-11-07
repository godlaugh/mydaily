import SwiftUI

struct JournalMiniPlayer: View {
    @ObservedObject private var player = AudioPlayer.shared

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.currentTitle.isEmpty ? JournalText.string("audio_note") : player.currentTitle)
                        .font(.subheadline).lineLimit(1)
                    Text("\(MemoEntity.durationLabel(player.currentTime)) / \(MemoEntity.durationLabel(player.duration))")
                        .font(.caption2).monospacedDigit().foregroundStyle(JournalTheme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Label(JournalText.string(player.isPlaying ? "pause" : "play"), systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                        .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("journal_mini_toggle")
                Button(action: player.stop) {
                    Label(JournalText.string("close_player"), systemImage: "xmark")
                        .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                    .foregroundStyle(JournalTheme.secondary)
                    .accessibilityIdentifier("journal_mini_close")
            }
            ProgressView(value: player.currentTime, total: max(1, player.duration))
                .tint(JournalTheme.accent)
                .accessibilityLabel(JournalText.string("playback_progress"))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 15).padding(.vertical, 9)
        .background(JournalTheme.soft, in: RoundedRectangle(cornerRadius: 21))
    }
}
