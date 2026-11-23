import SwiftUI
import SwiftData

struct LogView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case sessions = "Sessions", notes = "Notes"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Query(sort: \ReadingSession.startedAt, order: .reverse) private var sessions: [ReadingSession]
    @Query(sort: \BookNote.createdAt, order: .reverse) private var notes: [BookNote]
    @State private var mode: Mode = .sessions
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))

                if mode == .sessions { sessionRows } else { noteRows }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reading log")
            .searchable(text: $search, prompt: mode == .sessions ? "Search books" : "Search quotes and thoughts")
        }
    }

    private var filteredSessions: [ReadingSession] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sessions }
        return sessions.filter { ($0.book?.title ?? "").localizedCaseInsensitiveContains(q) }
    }

    @ViewBuilder private var sessionRows: some View {
        let groups = Dictionary(grouping: filteredSessions, by: \.day).sorted { $0.key > $1.key }
        if groups.isEmpty {
            Text("Every session you log shows up here.").foregroundStyle(.secondary)
        } else {
            let total = sessions.reduce(0) { $0 + $1.pages }
            Text("\(sessions.count) sessions · \(total.formatted()) pages all time").font(.footnote).foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        ForEach(groups, id: \.key) { group in
            Section(Day.long(group.key)) {
                ForEach(group.value) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.book?.title ?? "Deleted book").font(.subheadline.weight(.semibold))
                            Text(s.startedAt.formatted(date: .omitted, time: .shortened) + " · p. \(s.startPage) → \(s.endPage)"
                                 + (s.minutes.map { " · \($0) min" } ?? ""))
                                .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        Text("+\(s.pages)").font(.system(.headline, design: .rounded, weight: .black)).foregroundStyle(theme.brandText)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { Library.delete(ctx, s) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var noteRows: some View {
        let q = search.trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? notes : notes.filter { $0.text.localizedCaseInsensitiveContains(q) || ($0.book?.title ?? "").localizedCaseInsensitiveContains(q) }
        if list.isEmpty {
            Text(q.isEmpty ? "Quotes and thoughts you add to your books show up here." : "No notes match “\(q)”.")
                .foregroundStyle(.secondary)
        }
        ForEach(list) { note in
            NoteRow(note: note, showBook: true)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .swipeActions {
                    Button("Delete", role: .destructive) { ctx.delete(note); Library.save(ctx) }
                }
        }
    }
}
