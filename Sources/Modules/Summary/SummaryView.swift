import SwiftUI

struct SummaryView: View {
    @FetchRequest<SummaryEntity>(sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)]) private var items
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var config: Config

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Text(JournalText.string("tab_review")).font(.largeTitle.bold())
                        Spacer()
                        Button(action: createReview) {
                            Label(JournalText.string("create_review"), systemImage: "sparkles").labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                        }
                    }
                    if items.isEmpty {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(JournalText.string("review_empty")).font(JournalTheme.headline)
                            if !config.sumEnabled {
                                Text(JournalText.string("review_disabled")).font(.subheadline).foregroundStyle(JournalTheme.secondary)
                            }
                            Button(JournalText.string("create_review"), action: createReview)
                                .font(.subheadline).padding(.horizontal, 20).frame(minHeight: 48)
                                .background(JournalTheme.soft, in: Capsule())
                        }
                        .padding(.top, 35)
                    } else {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                VStack(alignment: .leading, spacing: 13) {
                                    if let date = item.createdAt {
                                        Text(date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(JournalTheme.secondary)
                                    }
                                    Text(item.viewTitle).font(JournalTheme.headline)
                                    Text(item.viewContent).font(.subheadline).lineSpacing(6)
                                        .foregroundStyle(JournalTheme.secondary).lineLimit(4)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(JournalTheme.line)
                        }
                    }
                }
                .padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(JournalTheme.paper)
            .safeAreaInset(edge: .bottom, spacing: 0) { JournalBottomBar() }
            .navigationDestination(for: SummaryEntity.self) { SummaryDetailView(summary: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func createReview() {
        if config.sumEnabled { appState.startSummarizing() }
        else { appState.activeSheet = .settings }
    }
}
