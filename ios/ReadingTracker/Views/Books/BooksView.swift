import SwiftUI
import SwiftData

struct BooksView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case reading = "Reading", wantToRead = "Want to read", shelf = "Shelf"
        var id: String { rawValue }
    }

    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Query(sort: \Book.lastAt, order: .reverse) private var books: [Book]
    @Query private var sessions: [ReadingSession]
    @State private var segment: Segment = .reading
    @State private var shelf: BookStatus = .finished
    @State private var showAdd = false

    var body: some View {
        let snaps = sessions.map(\.snap)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Show", selection: $segment) {
                        ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch segment {
                    case .reading: readingList(snaps)
                    case .wantToRead: wantList
                    case .shelf: shelfList(snaps)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Books")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if store.access.canEdit { showAdd = true } else { router.showPaywall = true }
                    } label: { Label("Add a book", systemImage: "plus.circle.fill") }
                    .accessibilityIdentifier("addBook")
                }
            }
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
            .sheet(isPresented: $showAdd) {
                AddBookSheet(defaultStatus: segment == .wantToRead ? .wantToRead : .reading)
                    .environment(\.theme, theme)
            }
        }
    }

    @ViewBuilder private func readingList(_ snaps: [SessionSnap]) -> some View {
        let list = books.filter { $0.status == .reading }
        if list.isEmpty {
            EmptyCard(text: "Nothing on the go. Tap + to add a book, or start one from Want to read.")
        }
        ForEach(list) { book in
            BookCard(book: book, sessions: snaps)
        }
    }

    @ViewBuilder private var wantList: some View {
        let list = books.filter { $0.status == .wantToRead }.sorted { $0.addedAt.seconds > $1.addedAt.seconds }
        if list.isEmpty {
            EmptyCard(text: "Books you'd like to read go here. Tap + and choose Want to read.")
        }
        ForEach(list) { book in
            HStack(spacing: 12) {
                NavigationLink(value: book) {
                    HStack(spacing: 12) {
                        CoverView(data: book.coverData, title: book.title, width: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title).font(.headline).multilineTextAlignment(.leading)
                            Text([book.author, book.snap.lengthText].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                Button("Start") {
                    guard store.access.canEdit else { router.showPaywall = true; return }
                    Library.startReading(ctx, book)
                    segment = .reading
                }
                .buttonStyle(PillButton(kind: .highlight))
                .frame(width: 90)
            }
            .card(theme.surface, radius: 16, padding: 12)
        }
    }

    @ViewBuilder private func shelfList(_ snaps: [SessionSnap]) -> some View {
        let fin = books.filter { $0.status == .finished }.sorted { ($0.finishedDay ?? "") > ($1.finishedDay ?? "") }
        let dnf = books.filter { $0.status == .dnf }.sorted { ($0.dnfDay ?? "") > ($1.dnfDay ?? "") }
        Picker("Shelf", selection: $shelf) {
            Text("Finished (\(fin.count))").tag(BookStatus.finished)
            Text("Written off (\(dnf.count))").tag(BookStatus.dnf)
        }
        .pickerStyle(.segmented)
        let list = shelf == .finished ? fin : dnf
        if list.isEmpty {
            EmptyCard(text: shelf == .finished ? "Finished books land here. Log the last page, or tap Finished it on a book."
                                               : "Books you give up on land here. The pages you read still count.")
        }
        ForEach(list) { book in
            NavigationLink(value: book) { ShelfRow(book: book, sessions: snaps) }
                .buttonStyle(.plain)
        }
    }
}

struct ShelfRow: View {
    let book: Book
    let sessions: [SessionSnap]
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverView(data: book.coverData, title: book.title, width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.headline)
                    .strikethrough(book.status == .dnf, color: theme.brand)
                    .multilineTextAlignment(.leading)
                if book.status == .finished, book.rating != nil {
                    StarRating(rating: .constant(book.rating), size: 13, color: theme.brandText, editable: false)
                }
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .card(theme.surface, radius: 16, padding: 12)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !book.author.isEmpty { parts.append(book.author) }
        if book.status == .dnf {
            let cp = book.currentPage
            let pct = Int((Double(cp) / Double(max(1, book.totalPages)) * 100).rounded())
            parts.append(book.isAudio ? "stopped \(pct)% through" : "stopped on page \(cp) of \(book.totalPages) (\(pct)%)")
            if let d = book.dnfDay { parts.append(Day.short(d)) }
            if let n = book.dnfNote { parts.append("“\(n)”") }
        } else {
            parts.append(book.snap.lengthText)
            if let d = book.finishedDay { parts.append("finished \(Day.short(d))") }
            if let days = Stats.daysTaken(book.snap, sessions: sessions) { parts.append("took \(days) \(days == 1 ? "day" : "days")") }
        }
        return parts.joined(separator: " · ")
    }
}
