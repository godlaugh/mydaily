import SwiftUI

/// Attach to the root ScrollView so its scrolling range includes the full bar height.
/// An inset outside NavigationStack is not reliably forwarded to the scroll content.
struct JournalBottomBar: View {
    @EnvironmentObject private var timeline: TimelineViewModel
    @ObservedObject private var player = AudioPlayer.shared

    var body: some View {
        if !timeline.isMultiSelectMode {
            VStack(spacing: 10) {
                if player.currentFile != nil { JournalMiniPlayer() }
                JournalDock(timeline: timeline)
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 8)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .background(JournalTheme.paper)
        }
    }
}
