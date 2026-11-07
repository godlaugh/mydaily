import SwiftUI
import CoreData

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @StateObject private var timeline = TimelineViewModel()
    @ObservedObject private var player = AudioPlayer.shared
    @State private var path: [NSManagedObjectID] = []

    var body: some View {
        Group {
            if appState.activeTab == 0 {
                NavigationStack(path: $path) {
                    TimelineView { path.append($0.objectID) }
                        .navigationDestination(for: NSManagedObjectID.self) { id in
                            if let memo = try? context.existingObject(with: id) as? MemoEntity {
                                JournalDetailView(anchor: memo)
                            }
                        }
                }
            } else {
                SummaryView()
            }
        }
        .environmentObject(timeline)
        .foregroundStyle(JournalTheme.ink)
        .background(JournalTheme.paper)
        .sheet(item: $appState.activeSheet) { item in
            switch item {
            case .settings: SettingsView()
            case .quickMemo: JournalComposeView()
            case .appendMemo(let memo): JournalComposeView(parent: memo)
            case .summarize(let item): AddSummaryPromptView(item: item).interactiveDismissDisabled()
            case .micPermission: MicPermissionView()
            case .editMemo(let memo): MemoEditView(memo: memo)
            case .editSummary(let summary): SummaryEditView(summary: summary)
            }
        }
        .fullScreenCover(isPresented: $appState.showRecording, onDismiss: { appState.recordingParentID = nil }) {
            RecordingView(parentID: appState.recordingParentID)
        }
        .alert(JournalText.string("error"), isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) { } message: {
            Text(player.errorMessage ?? "")
        }
    }
}
