import SwiftUI
import CoreData

struct TimelineView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vm: TimelineViewModel
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: MemoEntity.all) private var entries
    let open: (MemoEntity) -> Void
    @State private var groupToDelete: JournalGroup?
    @State private var errorMessage: String?
    @State private var deleteSelection = false

    private var groups: [JournalGroup] { JournalGroup.grouped(Array(entries)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 0) {
                        Text("alog").foregroundStyle(JournalTheme.ink)
                        Text(".").foregroundStyle(JournalTheme.accent)
                    }
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("ALog")
                    Spacer()
                    if vm.isMultiSelectMode {
                        Button(L(.cancel), action: cancelSelection).frame(minHeight: 44)
                            .accessibilityIdentifier("journal_cancel_selection")
                        Button(role: .destructive) { deleteSelection = true } label: {
                            Label(L(.delete), systemImage: "trash").labelStyle(.iconOnly)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .disabled(vm.selectedMemos.isEmpty)
                        .accessibilityIdentifier("journal_delete_selection")
                    } else {
                        Button { appState.startCreatingNote() } label: {
                            Label(JournalText.string("write"), systemImage: "square.and.pencil")
                                .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("journal_write")
                        Button { appState.activeSheet = .settings } label: {
                            Label(L(.settings_title), systemImage: "slider.horizontal.3")
                                .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("journal_settings")
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 30)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(JournalText.string("title")).font(.largeTitle.bold())
                        Text(JournalText.string("recent")).font(.caption).foregroundStyle(JournalTheme.secondary)
                    }
                    Spacer()
                    Text(Date(), format: .dateTime.month().day()).font(.caption).foregroundStyle(JournalTheme.secondary)
                }
                .padding(.bottom, 26)
                if groups.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(JournalText.string("empty_title")).font(JournalTheme.headline)
                        Text(JournalText.string("empty_body")).font(.body).foregroundStyle(JournalTheme.secondary)
                    }
                    .padding(.vertical, 50)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            HStack(alignment: .top, spacing: 12) {
                                if vm.isMultiSelectMode {
                                    Button { vm.toggleMemoSelection(group.first) } label: {
                                        Image(systemName: vm.selectedMemos.contains(group.first) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3).frame(width: 44, height: 44).contentShape(Rectangle())
                                    }
                                    .accessibilityLabel(group.title)
                                    .accessibilityAddTraits(vm.selectedMemos.contains(group.first) ? .isSelected : [])
                                    .accessibilityIdentifier("journal_select_\(group.first.id ?? "")")
                                }
                                JournalRow(group: group) {
                                    if vm.isMultiSelectMode { vm.toggleMemoSelection(group.first) }
                                    else { open(group.first) }
                                }
                            }
                                .contextMenu {
                                    Button { open(group.first) } label: { Label(JournalText.string("detail"), systemImage: "book") }
                                    Button { appState.activeSheet = .appendMemo(group.first) } label: { Label(JournalText.string("continue_text"), systemImage: "square.and.pencil") }
                                    Button {
                                        vm.selectedMemos = [group.first]
                                        vm.isMultiSelectMode = true
                                    } label: { Label(JournalText.string("select"), systemImage: "checkmark.circle") }
                                    .accessibilityIdentifier("journal_begin_selection")
                                    Button(role: .destructive) { groupToDelete = group } label: { Label(L(.delete), systemImage: "trash") }
                                }
                            if group.id != groups.last?.id {
                                Rectangle().fill(JournalTheme.line).frame(height: 1).padding(.vertical, 24)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(JournalTheme.paper)
        .safeAreaInset(edge: .bottom, spacing: 0) { JournalBottomBar() }
        .toolbar(.hidden, for: .navigationBar)
        .task { appState.checkMicPermission() }
        .confirmationDialog(JournalText.string("delete_selected"), isPresented: $deleteSelection, titleVisibility: .visible) {
            Button(L(.delete), role: .destructive) {
                let selected = groups.filter { vm.selectedMemos.contains($0.first) }.flatMap(\.entries)
                do { try JournalStore.delete(selected, in: context); cancelSelection() }
                catch { errorMessage = error.localizedDescription }
            }
        } message: { Text(JournalText.string("delete_selected_body")) }
        .confirmationDialog(JournalText.string("delete_thread"), isPresented: Binding(get: { groupToDelete != nil }, set: { if !$0 { groupToDelete = nil } }), titleVisibility: .visible) {
            Button(L(.delete), role: .destructive, action: deleteGroup)
            Button(L(.cancel), role: .cancel) { groupToDelete = nil }
        } message: {
            Text(String(format: JournalText.string("delete_thread_body"), groupToDelete?.entries.count ?? 0))
        }
        .alert(JournalText.string("error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { } message: {
            Text(errorMessage ?? "")
        }
    }

    private func deleteGroup() {
        guard let group = groupToDelete else { return }
        do { try JournalStore.delete(group.entries, in: context) }
        catch { errorMessage = error.localizedDescription }
        groupToDelete = nil
    }

    private func cancelSelection() {
        vm.selectedMemos.removeAll()
        vm.isMultiSelectMode = false
    }
}
