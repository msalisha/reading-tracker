import Foundation
import SwiftData

@Model
final class Book {
    @Attribute(.unique) var uid: String
    var title: String
    var author: String
    var isbn: String?
    var totalPages: Int
    /// The page you were on when you added the book.
    var startPage: Int
    var statusRaw: String
    var addedAt: Date
    var lastAt: Date
    var finishedDay: String?
    var dnfDay: String?
    var dnfNote: String?
    /// Optional 0.5–5 stars.
    var rating: Double?
    @Attribute(.externalStorage) var coverData: Data?

    @Relationship(deleteRule: .cascade, inverse: \ReadingSession.book) var sessions: [ReadingSession] = []
    @Relationship(deleteRule: .cascade, inverse: \BookNote.book) var notes: [BookNote] = []

    init(uid: String = UUID().uuidString, title: String, author: String = "", isbn: String? = nil,
         totalPages: Int, startPage: Int = 0, status: BookStatus = .reading,
         addedAt: Date = .now, lastAt: Date = .now, coverData: Data? = nil) {
        self.uid = uid
        self.title = title
        self.author = author
        self.isbn = isbn
        self.totalPages = totalPages
        self.startPage = startPage
        self.statusRaw = status.rawValue
        self.addedAt = addedAt
        self.lastAt = lastAt
        self.coverData = coverData
    }

    var status: BookStatus {
        get { BookStatus(rawValue: statusRaw) ?? .reading }
        set { statusRaw = newValue.rawValue }
    }

    var snap: BookSnap {
        BookSnap(id: uid, title: title, author: author, totalPages: totalPages, startPage: startPage, status: status,
                 finishedDay: finishedDay, dnfDay: dnfDay, rating: rating, addedAt: addedAt, lastAt: lastAt)
    }

    var currentPage: Int { Stats.currentPage(snap, sessions: sessions.map(\.snap)) }
}

@Model
final class ReadingSession {
    @Attribute(.unique) var uid: String
    var book: Book?
    var startedAt: Date
    var day: String
    var startPage: Int
    var endPage: Int
    var pages: Int
    var minutes: Int?
    var createdAt: Date

    init(uid: String = UUID().uuidString, book: Book?, startedAt: Date, startPage: Int, endPage: Int,
         minutes: Int?, createdAt: Date = .now, day: String? = nil) {
        self.uid = uid
        self.book = book
        self.startedAt = startedAt
        self.day = day ?? Day.key(startedAt)
        self.startPage = startPage
        self.endPage = endPage
        self.pages = endPage - startPage
        self.minutes = minutes
        self.createdAt = createdAt
    }

    var snap: SessionSnap {
        SessionSnap(id: uid, bookID: book?.uid ?? "", day: day, startedAt: startedAt, startPage: startPage,
                    endPage: endPage, pages: pages, minutes: minutes)
    }
}

@Model
final class BookNote {
    enum Kind: String, CaseIterable, Identifiable {
        case quote, thought
        var id: String { rawValue }
        var title: String { self == .quote ? "Quote" : "Thought" }
        var icon: String { self == .quote ? "quote.opening" : "lightbulb" }
    }

    @Attribute(.unique) var uid: String
    var book: Book?
    var kindRaw: String
    var text: String
    var page: Int?
    var createdAt: Date

    init(uid: String = UUID().uuidString, book: Book?, kind: Kind, text: String, page: Int? = nil, createdAt: Date = .now) {
        self.uid = uid
        self.book = book
        self.kindRaw = kind.rawValue
        self.text = text
        self.page = page
        self.createdAt = createdAt
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .thought }
        set { kindRaw = newValue.rawValue }
    }
}

enum Persistence {
    static let schema = Schema([Book.self, ReadingSession.self, BookNote.self])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let dir = AppGroup.containerURL {
            config = ModelConfiguration(schema: schema, url: dir.appendingPathComponent("Library.store"))
        } else {
            config = ModelConfiguration(schema: schema)
        }
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Couldn't open the library: \(error)")
        }
    }
}
