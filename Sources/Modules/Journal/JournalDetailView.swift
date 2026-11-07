import SwiftUI
import CoreData

struct JournalDetailView: View {
    @ObservedObject var anchor: MemoEntity
    @FetchRequest(fetchRequest: MemoEntity.all) private var entries
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var timeline: TimelineViewModel
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deletion: MemoEntity?
    @State private var errorMessage: String?

    private var group: JournalGroup? { JournalGroup.containing(anchor, in: Array(entries)) }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                if let group {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(group.entries) { memo in
                            JournalThreadEntry(memo: memo, first: memo == group.first,
                                               last: memo == group.latest,
                                               connected: group.entries.count > 1) { deletion = memo }
                                .id(memo.objectID)
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 28)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(JournalTheme.paper)
            .onChange(of: group?.entries.count) { count in
                guard let count, count > 1, let last = group?.latest.objectID else { return }
                if reduceMotion { scroll.scrollTo(last, anchor: .bottom) }
                else { withAnimation(.easeInOut(duration: 0.25)) { scroll.scrollTo(last, anchor: .bottom) } }
            }
        }
        .navigationTitle(JournalText.string("detail"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(JournalTheme.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                Button { appState.startRecording(parent: anchor) } label: {
                    Label(JournalText.string("continue"), systemImage: "mic")
                        .frame(maxWidth: .infinity).frame(minHeight: 48)
                }
                .background(JournalTheme.soft, in: Capsule())
                .accessibilityLabel(JournalText.string("continue_voice"))
                .accessibilityIdentifier("journal_continue_voice")
                Button { appState.activeSheet = .appendMemo(anchor) } label: {
                    Label(JournalText.string("continue_text"), systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly).frame(width: 48, height: 48)
                }
                .background(JournalTheme.soft, in: Circle())
                .accessibilityIdentifier("journal_continue_text")
            }
            .font(.subheadline).buttonStyle(.plain)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
            .background(JournalTheme.paper)
        }
        .confirmationDialog(JournalText.string("delete_entry"), isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button(L(.delete), role: .destructive, action: deleteEntry)
            Button(L(.cancel), role: .cancel) { deletion = nil }
        } message: { Text(JournalText.string("delete_entry_body")) }
        .alert(JournalText.string("error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { } message: { Text(errorMessage ?? "") }
        .onChange(of: anchor.isDeleted) { deleted in if deleted { dismiss() } }
    }

    private func deleteEntry() {
        guard let deletion else { return }
        do { try JournalStore.delete([deletion], in: context) }
        catch { errorMessage = error.localizedDescription }
        self.deletion = nil
    }
}
