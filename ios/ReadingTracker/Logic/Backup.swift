import Foundation
import SwiftData

/// Reads and writes the backup file. The format is the web app's ("Save a backup"), so a backup
/// from the web tracker imports straight in. The iPhone app adds ratings and notes to the same file.
enum Backup {
    struct BookRecord: Equatable {
        var id: String, title: String, author: String, isbn: String?
        var totalPages: Int, startPage: Int, status: BookStatus
        var addedAt: Date, lastAt: Date
        var finishedDay: String?, dnfDay: String?, dnfNote: String?, rating: Double?
    }
    struct SessionRecord: Equatable {
        var id: String, bookID: String, startedAt: Date, day: String
        var startPage: Int, endPage: Int, minutes: Int?, createdAt: Date
    }
    struct NoteRecord: Equatable {
        var id: String, bookID: String, kind: BookNote.Kind, text: String, page: Int?, createdAt: Date
    }
    struct Contents: Equatable {
        var books: [BookRecord] = []
        var sessions: [SessionRecord] = []
        var notes: [NoteRecord] = []
        var totalPages: Int { sessions.reduce(0) { $0 + max(0, $1.endPage - $1.startPage) } }
    }

    enum Problem: LocalizedError {
        case notABackup
        var errorDescription: String? { "That file isn't a Pageturner or Reading Tracker backup." }
    }

    // MARK: reading

    static func parse(_ data: Data) throws -> Contents {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let books = root["books"] as? [String: Any],
              let sessions = root["sessions"] as? [String: Any] else { throw Problem.notABackup }
        var out = Contents()
        for (id, value) in books {
            guard let b = value as? [String: Any], let title = b["title"] as? String,
                  let total = int(b["totalPages"]), total > 0 else { continue }
            out.books.append(BookRecord(
                id: id, title: title, author: b["author"] as? String ?? "", isbn: b["isbn"] as? String,
                totalPages: total, startPage: int(b["startPage"]) ?? 0,
                status: BookStatus(rawValue: b["status"] as? String ?? "") ?? .reading,
                addedAt: date(b["addedAt"]) ?? .now, lastAt: date(b["lastAt"]) ?? date(b["addedAt"]) ?? .now,
                finishedDay: b["finishedDay"] as? String, dnfDay: b["dnfDay"] as? String, dnfNote: b["dnfNote"] as? String,
                rating: b["rating"] as? Double))
        }
        let bookIDs = Set(out.books.map(\.id))
        for (id, value) in sessions {
            guard let s = value as? [String: Any], let bookID = s["bookId"] as? String, bookIDs.contains(bookID),
                  let from = int(s["startPage"]), let to = int(s["endPage"]) else { continue }
            let started = date(s["startedAt"]) ?? (s["day"] as? String).map(Day.date) ?? .now
            out.sessions.append(SessionRecord(
                id: id, bookID: bookID, startedAt: started, day: s["day"] as? String ?? Day.key(started),
                startPage: from, endPage: to, minutes: int(s["minutes"]), createdAt: date(s["createdAt"]) ?? started))
        }
        for (id, value) in (root["notes"] as? [String: Any]) ?? [:] {
            guard let n = value as? [String: Any], let bookID = n["bookId"] as? String, bookIDs.contains(bookID),
                  let text = n["text"] as? String else { continue }
            out.notes.append(NoteRecord(id: id, bookID: bookID, kind: BookNote.Kind(rawValue: n["kind"] as? String ?? "") ?? .thought,
                                        text: text, page: int(n["page"]), createdAt: date(n["createdAt"]) ?? .now))
        }
        out.books.sort { $0.addedAt < $1.addedAt }
        out.sessions.sort { $0.startedAt < $1.startedAt }
        return out
    }

