import SwiftUI
import DSWaveformImage
import DSWaveformImageViews

struct JournalAudioDetail: View {
    @ObservedObject var memo: MemoEntity
    @ObservedObject private var player = AudioPlayer.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let file = memo.file {
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    JournalAudioChip(memo: memo)
                    WaveformView(audioURL: FileHelper.fullAudioURL(for: file), configuration: .init(
                        style: .striped(.init(color: colorScheme == .dark ? .lightGray : .darkGray, width: 2, spacing: 3))
                    ))
                    .frame(height: 32)
                    .accessibilityHidden(true)
                }
                if player.currentFile == file {
                    Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                           in: 0...max(player.duration, 1))
                        .tint(JournalTheme.accent)
                        .accessibilityLabel(JournalText.string("playback_progress"))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(JournalTheme.soft, in: RoundedRectangle(cornerRadius: 19))
        }
    }
}
