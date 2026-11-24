import Foundation
import SwiftData

// Every model follows iCloud's rules so the library can sync: no unique constraints, a default for every stored
// property, and optional to-many relationships. `uid` is still unique in practice: Sync.dedupe merges any copies.

@Model
final class Book {
    var uid: String = ""
    /// Identifies this copy of the record, so devices agree which copy to keep if the same book exists twice.
    var copyID: String = ""
    var title: String = ""
    var author: String = ""
    var isbn: String?
    var totalPages: Int = 1
    /// The page you were on when you added the book.
    var startPage: Int = 0
    var statusRaw: String = BookStatus.reading.rawValue
    /// "print" or "audio". For an audiobook, `totalPages`, `startPage` and session positions are in minutes.
    var formatRaw: String = "print"
    var addedAt: Date = Date.now
    var lastAt: Date = Date.now
    var finishedDay: String?
    var dnfDay: String?
    var dnfNote: String?
    /// Optional 0.5–5 stars.
    var rating: Double?
    @Attribute(.externalStorage) var coverData: Data?

    @Relationship(deleteRule: .cascade, inverse: \ReadingSession.book) var sessions: [ReadingSession]? = []
    @Relationship(deleteRule: .cascade, inverse: \BookNote.book) var notes: [BookNote]? = []

    init(uid: String = UUID().uuidString, title: String, author: String = "", isbn: String? = nil,
         totalPages: Int, startPage: Int = 0, status: BookStatus = .reading,
         addedAt: Date = .now, lastAt: Date = .now, coverData: Data? = nil, isAudio: Bool = false) {
        self.formatRaw = isAudio ? "audio" : "print"
        self.uid = uid
        self.copyID = UUID().uuidString
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

    var isAudio: Bool {
        get { formatRaw == "audio" }
        set { formatRaw = newValue ? "audio" : "print" }
    }

    var snap: BookSnap {
        BookSnap(id: uid, title: title, author: author, totalPages: totalPages, startPage: startPage, status: status,
                 finishedDay: finishedDay, dnfDay: dnfDay, rating: rating, addedAt: addedAt, lastAt: lastAt, isAudio: isAudio)
    }

    var currentPage: Int { Stats.currentPage(snap, sessions: (sessions ?? []).map(\.snap)) }
}

@Model
final class ReadingSession {
    var uid: String = ""
    var copyID: String = ""
    var book: Book?
    var startedAt: Date = Date.now
    var day: String = ""
    var startPage: Int = 0
    var endPage: Int = 0
    var pages: Int = 0
    var minutes: Int?
    var createdAt: Date = Date.now

    init(uid: String = UUID().uuidString, book: Book?, startedAt: Date, startPage: Int, endPage: Int,
         minutes: Int?, createdAt: Date = .now, day: String? = nil) {
        self.uid = uid
        self.copyID = UUID().uuidString
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
                    endPage: endPage, pages: pages, minutes: minutes, isAudio: book?.isAudio ?? false)
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

    var uid: String = ""
    var copyID: String = ""
    var book: Book?
    var kindRaw: String = Kind.thought.rawValue
    var text: String = ""
    var page: Int?
    var createdAt: Date = Date.now

    init(uid: String = UUID().uuidString, book: Book?, kind: Kind, text: String, page: Int? = nil, createdAt: Date = .now) {
        self.uid = uid
        self.copyID = UUID().uuidString
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
    nonisolated(unsafe) static let schema = Schema([Book.self, ReadingSession.self, BookNote.self])
    /// The iCloud container the library syncs with, or nil when this build has no iCloud entitlement (e.g. CI).
    nonisolated(unsafe) static private(set) var cloudContainerID: String?

    /// The in-app iCloud sync switch (on unless the user turns it off).
    static var syncEnabled: Bool {
        get { AppGroup.defaults.object(forKey: "iCloudSyncEnabled") as? Bool ?? true }
        set { AppGroup.defaults.set(newValue, forKey: "iCloudSyncEnabled") }
    }

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do { return try ModelContainer(for: schema, configurations: [config]) } catch {
                fatalError("Couldn't open the library: \(error)")
            }
        }
        let url = AppGroup.containerURL?.appendingPathComponent("Library.store")
        func config(_ db: ModelConfiguration.CloudKitDatabase) -> ModelConfiguration {
            if let url { return ModelConfiguration(schema: schema, url: url, cloudKitDatabase: db) }
            return ModelConfiguration(schema: schema, cloudKitDatabase: db)
        }
        prepareForSync(config(.none))
        cloudContainerID = nil
        guard syncEnabled else {
            do { return try ModelContainer(for: schema, configurations: [config(.none)]) } catch {
                fatalError("Couldn't open the library: \(error)")
            }
        }
        // .automatic syncs with the iCloud container in the app's entitlements, and stays on-device when there is none.
        let cloud = config(.automatic)
        do {
            let container = try ModelContainer(for: schema, configurations: [cloud])
            cloudContainerID = cloud.cloudKitContainerIdentifier
            return container
        } catch {
            print("iCloud sync unavailable, using on-device storage: \(error)")
        }
        do { return try ModelContainer(for: schema, configurations: [config(.none)]) } catch {
            fatalError("Couldn't open the library: \(error)")
        }
    }

    /// Once, before the library first syncs: give every existing record its own copy ID while it is still only on
    /// this device, so the first upload already carries it and every device makes the same choice when merging.
    private static func prepareForSync(_ local: ModelConfiguration) {
        let key = "syncPrepared.v1"
        guard !AppGroup.defaults.bool(forKey: key) else { return }
        autoreleasepool {
            if let container = try? ModelContainer(for: schema, configurations: [local]) {
                let ctx = ModelContext(container)
                Sync.assignCopyIDs(ctx)
            }
        }
        AppGroup.defaults.set(true, forKey: key)
    }
}
