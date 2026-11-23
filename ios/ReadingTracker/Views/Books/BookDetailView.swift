import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Bindable var book: Book

    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var noteDraft: NoteDraft?
    @State private var cardNote: BookNote?
    @State private var editing = false
    @State private var askDelete = false

    private var notes: [BookNote] { book.notes.sorted { $0.createdAt.seconds > $1.createdAt.seconds } }
    private var sessions: [ReadingSession] { book.sessions.sorted { $0.startedAt.seconds > $1.startedAt.seconds } }

    var body: some View {
        let pace = Stats.pace(book.snap, sessions: book.sessions.map(\.snap), now: .now)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    if store.access.canEdit {
                        CoverButton(cover: Binding(get: { book.coverData }, set: { book.coverData = $0; Library.save(ctx) }),
                                    title: book.title, author: book.author, isbn: book.isbn, width: 96)
                    } else {
                        CoverView(data: book.coverData, title: book.title, width: 96)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title).font(.system(.title2, design: .rounded, weight: .heavy))
                        if !book.author.isEmpty { Text(book.author).foregroundStyle(.secondary) }
                        Text(statusLine).font(.subheadline.weight(.semibold)).foregroundStyle(theme.brandText)
                    }
                }

                if book.status != .wantToRead {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressBar(fraction: pace.fraction, color: theme.brand)
                        Text(progressLine(pace)).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Your rating")
                    StarRating(rating: Binding(get: { book.rating }, set: { book.rating = $0; Library.save(ctx) }),
                               size: 30, color: theme.brandText, editable: store.access.canEdit)
                    Text(book.rating == nil ? "Optional. Tap a star; tap again to clear." : "Tap the same star again to clear.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("rating")

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(text: "Notes", trailing: notes.isEmpty ? nil : "\(notes.count)")
                    }
                    HStack(spacing: 8) {
                        Button { add(.quote) } label: { Label("Quote", systemImage: "quote.opening") }
                            .buttonStyle(PillButton(kind: .brand)).accessibilityIdentifier("addQuote")
                        Button { add(.thought) } label: { Label("Thought", systemImage: "lightbulb") }
                            .buttonStyle(PillButton(kind: .outline)).accessibilityIdentifier("addThought")
                    }
                    if notes.isEmpty {
                        EmptyCard(text: "Capture quotes you love and thoughts as you read. You can scan a quote straight from the page.")
                    }
                    ForEach(notes) { note in
                        NoteRow(note: note, onShare: { cardNote = note })
                            .onTapGesture { if store.access.canEdit { noteDraft = NoteDraft(note: note, kind: note.kind) } }
                            .contextMenu {
                                Button { cardNote = note } label: { Label("Share as a picture", systemImage: "photo") }
                                Button { UIPasteboard.general.string = note.text } label: { Label("Copy", systemImage: "doc.on.doc") }
                                ShareLink(item: shareText(note)) { Label("Share", systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { ctx.delete(note); Library.save(ctx) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }

                if !sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle(text: "Sessions", trailing: "\(sessions.count)")
                        ForEach(sessions) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                                    Text("p. \(s.startPage) → \(s.endPage)" + (s.minutes.map { " · \($0) min" } ?? ""))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("+\(s.pages)").font(.system(.headline, design: .rounded, weight: .black)).foregroundStyle(theme.brandText)
                            }
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                }

                actions
            }
            .padding(16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { if store.access.canEdit { editing = true } else { router.showPaywall = true } }
            }
        }
        .sheet(item: $cardNote) { QuoteCardSheet(note: $0).environment(\.theme, theme) }
        .sheet(item: $noteDraft) { draft in
            NoteEditor(book: book, draft: draft).environment(\.theme, theme)
        }
        .sheet(isPresented: $editing) { EditBookSheet(book: book).environment(\.theme, theme) }
        .confirmationDialog("Delete \(book.title)?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Delete book, sessions and notes", role: .destructive) {
                dismiss()
                Library.delete(ctx, book)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 8) {
            switch book.status {
            case .wantToRead:
                Button("Start reading") { guarded { Library.startReading(ctx, book) } }.buttonStyle(PillButton(kind: .highlight, big: true))
            case .finished, .dnf:
                Button("Back to reading") { guarded { Library.startReading(ctx, book) } }.buttonStyle(PillButton(kind: .outline, big: true))
            case .reading:
                EmptyView()
            }
            Button("Delete book", role: .destructive) { askDelete = true }
                .font(.subheadline.weight(.semibold)).padding(.top, 6)
        }
    }

    private func progressLine(_ pace: Pace) -> String {
        switch book.status {
        case .finished:
            let took = Stats.daysTaken(book.snap, sessions: book.sessions.map(\.snap))
            return "All \(book.totalPages.formatted()) pages read" + (took.map { " · took \($0) \($0 == 1 ? "day" : "days")" } ?? "")
        case .dnf:
            return "Stopped on page \(pace.current) of \(book.totalPages)"
        default:
            return "Page \(pace.current) of \(book.totalPages) · \(pace.line)"
        }
    }

    private var statusLine: String {
        switch book.status {
        case .wantToRead: return "Want to read · \(book.totalPages) pages"
        case .reading: return "On the go"
        case .finished: return "Finished" + (book.finishedDay.map { " \(Day.short($0))" } ?? "")
        case .dnf: return "Written off" + (book.dnfDay.map { " \(Day.short($0))" } ?? "")
        }
    }

    private func add(_ kind: BookNote.Kind) {
        guarded { noteDraft = NoteDraft(note: nil, kind: kind) }
    }

    private func guarded(_ action: () -> Void) {
        if store.access.canEdit { action() } else { router.showPaywall = true }
    }

    private func shareText(_ note: BookNote) -> String {
        let quote = note.kind == .quote ? "“\(note.text)”" : note.text
        return "\(quote)\n— \(book.title)" + (book.author.isEmpty ? "" : ", \(book.author)") + (note.page.map { ", p. \($0)" } ?? "")
    }
}

