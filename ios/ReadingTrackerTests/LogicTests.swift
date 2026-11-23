import XCTest
import SwiftData
import StoreKit
@testable import ReadingTracker

final class ISBNTests: XCTestCase {
    func testValidISBN13() {
        XCTAssertEqual(ISBN.normalize("9781398561960"), "9781398561960")
        XCTAssertEqual(ISBN.normalize("978-1-398-56196-0"), "9781398561960")
    }

    func testRejectsBadChecksumAndNonBooks() {
        XCTAssertNil(ISBN.normalize("9781398561961"))
        XCTAssertNil(ISBN.normalize("5012345678900")) // a grocery barcode
        XCTAssertNil(ISBN.normalize("hello"))
    }

    func testConvertsISBN10() {
        XCTAssertEqual(ISBN.normalize("0-306-40615-2"), "9780306406157")
        XCTAssertEqual(ISBN.normalize("080442957X"), "9780804429573")
        XCTAssertNil(ISBN.normalize("0306406153"))
    }
}

final class DayTests: XCTestCase {
    func testKeysRoundTrip() {
        for key in ["2026-01-01", "2026-02-28", "2026-03-29", "2026-10-25", "2026-11-23", "2026-12-31", "2028-02-29"] {
            XCTAssertEqual(Day.key(Day.date(key)), key)
        }
        XCTAssertEqual(Day.monthKey(Day.date("2026-11-23")), "2026-11")
        XCTAssertEqual(Day.key(Day.date("2026-11")), "2026-11-01")
        XCTAssertEqual(Day.key(Day.date("2026-10-30T13:40")), "2026-10-30")
        XCTAssertEqual(Day.date("nonsense"), .distantPast)
    }

    func testWeeksStartOnMonday() {
        XCTAssertEqual(Day.key(Day.startOfWeek(Day.date("2026-11-23"))), "2026-11-23") // a Monday
        XCTAssertEqual(Day.key(Day.startOfWeek(Day.date("2026-11-22"))), "2026-11-16") // a Sunday
        XCTAssertEqual(Day.daysInMonth(Day.date("2026-02-10")), 28)
    }
}

final class StatsTests: XCTestCase {
    private let now = Day.date("2026-11-18").addingTimeInterval(20 * 3600) // Wed 18 Nov 2026, 8pm

    private func session(_ book: String, _ day: String, _ from: Int, _ to: Int, minutes: Int? = nil) -> SessionSnap {
        SessionSnap(id: UUID().uuidString, bookID: book, day: day, startedAt: Day.date(day).addingTimeInterval(19 * 3600),
                    startPage: from, endPage: to, pages: to - from, minutes: minutes)
    }

    func testCurrentPageUsesFurthestPageAndCapsAtTotal() {
        let b = BookSnap(id: "a", title: "A", totalPages: 100, startPage: 5)
        XCTAssertEqual(Stats.currentPage(b, sessions: []), 5)
        let ss = [session("a", "2026-11-10", 5, 40), session("a", "2026-11-11", 10, 30), session("b", "2026-11-11", 0, 99)]
        XCTAssertEqual(Stats.currentPage(b, sessions: ss), 40)
        XCTAssertEqual(Stats.currentPage(b, sessions: [session("a", "2026-11-12", 40, 120)]), 100)
    }

    func testStreakCountsBackFromTodayOrYesterday() {
        let pbd = ["2026-11-18": 10, "2026-11-17": 5, "2026-11-16": 3, "2026-11-14": 9]
        XCTAssertEqual(Stats.streak(pbd, now: now), 3)
        let noneToday = ["2026-11-17": 5, "2026-11-16": 3]
        XCTAssertEqual(Stats.streak(noneToday, now: now), 2)
        XCTAssertEqual(Stats.streak(["2026-11-15": 4], now: now), 0)
    }

    func testScoresWeekAndMonth() {
        let ss = [
            session("a", "2026-11-18", 0, 20),  // today (Wed)
            session("a", "2026-11-16", 20, 50), // Mon this week
            session("a", "2026-11-10", 50, 60), // Tue last week (counts: before Wed)
            session("a", "2026-11-13", 60, 70), // Fri last week (doesn't count yet)
            session("a", "2026-10-05", 70, 90), // last month, before the 18th
            session("a", "2026-10-25", 90, 99), // last month, after the 18th
        ]
        let books = [BookSnap(id: "a", title: "A", totalPages: 300),
                     BookSnap(id: "b", title: "B", totalPages: 100, status: .finished, finishedDay: "2026-11-02"),
                     BookSnap(id: "c", title: "C", totalPages: 100, status: .dnf, dnfDay: "2026-11-03")]
        let s = Stats.scores(books: books, sessions: ss, now: now)
        XCTAssertEqual(s.today, 20)
        XCTAssertEqual(s.week, 50)
        XCTAssertEqual(s.lastWeekSoFar, 10)
        XCTAssertEqual(s.month, 70)
        XCTAssertEqual(s.lastMonthSoFar, 20)
        XCTAssertEqual(s.finishedThisMonth, 1)
        XCTAssertEqual(s.dnfThisMonth, 1)
        XCTAssertEqual(s.streak, 1)
        XCTAssertEqual(Stats.versus(50, 10, "last week"), "+40 vs last week")
        XCTAssertEqual(Stats.versus(5, 0, "last week"), "nothing last week by now")
    }

