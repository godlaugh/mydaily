import SwiftUI

struct JournalRow: View {
    let group: JournalGroup
    let open: () -> Void
    @EnvironmentObject private var timeline: TimelineViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(group.first.journalDate).font(.caption).foregroundStyle(JournalTheme.secondary)
                if group.first.file != nil {
                    Text("·").foregroundStyle(JournalTheme.secondary).accessibilityHidden(true)
                    JournalAudioChip(memo: group.first)
                }
                Spacer(minLength: 0)
            }
            Button(action: open) {
                VStack(alignment: .leading, spacing: 13) {
                    Text(group.title)
                        .font(.headline)
                        .lineSpacing(5).foregroundStyle(JournalTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if timeline.transcribingMemos.contains(group.first) {
                        ProgressView(L(.transcribing)).font(.subheadline)
                    } else if !group.first.journalExcerpt.isEmpty {
                        Text(group.first.journalExcerpt).font(.subheadline).lineSpacing(6)
                            .foregroundStyle(JournalTheme.secondary).lineLimit(3)
                    }
                    if timeline.failedMemos[group.first] != nil {
                        Label(L(.try_again), systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(JournalTheme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("journal_entry_\(group.first.id ?? "")")
            if group.entries.count > 1 {
                Button(action: open) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.3.layers.3d").accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.latest.journalDate).font(.caption2)
                            Text(group.latest.journalPreview.isEmpty ? group.latest.journalTitle : group.latest.journalPreview)
                                .font(.caption).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption2).accessibilityHidden(true)
                    }
                    .foregroundStyle(JournalTheme.secondary)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: JournalText.string("thread_accessibility"), group.entries.count))
                .accessibilityIdentifier("journal_thread_\(group.first.id ?? "")")
            }
        }
    }
}