struct NoteRow: View {
    let note: BookNote
    var showBook = false
    /// Shows a share button that turns the note into a picture.
    var onShare: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: note.kind.icon).foregroundStyle(theme.brandText)
                Text(note.kind.title).font(.caption.weight(.bold)).foregroundStyle(theme.brandText)
                if let p = note.page { Text("· p. \(p)").font(.caption).foregroundStyle(.secondary) }
                if showBook, let b = note.book { Text("· \(b.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Text(note.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                if let onShare {
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up").font(.subheadline.weight(.semibold)).foregroundStyle(theme.brandText)
                            .padding(.leading, 4)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Share as a picture")
                    .accessibilityIdentifier("shareCard")
                }
            }
            Text(note.kind == .quote ? "“\(note.text)”" : note.text)
                .font(note.kind == .quote ? .body.italic() : .body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .card(theme.surface, radius: 14, padding: 14)
    }
}

struct NoteDraft: Identifiable {
    var id = UUID()
    var note: BookNote?
    var kind: BookNote.Kind
}

struct NoteEditor: View {
    let book: Book
    let draft: NoteDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @State private var kind: BookNote.Kind = .quote
    @State private var text = ""
    @State private var pageText = ""
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(BookNote.Kind.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented)
                Section {
                    TextField(kind == .quote ? "The words you want to keep" : "What you're thinking", text: $text, axis: .vertical)
                        .lineLimit(4...14)
                        .accessibilityIdentifier("noteText")
                    if kind == .quote {
                        Button { scanning = true } label: { Label("Scan from the page", systemImage: "text.viewfinder") }
                            .disabled(!ScannerView.isAvailable)
                    }
                }
                LabeledContent("Page (optional)") {
                    TextField("", text: $pageText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle(draft.note == nil ? "New \(kind.title.lowercased())" : "Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("noteSave")
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                QuoteScanSheet { captured in
                    text = text.isEmpty ? captured : text + " " + captured
                }
            }
            .onAppear {
                kind = draft.kind
                if let n = draft.note {
                    text = n.text
                    pageText = n.page.map(String.init) ?? ""
                } else if book.status == .reading {
                    pageText = "\(book.currentPage)"
                }
            }
        }
    }

    private func save() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let page = Int(trimming: pageText)
        if let n = draft.note {
            n.kind = kind
            n.text = clean
            n.page = page
        } else {
            ctx.insert(BookNote(book: book, kind: kind, text: clean, page: page))
        }
        Library.save(ctx)
        dismiss()
    }
}

struct EditBookSheet: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @State private var title = ""
    @State private var author = ""
    @State private var pagesText = ""
    @State private var startText = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Book name", text: $title)
                TextField("Author", text: $author)
                LabeledContent("Number of pages") { TextField("", text: $pagesText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                LabeledContent("Started on page") { TextField("", text: $startText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Edit book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.bold) }
            }
            .onAppear {
                title = book.title
                author = book.author
                pagesText = "\(book.totalPages)"
                startText = "\(book.startPage)"
            }
        }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { error = "Add the book name."; return }
        guard let pages = Int(trimming: pagesText), pages > 0 else { error = "Number of pages should be 1 or more."; return }
        let start = Int(trimming: startText) ?? 0
        guard start >= 0, start < pages else { error = "The starting page should be between 0 and \(pages - 1)."; return }
        book.title = name
        book.author = author.trimmingCharacters(in: .whitespaces)
        book.totalPages = pages
        book.startPage = start
        Library.save(ctx)
        dismiss()
    }
}

/// Offered when a book is finished: an optional rating and a closing thought.
struct RateBookSheet: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @State private var rating: Double?
    @State private var thought = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("🎉").font(.system(size: 56))
            Text("You finished \(book.title)!").font(.system(.title2, design: .rounded, weight: .heavy)).multilineTextAlignment(.center)
            Text("How was it? Both are optional.").foregroundStyle(.secondary)
            StarRating(rating: $rating, size: 38, color: theme.brandText)
            TextField("A closing thought", text: $thought, axis: .vertical)
                .lineLimit(2...5)
                .padding(12)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
            Button("Save") {
                book.rating = rating
                let t = thought.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { ctx.insert(BookNote(book: book, kind: .thought, text: t)) }
                Library.save(ctx)
                dismiss()
            }
            .buttonStyle(PillButton(kind: .brand, big: true))
            Button("Skip") { dismiss() }.foregroundStyle(.secondary)
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .onAppear { rating = book.rating }
    }
}