    /// Adds the backup to the library. Books already in the library (same id) are replaced.
    @MainActor
    static func restore(_ contents: Contents, into ctx: ModelContext) {
        // Remove anything being replaced first, and commit that, so the new copies don't clash with the old ids.
        var removed = false
        for r in contents.books {
            if let existing = Library.book(ctx, uid: r.id) {
                existing.sessions.forEach { ctx.delete($0) }
                existing.notes.forEach { ctx.delete($0) }
                ctx.delete(existing)
                removed = true
            }
        }
        let sessionIDs = Set(contents.sessions.map(\.id)), noteIDs = Set(contents.notes.map(\.id))
        for s in (try? ctx.fetch(FetchDescriptor<ReadingSession>())) ?? [] where sessionIDs.contains(s.uid) { ctx.delete(s); removed = true }
        for n in (try? ctx.fetch(FetchDescriptor<BookNote>())) ?? [] where noteIDs.contains(n.uid) { ctx.delete(n); removed = true }
        if removed { try? ctx.save() }

        var byID: [String: Book] = [:]
        for r in contents.books {
            let b = Book(uid: r.id, title: r.title, author: r.author, isbn: r.isbn, totalPages: r.totalPages,
                         startPage: r.startPage, status: r.status, addedAt: r.addedAt, lastAt: r.lastAt)
            b.finishedDay = r.finishedDay
            b.dnfDay = r.dnfDay
            b.dnfNote = r.dnfNote
            b.rating = r.rating
            ctx.insert(b)
            byID[r.id] = b
        }
        for r in contents.sessions {
            guard let b = byID[r.bookID] else { continue }
            ctx.insert(ReadingSession(uid: r.id, book: b, startedAt: r.startedAt, startPage: r.startPage,
                                      endPage: r.endPage, minutes: r.minutes, createdAt: r.createdAt, day: r.day))
        }
        for r in contents.notes {
            guard let b = byID[r.bookID] else { continue }
            ctx.insert(BookNote(uid: r.id, book: b, kind: r.kind, text: r.text, page: r.page, createdAt: r.createdAt))
        }
        Library.save(ctx)
    }

    // MARK: writing

    @MainActor
    static func export(_ ctx: ModelContext) -> Data {
        let books = (try? ctx.fetch(FetchDescriptor<Book>())) ?? []
        var b: [String: Any] = [:], s: [String: Any] = [:], n: [String: Any] = [:]
        for book in books {
            b[book.uid] = compact([
                "title": book.title, "author": book.author, "isbn": book.isbn as Any, "totalPages": book.totalPages,
                "startPage": book.startPage, "status": book.statusRaw, "addedAt": iso(book.addedAt), "lastAt": iso(book.lastAt),
                "finishedDay": book.finishedDay as Any, "dnfDay": book.dnfDay as Any, "dnfNote": book.dnfNote as Any,
                "rating": book.rating as Any])
            for x in book.sessions {
                s[x.uid] = compact([
                    "bookId": book.uid, "startedAt": local(x.startedAt), "day": x.day, "startPage": x.startPage,
                    "endPage": x.endPage, "pages": x.pages, "minutes": x.minutes as Any, "createdAt": iso(x.createdAt)])
            }
            for x in book.notes {
                n[x.uid] = compact(["bookId": book.uid, "kind": x.kindRaw, "text": x.text, "page": x.page as Any,
                                    "createdAt": iso(x.createdAt)])
            }
        }
        let root: [String: Any] = ["app": "reading-tracker", "version": 2, "exportedAt": iso(.now),
                                   "books": b, "sessions": s, "notes": n, "timer": [String: Any]()]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    @MainActor
    static func csv(_ ctx: ModelContext) -> String {
        let books = ((try? ctx.fetch(FetchDescriptor<Book>())) ?? []).sorted { $0.addedAt < $1.addedAt }
        var rows = ["Book,Author,Status,Pages,Rating,Finished,Session started,From page,To page,Pages read,Minutes"]
        for b in books {
            let head = [b.title, b.author, b.statusRaw, String(b.totalPages), b.rating.map { String($0) } ?? "", b.finishedDay ?? ""]
            let ss = b.sessions.sorted { $0.startedAt < $1.startedAt }
            if ss.isEmpty { rows.append((head + ["", "", "", "", ""]).map(field).joined(separator: ",")) }
            for s in ss {
                rows.append((head + [local(s.startedAt), String(s.startPage), String(s.endPage), String(s.pages),
                                     s.minutes.map(String.init) ?? ""]).map(field).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    // MARK: helpers

    private static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    private static let localMinute: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    /// Accepts "2026-10-30T00:28:12.282Z", "2026-10-30T00:28:12Z" and the web app's local "2026-10-30T13:40".
    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        return isoFull.date(from: s) ?? isoPlain.date(from: s) ?? localMinute.date(from: String(s.prefix(16)))
    }

    private static func iso(_ d: Date) -> String { isoFull.string(from: d) }
    private static func local(_ d: Date) -> String { localMinute.string(from: d) }

    private static func compact(_ d: [String: Any]) -> [String: Any] {
        d.filter { !($0.value is NSNull) && !isNilAny($0.value) }
    }

    private static func isNilAny(_ v: Any) -> Bool {
        let m = Mirror(reflecting: v)
        return m.displayStyle == .optional && m.children.isEmpty
    }

    private static func field(_ s: String) -> String {
        s.contains(",") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
}
