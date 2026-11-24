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
    @State private var cardNote: BookNote?

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
            .sheet(item: $cardNote) { QuoteCardSheet(note: $0).environment(\.theme, theme) }
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
            let total = sessions.filter { !($0.book?.isAudio ?? false) }.reduce(0) { $0 + $1.pages }
            let listened = sessions.filter { $0.book?.isAudio ?? false }.reduce(0) { $0 + $1.pages }
            Text("\(sessions.count) sessions · \(total.formatted()) pages" + (listened > 0 ? " · \(Stats.formatMinutes(Double(listened))) listened" : "") + " all time").font(.footnote).foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        ForEach(groups, id: \.key) { group in
            Section {
                ForEach(group.value) { s in
                    HStack(spacing: 12) {
                        CoverView(data: s.book?.coverData, title: s.book?.title ?? "?", width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                if s.book?.isAudio ?? false { Image(systemName: "headphones").font(.caption.weight(.bold)).foregroundStyle(theme.brandText) }
                                Text(s.book?.title ?? "Deleted book").font(.subheadline.weight(.semibold)).lineLimit(1)
                            }
                            Text(s.startedAt.formatted(date: .omitted, time: .shortened) + " · " + s.snap.rangeText
                                 + (s.minutes.map { " · \($0) min" } ?? ""))
                                .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        Text(s.snap.gainText).font(.system(.subheadline, design: .rounded, weight: .black))
                            .foregroundStyle(theme.brandText)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(theme.brandText.opacity(0.12), in: Capsule())
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { Library.delete(ctx, s) }
                    }
                }
            } header: {
                HStack {
                    Text(Day.long(group.key))
                    Spacer()
                    Text(dayTotal(group.value)).monospacedDigit()
                }
            }
        }
    }

    /// "19 pages · 45 min listened" for one day's sessions.
    private func dayTotal(_ list: [ReadingSession]) -> String {
        let pages = list.filter { !($0.book?.isAudio ?? false) }.reduce(0) { $0 + $1.pages }
        let listened = list.filter { $0.book?.isAudio ?? false }.reduce(0) { $0 + $1.pages }
        var parts: [String] = []
        if pages > 0 { parts.append("\(pages) \(pages == 1 ? "page" : "pages")") }
        if listened > 0 { parts.append("\(Stats.formatMinutes(Double(listened))) listened") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var noteRows: some View {
        let q = search.trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? notes : notes.filter { $0.text.localizedCaseInsensitiveContains(q) || ($0.book?.title ?? "").localizedCaseInsensitiveContains(q) }
        if list.isEmpty {
            Text(q.isEmpty ? "Quotes and thoughts you add to your books show up here." : "No notes match “\(q)”.")
                .foregroundStyle(.secondary)
        }
        ForEach(list) { note in
            NoteRow(note: note, showBook: true, onShare: { cardNote = note })
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .swipeActions {
                    Button("Delete", role: .destructive) { ctx.delete(note); Library.save(ctx) }
                }
        }
    }
}
