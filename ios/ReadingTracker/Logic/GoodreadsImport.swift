import Foundation
import SwiftData

/// Imports a Goodreads library export (My Books → Tools → Import and export → Export Library).
enum GoodreadsImport {
    enum Shelf: String, CaseIterable, Identifiable, Sendable {
        case read, reading, toRead
        var id: String { rawValue }
        var title: String {
            switch self {
            case .read: return "Read"
            case .reading: return "Currently reading"
            case .toRead: return "Want to read"
            }
        }
    }

    struct Item: Equatable, Sendable {
        var goodreadsID: String
        var title: String
        var author: String
        var isbn: String?
        /// nil when Goodreads doesn't know (or for audiobooks, whose length it doesn't export).
        var pages: Int?
        var rating: Double?
        var shelf: Shelf
        /// "yyyy-MM-dd"
        var dayRead: String?
        var dateAdded: Date?
        var review: String?
        var isAudio: Bool
    }

    struct Result: Equatable {
        var added = 0, updated = 0, skipped = 0
        /// Books that could use a cover or a page count from the catalogues.
        var toEnrich: [String] = []
    }

    enum Problem: LocalizedError {
        case notGoodreads
        var errorDescription: String? {
            "That doesn't look like a Goodreads export. It should be the file called goodreads_library_export.csv."
        }
    }

    // MARK: reading the file

    /// Splits CSV text into rows of fields, handling quotes, doubled quotes, and commas and line breaks inside quotes.
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        var chars = text.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? chars.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let next = chars.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func parse(_ data: Data) throws -> [Item] {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw Problem.notGoodreads }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let all = rows(text)
        guard let header = all.first else { throw Problem.notGoodreads }
        var column: [String: Int] = [:]
        for (i, name) in header.enumerated() { column[name.trimmingCharacters(in: .whitespaces).lowercased()] = i }
        guard let titleAt = column["title"], column["exclusive shelf"] != nil || column["bookshelves"] != nil else { throw Problem.notGoodreads }

        func value(_ row: [String], _ name: String) -> String {
            guard let i = column[name], i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var items: [Item] = []
        for (n, row) in all.dropFirst().enumerated() {
            guard titleAt < row.count else { continue }
            let title = value(row, "title")
            guard !title.isEmpty else { continue }
            let shelfText = value(row, "exclusive shelf").lowercased()
            let shelf: Shelf = shelfText == "currently-reading" ? .reading : shelfText == "to-read" ? .toRead : .read
            let binding = value(row, "binding").lowercased()
            let isAudio = binding.contains("audio") || binding.contains("audible")
            let pages = Int(value(row, "number of pages")).flatMap { $0 > 0 ? $0 : nil }
            let rating = Double(value(row, "my rating")).flatMap { $0 > 0 ? min(5, $0) : nil }
            let isbn = ISBN.normalize(clean(value(row, "isbn13"))) ?? ISBN.normalize(clean(value(row, "isbn")))
            let review = plain(value(row, "my review"))
            let id = value(row, "book id")
            items.append(Item(goodreadsID: id.isEmpty ? "row\(n)" : id,
                              title: String(title.prefix(200)), author: String(value(row, "author").prefix(200)),
                              isbn: isbn, pages: isAudio ? nil : pages, rating: rating, shelf: shelf,
                              dayRead: day(value(row, "date read")), dateAdded: day(value(row, "date added")).map(Day.date),
                              review: review.isEmpty ? nil : review, isAudio: isAudio))
        }
        return items
    }

    /// Goodreads writes ISBNs as ="9780141439518" so spreadsheets keep the leading zeros.
    private static func clean(_ s: String) -> String { s.filter { $0.isNumber || $0 == "X" || $0 == "x" } }

