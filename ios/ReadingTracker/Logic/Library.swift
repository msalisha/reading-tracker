import Foundation
import SwiftData
import WidgetKit
import UIKit

/// Everything that changes the reading data goes through here, so the rules live in one place.
@MainActor
enum Library {
    /// Checks a start/finish pair. Returns a message to show, or nil when it's fine.
    static func problem(from: Int?, to: Int?, totalPages: Int) -> String? {
        guard let from, from >= 0 else { return "Type the page you started on." }
        if from >= totalPages { return "This book has \(totalPages) pages, so you need to start before page \(totalPages)." }
        guard let to else { return "Type the page you finished on." }
        if to <= from { return "You started on page \(from), so the finishing page needs to be higher." }
        if to > totalPages { return "This book has \(totalPages) pages, so the finishing page can't be higher." }
        return nil
    }

    /// Saves a session and moves the book on. Returns true when it finished the book.
    @discardableResult
    static func logSession(_ ctx: ModelContext, book: Book, startedAt: Date, from: Int, to: Int, minutes: Int?) -> Bool {
        let session = ReadingSession(book: book, startedAt: startedAt, startPage: from, endPage: to, minutes: minutes)
        ctx.insert(session)
        book.lastAt = .now
        if book.status == .wantToRead { book.status = .reading }
        var finished = false
        if to >= book.totalPages {
            book.status = .finished
            book.finishedDay = session.day
            book.dnfDay = nil
            book.dnfNote = nil
            finished = true
        }
        save(ctx)
        Haptics.success()
        return finished
    }

    static func markFinished(_ ctx: ModelContext, _ book: Book) {
        book.status = .finished
        book.finishedDay = Day.key(.now)
        book.dnfDay = nil
        book.dnfNote = nil
        book.lastAt = .now
        save(ctx)
        Haptics.success()
    }

    static func markDNF(_ ctx: ModelContext, _ book: Book, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        book.status = .dnf
        book.dnfDay = Day.key(.now)
        book.dnfNote = trimmed.isEmpty ? nil : String(trimmed.prefix(200))
        book.finishedDay = nil
        save(ctx)
    }

    static func startReading(_ ctx: ModelContext, _ book: Book) {
        book.status = .reading
        book.finishedDay = nil
        book.dnfDay = nil
        book.dnfNote = nil
        book.lastAt = .now
        save(ctx)
    }

    static func delete(_ ctx: ModelContext, _ book: Book) {
        if TimerStorage.load()?.bookID == book.uid {
            TimerStorage.save(nil)
            Task { await LiveActivityController.endAll() }
            NotificationCenter.default.post(name: .readingTimerChanged, object: nil)
        }
        ctx.delete(book)
        save(ctx)
    }

    static func delete(_ ctx: ModelContext, _ session: ReadingSession) {
        ctx.delete(session)
        save(ctx)
    }

    static func save(_ ctx: ModelContext) {
        try? ctx.save()
        refreshWidgets(ctx)
    }

    static func book(_ ctx: ModelContext, uid: String) -> Book? {
        let id = uid
        var d = FetchDescriptor<Book>(predicate: #Predicate { $0.uid == id })
        d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }

    /// Writes the small summary the widgets read, then asks them to redraw.
    static func refreshWidgets(_ ctx: ModelContext) {
        let sessions = (try? ctx.fetch(FetchDescriptor<ReadingSession>())) ?? []
        let books = (try? ctx.fetch(FetchDescriptor<Book>())) ?? []
        let snaps = sessions.map(\.snap)
        let cut = Day.key(Day.add(-400, to: .now))
        var snapshot = WidgetSnapshot()
        snapshot.pagesByDay = Stats.pagesByDay(snaps).filter { $0.key >= cut }
        let mk = Day.monthKey(.now)
        snapshot.booksThisMonth = books.filter { $0.status == .finished && ($0.finishedDay ?? "").hasPrefix(mk) }.count
        let timerBook = TimerStorage.load()?.bookID
        let reading = books.filter { $0.status == .reading }.sorted { $0.lastAt > $1.lastAt }
        if let b = reading.first(where: { $0.uid == timerBook }) ?? reading.first {
            snapshot.currentBook = .init(id: b.uid, title: b.title, author: b.author,
                                         page: Stats.currentPage(b.snap, sessions: snaps), totalPages: b.totalPages,
                                         cover: b.coverData.flatMap { Covers.thumbnail($0, maxSide: 240) })
        }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum Haptics {
    @MainActor static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    @MainActor static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
