import Foundation
import SwiftData

/// Example library used by UI tests and App Store screenshots (launch argument -uitest-sample).
/// Public-domain books only.
@MainActor
enum SampleData {
    static func insert(into ctx: ModelContext, now: Date = .now) {
        let specs: [(String, String, Int, BookStatus)] = [
            ("Pride and Prejudice", "Jane Austen", 432, .reading),
            ("Frankenstein", "Mary Shelley", 280, .reading),
            ("Moby-Dick", "Herman Melville", 635, .reading),
            ("The Great Gatsby", "F. Scott Fitzgerald", 180, .finished),
            ("Jane Eyre", "Charlotte Brontë", 507, .finished),
            ("Little Women", "Louisa May Alcott", 449, .wantToRead),
        ]
        var books: [Book] = []
        for (i, s) in specs.enumerated() {
            let b = Book(uid: "sample-\(i)", title: s.0, author: s.1, totalPages: s.2, status: s.3,
                         addedAt: Day.add(-40 + i, to: now), lastAt: Day.add(-i, to: now))
            ctx.insert(b)
            books.append(b)
        }
        // Thirty days of reading, rotating between the books, with a gap or two.
        var page: [Int: Int] = [:]
        for d in stride(from: 29, through: 0, by: -1) where d % 9 != 4 {
            let which = d > 20 ? 4 : d > 12 ? 3 : [0, 1, 0, 2][d % 4]
            let book = books[which]
            let from = page[which] ?? 0
            let read = 12 + (d * 7) % 25
            let to = min(book.totalPages, from + read)
            let start = Calendar.current.date(bySettingHour: 20, minute: 15, second: 0, of: Day.add(-d, to: now)) ?? now
            ctx.insert(ReadingSession(book: book, startedAt: start, startPage: from, endPage: to, minutes: 15 + read))
            page[which] = to
        }
        // An audiobook on the go, with a few listening sessions.
        let audio = Book(uid: "sample-audio", title: "Emma", author: "Jane Austen", totalPages: 14 * 60 + 30, status: .reading,
                         addedAt: Day.add(-9, to: now), lastAt: Day.add(-8, to: now), isAudio: true)
        ctx.insert(audio)
        var at = 0
        for d in [6, 3, 1] {
            let start = Calendar.current.date(bySettingHour: 8, minute: 5, second: 0, of: Day.add(-d, to: now)) ?? now
            ctx.insert(ReadingSession(book: audio, startedAt: start, startPage: at, endPage: at + 45, minutes: 40))
            at += 45
        }
        books[3].finishedDay = Day.key(Day.add(-14, to: now))
        books[3].rating = 4.5
        books[4].finishedDay = Day.key(Day.add(-22, to: now))
        books[4].rating = 5
        ctx.insert(BookNote(book: books[0], kind: .quote,
                            text: "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
                            page: 1))
        ctx.insert(BookNote(book: books[0], kind: .thought, text: "Elizabeth's first impressions are doing a lot of work here."))
        Library.save(ctx)
    }
}
