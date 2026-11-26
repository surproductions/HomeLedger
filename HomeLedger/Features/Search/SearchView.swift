import SwiftData
import SwiftUI

/// Global search plus the "Ask" assistant. Both run locally over the user's records only.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var assets: [Asset]
    @Query private var rooms: [Room]
    @Query private var documents: [DocumentRecord]
    @Query private var tasks: [MaintenanceTask]
    @Query private var services: [ServiceRecord]
    @Query private var expenses: [Expense]

    @State private var query = ""
    @State private var mode: Mode = .ask
    @State private var answers: [AssistantAnswer] = []
    @State private var path: [RecordRef] = []
    @FocusState private var focused: Bool

    enum Mode: String, CaseIterable, Identifiable { case ask = "Ask", search = "Search"; var id: String { rawValue } }

    private var corpus: SearchCorpus {
        SearchCorpus(assets: assets, rooms: rooms, documents: documents, tasks: tasks, services: services, expenses: expenses)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Picker("Mode", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("search.mode")
                    HStack(spacing: 10) {
                        Image(systemName: mode == .ask ? "sparkle.magnifyingglass" : "magnifyingglass").foregroundStyle(Theme.inkTertiary)
                        TextField(mode == .ask ? "Ask about your home…" : "Search everything", text: $query)
                            .focused($focused)
                            .submitLabel(mode == .ask ? .send : .search)
                            .onSubmit { if mode == .ask { ask(query) } }
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("search.field")
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkTertiary) }
                                .accessibilityLabel("Clear")
                        }
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
                }
                .padding(Theme.gutter)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if mode == .ask { askContent } else { searchContent }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 24)
                }
            }
            .canvasBackground()
            .navigationTitle(mode == .ask ? "Ask HomeLedger" : "Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: RecordRef.self) { RecordRefView(ref: $0) }
            .navigationDestination(for: AppRoute.self) { AppRouteView(route: $0) }
            .onAppear { if !LaunchOptions.current.isUITesting { focused = true } }
        }
    }

    @ViewBuilder
    private var askContent: some View {
        if answers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Answers come only from your records, on this iPhone. This is a rule-based assistant — it isn't a chatbot and won't guess.", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(Theme.inkSecondary)
                SectionHeader(title: "Try asking")
                ForEach(QueryEngine.examples, id: \.self) { example in
                    Button { query = example; ask(example) } label: {
                        HStack {
                            Text(example).font(.subheadline).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.brand)
                        }
                        .card(padding: 12, radius: Theme.radiusS)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        ForEach(answers) { answer in
            VStack(alignment: .leading, spacing: 10) {
                Text(answer.question).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                VStack(alignment: .leading, spacing: 10) {
                    Label(answer.text, systemImage: answer.found ? "checkmark.circle" : "questionmark.circle")
                        .font(.body).foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("assistant.answer")
                    if !answer.records.isEmpty {
                        Text("Supporting records").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                        ForEach(answer.records.prefix(12)) { ref in
                            NavigationLink(value: ref) {
                                RecordRow(symbol: ref.symbol, tint: Theme.brand, title: ref.title, subtitle: "\(ref.kindLabel) · \(ref.subtitle)")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .card(padding: 14)
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        let groups = SearchService().search(query, in: corpus)
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyStateView(symbol: "magnifyingglass", title: "Search everything", message: "Items, rooms, documents (including recognized text), warranties, repairs, maintenance and expenses.")
        } else if groups.isEmpty {
            EmptyStateView(symbol: "magnifyingglass", title: "No results", message: "Nothing matches “\(query)”.")
        } else {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: group.title)
                    ListCard {
                        ForEach(Array(group.results.enumerated()), id: \.element.id) { i, ref in
                            if i > 0 { RowDivider() }
                            NavigationLink(value: ref) { RecordRow(symbol: ref.symbol, tint: Theme.brand, title: ref.title, subtitle: ref.subtitle) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        answers.insert(QueryEngine().answer(trimmed, corpus: corpus), at: 0)
        query = ""
    }
}