    /// "2023/05/14" (or with dashes) → "2023-05-14".
    private static func day(_ s: String) -> String? {
        let parts = s.split(whereSeparator: { $0 == "/" || $0 == "-" }).compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 1900, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2])
    }

    /// Reviews come with HTML line breaks and tags.
    private static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">")] { t = t.replacingOccurrences(of: a, with: b) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: adding to the library

    static func uid(_ item: Item) -> String { "goodreads-\(item.goodreadsID)" }

    private static func key(_ title: String, _ author: String) -> String {
        (title + "|" + author).lowercased().filter { $0.isLetter || $0.isNumber || $0 == "|" }
    }

    /// Adds the chosen shelves. Books imported before are updated; books already in the library some other way
    /// (same ISBN, or same title and author) are left alone.
    @MainActor
    static func apply(_ items: [Item], shelves: Set<Shelf>, into ctx: ModelContext, now: Date = .now) -> Result {
        var result = Result()
        let existing = (try? ctx.fetch(FetchDescriptor<Book>())) ?? []
        var byUID: [String: Book] = [:], isbns = Set<String>(), names = Set<String>()
        for b in existing {
            byUID[b.uid] = b
            if !b.uid.hasPrefix("goodreads-") {
                if let i = b.isbn { isbns.insert(i) }
                names.insert(key(b.title, b.author))
            }
        }
        let noteIDs = Set(((try? ctx.fetch(FetchDescriptor<BookNote>())) ?? []).map(\.uid))

        for item in items where shelves.contains(item.shelf) {
            let id = uid(item)
            let book: Book
            if let have = byUID[id] {
                book = have
                result.updated += 1
            } else if (item.isbn.map(isbns.contains) ?? false) || names.contains(key(item.title, item.author)) {
                result.skipped += 1
                continue
            } else {
                book = Book(uid: id, title: item.title, author: item.author, isbn: item.isbn, totalPages: item.pages ?? 0,
                            status: .wantToRead, addedAt: item.dateAdded ?? now, lastAt: item.dateAdded ?? now, isAudio: item.isAudio)
                ctx.insert(book)
                byUID[id] = book
                result.added += 1
            }
            book.title = item.title
            book.author = item.author
            if let isbn = item.isbn { book.isbn = isbn }
            if let pages = item.pages, book.totalPages <= 0 { book.totalPages = pages }
            if let rating = item.rating { book.rating = rating }
            // Only set where the book stands if you haven't started logging it here.
            if (book.sessions ?? []).isEmpty {
                switch item.shelf {
                case .read:
                    book.status = .finished
                    book.finishedDay = item.dayRead ?? Day.key(item.dateAdded ?? now)
                    book.lastAt = Day.date(book.finishedDay ?? Day.key(now))
                case .reading:
                    book.status = .reading
                    book.finishedDay = nil
                case .toRead:
                    book.status = .wantToRead
                    book.finishedDay = nil
                }
            }
            if let review = item.review, !noteIDs.contains("goodreads-review-\(item.goodreadsID)") {
                ctx.insert(BookNote(uid: "goodreads-review-\(item.goodreadsID)", book: book, kind: .thought, text: String(review.prefix(4000)),
                                    createdAt: item.dayRead.map(Day.date) ?? item.dateAdded ?? now))
            }
            if book.isbn != nil, book.coverData == nil || book.totalPages <= 0 { result.toEnrich.append(id) }
        }
        Library.save(ctx)
        return result
    }
}

/// After an import, fetches covers (and missing page counts) by ISBN in the background, one book at a time.
@MainActor
@Observable
final class GoodreadsEnricher {
    static let shared = GoodreadsEnricher()
    private(set) var total = 0
    private(set) var done = 0
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }
    var progressText: String { "Fetching covers: \(done) of \(total)" }

    func start(_ uids: [String], in container: ModelContainer) {
        task?.cancel()
        total = uids.count
        done = 0
        guard !uids.isEmpty else { task = nil; return }
        task = Task { @MainActor in
            let ctx = container.mainContext
            for uid in uids {
                if Task.isCancelled { break }
                if let book = Library.book(ctx, uid: uid), let isbn = book.isbn {
                    var fallback: URL?
                    if book.totalPages <= 0 || book.coverData == nil, let found = await BookLookup.find(isbn: isbn) {
                        if book.totalPages <= 0, !book.isAudio, let pages = found.pages, pages > 0 { book.totalPages = pages }
                        fallback = found.coverURL
                    }
                    if book.coverData == nil, let cover = await BookLookup.cover(isbn: isbn, fallback: fallback) {
                        book.coverData = cover
                    }
                }
                done += 1
                if done % 10 == 0 { try? ctx.save() }
                try? await Task.sleep(for: .milliseconds(250))   // be gentle with the free catalogues
            }
            try? ctx.save()
            Library.refreshWidgets(ctx)
            task = nil
        }
    }

    func cancel() { task?.cancel(); task = nil }
}
