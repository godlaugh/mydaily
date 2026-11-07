import SwiftUI

struct JournalComposeView: View {
    var parent: MemoEntity? = nil
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var errorMessage: String?
    @State private var discard = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let parent {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "arrow.turn.down.right").foregroundStyle(JournalTheme.secondary).accessibilityHidden(true)
                            Text(parent.journalTitle).font(JournalTheme.headline)
                        }
                        Divider().overlay(JournalTheme.line)
                    }
                    TextField(JournalText.string(parent == nil ? "placeholder" : "append_placeholder"), text: $content, axis: .vertical)
                        .lineLimit(10...).font(.body).lineSpacing(7)
                        .focused($focused)
                        .accessibilityLabel(JournalText.string("thought"))
                        .accessibilityIdentifier("journal_note_input")
                }
                .padding(24).frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(JournalTheme.paper)
            .foregroundStyle(JournalTheme.ink)
            .navigationTitle(JournalText.string(parent == nil ? "write" : "continue"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L(.cancel)) { content.isEmpty ? dismiss() : (discard = true) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L(.save), action: save)
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("journal_save_note")
                }
            }
            .confirmationDialog(JournalText.string("discard"), isPresented: $discard, titleVisibility: .visible) {
                Button(JournalText.string("discard_action"), role: .destructive) { dismiss() }
                Button(L(.cancel), role: .cancel) { }
            }
            .alert(JournalText.string("error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { } message: { Text(errorMessage ?? "") }
        }
        .interactiveDismissDisabled(!content.isEmpty)
        .onAppear { focused = true }
    }

    private func save() {
        do {
            try JournalStore.add(content: content, parentID: parent?.objectID, in: context)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