    func testPaceFromLastFourteenDays() {
        let b = BookSnap(id: "a", title: "A", totalPages: 300)
        let p = Stats.pace(b, sessions: [session("a", "2026-11-10", 0, 70), session("a", "2026-10-01", 70, 100)], now: now)
        XCTAssertEqual(p.current, 100)
        XCTAssertEqual(p.left, 200)
        XCTAssertEqual(p.etaDays, 40) // 70 pages / 14 days = 5 a day
    }

    func testAverageDayOnlyCountsDaysYouRead() {
        let ss = [session("a", "2026-11-18", 0, 20, minutes: 30), session("a", "2026-11-17", 20, 60, minutes: 50),
                  session("a", "2026-11-16", 60, 90)]
        let avg = Stats.averageDay(sessions: ss, days: 7, now: now)
        XCTAssertEqual(avg.readDays, 3)
        XCTAssertEqual(avg.avgPages, 30, accuracy: 0.01)
        XCTAssertEqual(avg.timedDays, 2)
        XCTAssertEqual(avg.avgMinutes, 40, accuracy: 0.01)
        XCTAssertEqual(avg.pagesPerHour ?? 0, 45, accuracy: 0.01) // 60 pages in 80 minutes
        XCTAssertEqual(avg.series.count, 7)
    }

    func testPageBarsAndBookBars() {
        let ss = [session("a", "2026-11-18", 0, 20), session("a", "2026-11-05", 20, 40)]
        let days = Stats.pageBars(.day, sessions: ss, now: now)
        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days.last?.value, 20)
        XCTAssertTrue(days.last?.isCurrent ?? false)
        XCTAssertEqual(days.first?.value, 20) // 5 Nov is 13 days before
        let months = Stats.pageBars(.month, sessions: ss, now: now)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.last?.value, 40)
        let books = [BookSnap(id: "b", title: "B", totalPages: 100, status: .finished, finishedDay: "2026-11-02")]
        XCTAssertEqual(Stats.bookBars(books: books, now: now).last?.value, 1)
    }
}

final class TimerTests: XCTestCase {
    func testPauseResumeKeepsTime() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var t = ActiveTimer(bookID: "a", bookTitle: "A", startPage: 10, startedAt: t0, accumulated: 0, runningSince: t0, status: .running)
        XCTAssertEqual(t.elapsed(at: t0.addingTimeInterval(600)), 600, accuracy: 0.001)
        t.pause(at: t0.addingTimeInterval(600))
        XCTAssertEqual(t.elapsed(at: t0.addingTimeInterval(5000)), 600, accuracy: 0.001)
        t.resume(at: t0.addingTimeInterval(5000))
        t.stop(at: t0.addingTimeInterval(5300))
        XCTAssertEqual(t.elapsed(at: t0.addingTimeInterval(9999)), 900, accuracy: 0.001)
        XCTAssertEqual(t.minutes(at: t0.addingTimeInterval(9999)), 15)
        XCTAssertEqual(ActiveTimer.clock(3725), "1:02:05")
        XCTAssertEqual(ActiveTimer.clock(65), "1:05")
    }
}

final class AccessTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    func testTrialLifecycle() {
        XCTAssertEqual(AccessRules.access(trialStart: nil, unlocked: false, now: start), .noTrial)
        XCTAssertEqual(AccessRules.access(trialStart: start, unlocked: false, now: start),
                       .trial(endsAt: start.addingTimeInterval(AccessRules.trialLength)))
        XCTAssertEqual(AccessRules.access(trialStart: start, unlocked: false, now: start.addingTimeInterval(2 * 86_400)),
                       .trial(endsAt: start.addingTimeInterval(AccessRules.trialLength)))
        XCTAssertEqual(AccessRules.access(trialStart: start, unlocked: false, now: start.addingTimeInterval(3 * 86_400)), .expired)
        XCTAssertEqual(AccessRules.access(trialStart: start, unlocked: true, now: start.addingTimeInterval(30 * 86_400)), .unlocked)
        XCTAssertEqual(AccessRules.access(trialStart: nil, unlocked: true, now: start), .unlocked)
    }

    func testWhoCanEdit() {
        XCTAssertTrue(Access.unlocked.canEdit)
        XCTAssertTrue(Access.trial(endsAt: start).canEdit)
        XCTAssertFalse(Access.expired.canEdit)
        XCTAssertFalse(Access.noTrial.canEdit)
    }

    func testPurchaseErrorsAreExplained() {
        XCTAssertEqual(StoreErrors.message(for: Product.PurchaseError.purchaseNotAllowed), StoreErrors.notAllowed)
        XCTAssertTrue(StoreErrors.message(for: Product.PurchaseError.purchaseNotAllowed).contains("Screen Time"))
        XCTAssertEqual(StoreErrors.message(for: Product.PurchaseError.productUnavailable), StoreErrors.unavailable)
        XCTAssertEqual(StoreErrors.message(for: StoreKitError.networkError(URLError(.notConnectedToInternet))), StoreErrors.network)
        XCTAssertEqual(StoreErrors.message(for: StoreKitError.userCancelled), "")
        let other = NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Something odd"])
        XCTAssertTrue(StoreErrors.message(for: other).contains("Something odd"))
        XCTAssertTrue(StoreErrors.message(for: other).contains("haven't been charged"))
    }

    func testTimeLeftWording() {
        XCTAssertEqual(AccessRules.timeLeft(until: start.addingTimeInterval(2.5 * 86_400), now: start), "3 days left")
        XCTAssertEqual(AccessRules.timeLeft(until: start.addingTimeInterval(5 * 3600), now: start), "5 hours left")
        XCTAssertEqual(AccessRules.timeLeft(until: start.addingTimeInterval(1800), now: start), "1 hour left")
    }
}

@MainActor
final class BackupTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: BackupTests.self).url(forResource: "web-backup", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testParsesTheWebAppBackup() throws {
        let c = try Backup.parse(fixture())
        XCTAssertEqual(c.books.count, 4)
        XCTAssertEqual(c.sessions.count, 40)
        XCTAssertEqual(c.totalPages, 427)
        let hunger = try XCTUnwrap(c.books.first { $0.title == "The hunger code" })
        XCTAssertEqual(hunger.status, .finished)
        XCTAssertEqual(hunger.finishedDay, "2026-11-13")
        XCTAssertEqual(hunger.startPage, 3)
    }

    func testRestoreThenExportRoundTrips() throws {
        let container = Persistence.makeContainer(inMemory: true)
        let ctx = container.mainContext
        Backup.restore(try Backup.parse(fixture()), into: ctx)
        let books = try ctx.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(books.count, 4)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<ReadingSession>()).count, 40)
        let apple = try XCTUnwrap(books.first { $0.title.hasPrefix("Apple") })
        XCTAssertEqual(apple.currentPage, 51)

        apple.rating = 4.5
        ctx.insert(BookNote(book: apple, kind: .quote, text: "Think different.", page: 12))
        try ctx.save()

        let again = try Backup.parse(Backup.export(ctx))
        XCTAssertEqual(again.books.count, 4)
        XCTAssertEqual(again.sessions.count, 40)
        XCTAssertEqual(again.totalPages, 427)
        XCTAssertEqual(again.notes.first?.text, "Think different.")
        XCTAssertEqual(again.books.first { $0.title.hasPrefix("Apple") }?.rating, 4.5)

        // Importing the same backup twice doesn't duplicate anything, and the stats still work afterwards.
        Backup.restore(again, into: ctx)
        Backup.restore(try Backup.parse(fixture()), into: ctx)
        let allBooks = try ctx.fetch(FetchDescriptor<Book>())
        let allSessions = try ctx.fetch(FetchDescriptor<ReadingSession>())
        XCTAssertEqual(allBooks.count, 4)
        XCTAssertEqual(allSessions.count, 40)
        let scores = Stats.scores(books: allBooks.map(\.snap), sessions: allSessions.map(\.snap), now: Day.date("2026-11-15"))
        XCTAssertEqual(scores.finishedThisMonth, 1)
        XCTAssertGreaterThan(scores.month, 0)
        XCTAssertTrue(Backup.csv(ctx).hasPrefix("Book,Author,Status"))
    }

    func testLoggingFinishesTheBook() throws {
        let container = Persistence.makeContainer(inMemory: true) // keep the store alive for the whole test
        let ctx = container.mainContext
        let b = Book(title: "Short", totalPages: 50)
        ctx.insert(b)
        XCTAssertFalse(Library.logSession(ctx, book: b, startedAt: .now, from: 0, to: 30, minutes: 20))
        XCTAssertEqual(b.status, .reading)
        XCTAssertTrue(Library.logSession(ctx, book: b, startedAt: .now, from: 30, to: 50, minutes: nil))
        XCTAssertEqual(b.status, .finished)
        XCTAssertEqual(b.finishedDay, Day.key(.now))
        XCTAssertEqual(Library.problem(from: 30, to: 30, totalPages: 50), "You started on page 30, so the finishing page needs to be higher.")
        XCTAssertNil(Library.problem(from: 0, to: 50, totalPages: 50))
        withExtendedLifetime(container) {}
    }
}
