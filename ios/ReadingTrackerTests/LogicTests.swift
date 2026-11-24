import Testing
import Foundation
import SwiftData
import StoreKit
import AVFoundation
@testable import ReadingTracker

@Suite struct ISBNTests {
    @Test func testValidISBN13() {
        #expect(ISBN.normalize("9781398561960") == "9781398561960")
        #expect(ISBN.normalize("978-1-398-56196-0") == "9781398561960")
    }

    @Test func testRejectsBadChecksumAndNonBooks() {
        #expect(ISBN.normalize("9781398561961") == nil)
        #expect(ISBN.normalize("5012345678900") == nil) // a grocery barcode
        #expect(ISBN.normalize("hello") == nil)
    }

    @Test func testConvertsISBN10() {
        #expect(ISBN.normalize("0-306-40615-2") == "9780306406157")
        #expect(ISBN.normalize("080442957X") == "9780804429573")
        #expect(ISBN.normalize("0306406153") == nil)
    }
}

@Suite struct CoverSearchTests {
    @Test func googleSearchAddress() {
        let q = GoogleCovers.query(title: "Café & Co: A Story", author: " Zoë Brontë ")
        #expect(q == "Café & Co: A Story Zoë Brontë book cover")
        let url = GoogleCovers.searchURL(query: q)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host == "www.google.com")
        #expect(items.first { $0.name == "tbm" }?.value == "isch")
        #expect(items.first { $0.name == "q" }?.value == q) // survives encoding of &, :, accents and spaces
        #expect(GoogleCovers.query(title: "Dune", author: "") == "Dune book cover")
    }

    @Test func decodesPicturesFromThePage() async {
        // a 2×2 red PNG
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg=="
        #expect(await GoogleCovers.imageData(fromSource: "data:image/png;base64," + png) != nil)
        #expect(await GoogleCovers.imageData(fromSource: "data:image/png;base64,not-a-picture") == nil)
        #expect(await GoogleCovers.imageData(fromSource: "javascript:alert(1)") == nil)
        #expect(await GoogleCovers.imageData(fromSource: "") == nil)
    }

    @Test func mergesCatalogueAnswers() {
        let a = BookLookup.Found(title: "Piranesi", author: "", pages: 272, coverURL: nil)
        let b = BookLookup.Found(title: "Piranesi (Bloomsbury)", author: "Susanna Clarke", pages: 245, coverURL: URL(string: "https://x/1.jpg"))
        let c = BookLookup.Found(title: "PIRANESI", author: "Clarke, Susanna", pages: 272, coverURL: URL(string: "https://x/2.jpg"))
        let m = BookLookup.merge([a, b, c])
        #expect(m.title == "Piranesi")
        #expect(m.author == "Clarke, Susanna" || m.author == "Susanna Clarke")
        #expect(m.pages == 272)
        #expect(m.coverURL == URL(string: "https://x/1.jpg"))
    }
}

@Suite struct DayTests {
    @Test func testKeysRoundTrip() {
        for key in ["2026-01-01", "2026-02-28", "2026-03-29", "2026-10-25", "2026-11-23", "2026-12-31", "2028-02-29"] {
            #expect(Day.key(Day.date(key)) == key)
        }
        #expect(Day.monthKey(Day.date("2026-11-23")) == "2026-11")
        #expect(Day.key(Day.date("2026-11")) == "2026-11-01")
        #expect(Day.key(Day.date("2026-10-30T13:40")) == "2026-10-30")
        #expect(Day.date("nonsense") == .distantPast)
    }

    @Test func testWeeksStartOnMonday() {
        #expect(Day.key(Day.startOfWeek(Day.date("2026-11-23"))) == "2026-11-23") // a Monday
        #expect(Day.key(Day.startOfWeek(Day.date("2026-11-22"))) == "2026-11-16") // a Sunday
        #expect(Day.daysInMonth(Day.date("2026-02-10")) == 28)
    }
}

@Suite struct StatsTests {
    private let now = Day.date("2026-11-18").addingTimeInterval(20 * 3600) // Wed 18 Nov 2026, 8pm

    private func session(_ book: String, _ day: String, _ from: Int, _ to: Int, minutes: Int? = nil) -> SessionSnap {
        SessionSnap(id: UUID().uuidString, bookID: book, day: day, startedAt: Day.date(day).addingTimeInterval(19 * 3600),
                    startPage: from, endPage: to, pages: to - from, minutes: minutes)
    }

    @Test func testCurrentPageUsesFurthestPageAndCapsAtTotal() {
        let b = BookSnap(id: "a", title: "A", totalPages: 100, startPage: 5)
        #expect(Stats.currentPage(b, sessions: []) == 5)
        let ss = [session("a", "2026-11-10", 5, 40), session("a", "2026-11-11", 10, 30), session("b", "2026-11-11", 0, 99)]
        #expect(Stats.currentPage(b, sessions: ss) == 40)
        #expect(Stats.currentPage(b, sessions: [session("a", "2026-11-12", 40, 120)]) == 100)
    }

    @Test func testStreakCountsBackFromTodayOrYesterday() {
        let pbd = ["2026-11-18": 10, "2026-11-17": 5, "2026-11-16": 3, "2026-11-14": 9]
        #expect(Stats.streak(pbd, now: now) == 3)
        let noneToday = ["2026-11-17": 5, "2026-11-16": 3]
        #expect(Stats.streak(noneToday, now: now) == 2)
        #expect(Stats.streak(["2026-11-15": 4], now: now) == 0)
    }

    @Test func testScoresWeekAndMonth() {
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
        #expect(s.today == 20)
        #expect(s.week == 50)
        #expect(s.lastWeekSoFar == 10)
        #expect(s.month == 70)
        #expect(s.lastMonthSoFar == 20)
        #expect(s.finishedThisMonth == 1)
        #expect(s.dnfThisMonth == 1)
        #expect(s.streak == 1)
        #expect(Stats.versus(50, 10, "last week") == "+40 vs last week")
        #expect(Stats.versus(5, 0, "last week") == "nothing last week by now")
    }

    @Test func testPaceFromLastFourteenDays() {
        let b = BookSnap(id: "a", title: "A", totalPages: 300)
        let p = Stats.pace(b, sessions: [session("a", "2026-11-10", 0, 70), session("a", "2026-10-01", 70, 100)], now: now)
        #expect(p.current == 100)
        #expect(p.left == 200)
        #expect(p.etaDays == 40) // 70 pages / 14 days = 5 a day
    }

    @Test func testAverageDayOnlyCountsDaysYouRead() {
        let ss = [session("a", "2026-11-18", 0, 20, minutes: 30), session("a", "2026-11-17", 20, 60, minutes: 50),
                  session("a", "2026-11-16", 60, 90)]
        let avg = Stats.averageDay(sessions: ss, days: 7, now: now)
        #expect(avg.readDays == 3)
        #expect(abs((avg.avgPages) - (30)) <= 0.01)
        #expect(avg.timedDays == 2)
        #expect(abs((avg.avgMinutes) - (40)) <= 0.01)
        #expect(abs((avg.pagesPerHour ?? 0) - (45)) <= 0.01) // 60 pages in 80 minutes
        #expect(avg.series.count == 7)
    }

    @Test func testPageBarsAndBookBars() {
        let ss = [session("a", "2026-11-18", 0, 20), session("a", "2026-11-05", 20, 40)]
        let days = Stats.pageBars(.day, sessions: ss, now: now)
        #expect(days.count == 14)
        #expect(days.last?.value == 20)
        #expect(days.last?.isCurrent ?? false)
        #expect(days.first?.value == 20) // 5 Nov is 13 days before
        let months = Stats.pageBars(.month, sessions: ss, now: now)
        #expect(months.count == 12)
        #expect(months.last?.value == 40)
        let books = [BookSnap(id: "b", title: "B", totalPages: 100, status: .finished, finishedDay: "2026-11-02")]
        #expect(Stats.bookBars(books: books, now: now).last?.value == 1)
    }
}

@Suite struct RecapTests {
    private let now = Day.date("2026-11-20").addingTimeInterval(20 * 3600)

    private func s(_ book: String, _ day: String, _ from: Int, _ to: Int, _ minutes: Int? = nil) -> SessionSnap {
        SessionSnap(id: UUID().uuidString, bookID: book, day: day, startedAt: Day.date(day).addingTimeInterval(19 * 3600),
                    startPage: from, endPage: to, pages: to - from, minutes: minutes)
    }

    @Test func testMonthlyRecap() {
        let books = [
            BookSnap(id: "a", title: "Alpha", totalPages: 200, status: .finished, finishedDay: "2026-11-12", rating: 4),
            BookSnap(id: "b", title: "Beta", totalPages: 500, status: .finished, finishedDay: "2026-11-18", rating: 4.5),
            BookSnap(id: "c", title: "Gamma", totalPages: 300, status: .finished, finishedDay: "2026-10-02", rating: 5),
            BookSnap(id: "d", title: "Delta", totalPages: 100, status: .dnf, dnfDay: "2026-11-05"),
        ]
        let sessions = [
            s("a", "2026-11-10", 0, 100, 60), s("a", "2026-11-11", 100, 150, 30), s("a", "2026-11-12", 150, 200),
            s("b", "2026-11-17", 0, 300, 120), s("b", "2026-11-18", 300, 500),
            s("c", "2026-10-01", 0, 300),
        ]
        let notes = [Recap.NoteInput(text: "Old quote", isQuote: true, day: "2026-10-03", bookTitle: "Gamma", author: ""),
                     Recap.NoteInput(text: "New quote", isQuote: true, day: "2026-11-15", bookTitle: "Alpha", author: "A"),
                     Recap.NoteInput(text: "A thought", isQuote: false, day: "2026-11-19", bookTitle: "Beta", author: "")]
        let r = Recap.make(.thisMonth(now), books: books, sessions: sessions, notes: notes, now: now)
        #expect(r.period.title == "November 2026")
        #expect(r.finished.map(\.title) == ["Alpha", "Beta"])
        #expect(r.writtenOff == 1)
        #expect(r.pages == 700)
        #expect(r.minutes == 210)
        #expect(r.sessions == 5)
        #expect(r.readingDays == 5)
        #expect(r.daysElapsed == 20)
        #expect(r.longestStreak == 3)
        #expect(r.bestDay?.day == "2026-11-17")
        #expect(r.bestDay?.pages == 300)
        #expect(r.topBook?.title == "Beta")
        #expect(r.longestBook?.title == "Beta")
        #expect(r.fastest?.book.title == "Beta")
        #expect(r.fastest?.days == 2)
        #expect(abs((r.averageRating ?? 0) - (4.25)) <= 0.001)
        #expect(r.quote?.text == "New quote")
        #expect(r.favouriteWeekday == "Tuesday") // 17 Nov 2026, 300 pages
        #expect(!(r.isEmpty))
    }

    @Test func testYearAndEmptyPeriods() {
        let books = [BookSnap(id: "c", title: "Gamma", totalPages: 300, status: .finished, finishedDay: "2026-10-02")]
        let sessions = [s("c", "2026-10-01", 0, 300)]
        let year = Recap.make(.thisYear(now), books: books, sessions: sessions, notes: [], now: now)
        #expect(year.period.title == "2026")
        #expect(year.finished.count == 1)
        #expect(year.pages == 300)
        #expect(year.daysElapsed == Day.daysBetween(Day.date("2026-01-01"), now) + 1)
        let last = Recap.make(.lastYear(now), books: books, sessions: sessions, notes: [], now: now)
        #expect(last.isEmpty)
        #expect(Recap.Period.lastMonth(now).title == "October 2026")
        #expect(RecapSlide.slides(for: last) == [.intro, .summary])
    }
}

@Suite struct SoundTests {
    private func stats(_ sound: FocusSound, seconds: Double = 2) -> (rms: Float, peak: Float, finite: Bool) {
        let synth = SoundSynth(sampleRate: 44_100)
        synth.sound = sound
        var sum: Float = 0, peak: Float = 0, finite = true
        let n = Int(44_100 * seconds)
        for _ in 0..<n {
            let x = synth.next()
            if !x.isFinite { finite = false }
            sum += x * x
            peak = max(peak, abs(x))
        }
        return ((sum / Float(n)).squareRoot(), peak, finite)
    }

    @Test func testEachSoundIsAudibleAndSafe() {
        for sound in [FocusSound.rain, .cafe, .fireplace, .beach, .whiteNoise] {
            let s = stats(sound)
            #expect(s.finite, "\(sound) produced an invalid sample")
            #expect(s.peak <= 1, "\(sound) clips")
            #expect(s.rms > 0.01, "\(sound) is too quiet")
            #expect(s.rms < 0.5, "\(sound) is too loud")
        }
        #expect(stats(.off, seconds: 0.2).rms == 0)
    }

    @Test func testSoundsAreStereo() {
        for sound in [FocusSound.rain, .cafe, .fireplace, .beach, .whiteNoise] {
            let synth = SoundSynth(sampleRate: 44_100)
            synth.sound = sound
            var diff: Float = 0
            for _ in 0..<44_100 { let (l, r) = synth.nextStereo(); diff += abs(l - r) }
            #expect(diff / 44_100 > 0.001, "\(sound) should differ between left and right")
        }
    }

    @Test func recordingsAreBundled() {
        for name in ["rain", "fireplace", "cafe", "beach"] {
            #expect(Bundle.main.url(forResource: name, withExtension: "m4a") != nil, "missing \(name).m4a")
            #expect((RecordingLoop.loopFrames(for: FocusSound(rawValue: name)!) ?? 0) > 44_100 * 30)
        }
    }

    @Test func recordingLoopTrimsAndCleansTheStart() throws {
        let n = 10_000, extra = 8192
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n + extra)))
        buffer.frameLength = AVAudioFrameCount(n + extra)
        for c in 0..<2 {
            let x = buffer.floatChannelData![c]
            for i in 0..<(n + extra) { x[i] = Float(i % n) / Float(n) }   // a ramp that repeats every n frames
            for i in 0..<64 { x[i] = 0.9 }                                 // a smeared start, like a codec's
        }
        RecordingLoop.prepare(buffer, loopFrames: n)
        #expect(buffer.frameLength == AVAudioFrameCount(n))
        let x = buffer.floatChannelData![0]
        #expect(abs(x[0] - 0) < 0.001)           // the smear is gone
        #expect(abs(x[100] - 0.01) < 0.001)
    }

    @Test func testSoundsAreFastEnoughForRealTime() {
        // one second of the busiest sound must take well under a second to make
        let synth = SoundSynth(sampleRate: 48_000)
        synth.sound = .cafe
        let start = Date()
        for _ in 0..<48_000 { _ = synth.nextStereo() }
        #expect(Date().timeIntervalSince(start) < 0.5)
    }
}

@Suite struct TimerTests {
    @Test func testPauseResumeKeepsTime() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var t = ActiveTimer(bookID: "a", bookTitle: "A", startPage: 10, startedAt: t0, accumulated: 0, runningSince: t0, status: .running)
        #expect(abs((t.elapsed(at: t0.addingTimeInterval(600))) - (600)) <= 0.001)
        t.pause(at: t0.addingTimeInterval(600))
        #expect(abs((t.elapsed(at: t0.addingTimeInterval(5000))) - (600)) <= 0.001)
        t.resume(at: t0.addingTimeInterval(5000))
        t.stop(at: t0.addingTimeInterval(5300))
        #expect(abs((t.elapsed(at: t0.addingTimeInterval(9999))) - (900)) <= 0.001)
        #expect(t.minutes(at: t0.addingTimeInterval(9999)) == 15)
        #expect(ActiveTimer.clock(3725) == "1:02:05")
        #expect(ActiveTimer.clock(65) == "1:05")
    }
}

@Suite struct AccessTests {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func testTrialLifecycle() {
        #expect(AccessRules.access(trialStart: nil, unlocked: false, now: start) == .noTrial)
        #expect(AccessRules.access(trialStart: start, unlocked: false, now: start) == .trial(endsAt: start.addingTimeInterval(AccessRules.trialLength)))
        #expect(AccessRules.access(trialStart: start, unlocked: false, now: start.addingTimeInterval(2 * 86_400)) == .trial(endsAt: start.addingTimeInterval(AccessRules.trialLength)))
        #expect(AccessRules.access(trialStart: start, unlocked: false, now: start.addingTimeInterval(3 * 86_400)) == .expired)
        #expect(AccessRules.access(trialStart: start, unlocked: true, now: start.addingTimeInterval(30 * 86_400)) == .unlocked)
        #expect(AccessRules.access(trialStart: nil, unlocked: true, now: start) == .unlocked)
    }

    @Test func testWhoCanEdit() {
        #expect(Access.unlocked.canEdit)
        #expect(Access.trial(endsAt: start).canEdit)
        #expect(!(Access.expired.canEdit))
        #expect(!(Access.noTrial.canEdit))
    }

    @Test func testPurchaseErrorsAreExplained() {
        #expect(StoreErrors.message(for: Product.PurchaseError.purchaseNotAllowed) == StoreErrors.notAllowed)
        #expect(StoreErrors.message(for: Product.PurchaseError.purchaseNotAllowed).contains("Screen Time"))
        #expect(StoreErrors.message(for: Product.PurchaseError.productUnavailable) == StoreErrors.unavailable)
        #expect(StoreErrors.message(for: StoreKitError.networkError(URLError(.notConnectedToInternet))) == StoreErrors.network)
        #expect(StoreErrors.message(for: StoreKitError.userCancelled) == "")
        let other = NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Something odd"])
        #expect(StoreErrors.message(for: other).contains("Something odd"))
        #expect(StoreErrors.message(for: other).contains("haven't been charged"))
    }

    @Test func testTimeLeftWording() {
        #expect(AccessRules.timeLeft(until: start.addingTimeInterval(2.5 * 86_400), now: start) == "3 days left")
        #expect(AccessRules.timeLeft(until: start.addingTimeInterval(5 * 3600), now: start) == "5 hours left")
        #expect(AccessRules.timeLeft(until: start.addingTimeInterval(1800), now: start) == "1 hour left")
    }
}

@MainActor
@Suite struct BackupTests {
    private func fixture() throws -> Data {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "web-backup", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test func testParsesTheWebAppBackup() throws {
        let c = try Backup.parse(fixture())
        #expect(c.books.count == 4)
        #expect(c.sessions.count == 40)
        #expect(c.totalPages == 427)
        let hunger = try #require(c.books.first { $0.title == "The hunger code" })
        #expect(hunger.status == .finished)
        #expect(hunger.finishedDay == "2026-11-13")
        #expect(hunger.startPage == 3)
    }

    @Test func testRestoreThenExportRoundTrips() throws {
        let container = Persistence.makeContainer(inMemory: true)
        let ctx = container.mainContext
        Backup.restore(try Backup.parse(fixture()), into: ctx)
        let books = try ctx.fetch(FetchDescriptor<Book>())
        #expect(books.count == 4)
        #expect(try ctx.fetch(FetchDescriptor<ReadingSession>()).count == 40)
        let apple = try #require(books.first { $0.title.hasPrefix("Apple") })
        #expect(apple.currentPage == 51)

        apple.rating = 4.5
        ctx.insert(BookNote(book: apple, kind: .quote, text: "Think different.", page: 12))
        try ctx.save()

        let again = try Backup.parse(Backup.export(ctx))
        #expect(again.books.count == 4)
        #expect(again.sessions.count == 40)
        #expect(again.totalPages == 427)
        #expect(again.notes.first?.text == "Think different.")
        #expect(again.books.first { $0.title.hasPrefix("Apple") }?.rating == 4.5)

        // Importing the same backup twice doesn't duplicate anything, and the stats still work afterwards.
        Backup.restore(again, into: ctx)
        Backup.restore(try Backup.parse(fixture()), into: ctx)
        let allBooks = try ctx.fetch(FetchDescriptor<Book>())
        let allSessions = try ctx.fetch(FetchDescriptor<ReadingSession>())
        #expect(allBooks.count == 4)
        #expect(allSessions.count == 40)
        let scores = Stats.scores(books: allBooks.map(\.snap), sessions: allSessions.map(\.snap), now: Day.date("2026-11-15"))
        #expect(scores.finishedThisMonth == 1)
        #expect(scores.month > 0)
        #expect(Backup.csv(ctx).hasPrefix("Book,Author,Status"))
    }

    @Test func testLoggingFinishesTheBook() throws {
        let container = Persistence.makeContainer(inMemory: true) // keep the store alive for the whole test
        let ctx = container.mainContext
        let b = Book(title: "Short", totalPages: 50)
        ctx.insert(b)
        #expect(!(Library.logSession(ctx, book: b, startedAt: .now, from: 0, to: 30, minutes: 20)))
        #expect(b.status == .reading)
        #expect(Library.logSession(ctx, book: b, startedAt: .now, from: 30, to: 50, minutes: nil))
        #expect(b.status == .finished)
        #expect(b.finishedDay == Day.key(.now))
        #expect(Library.problem(from: 30, to: 30, totalPages: 50) == "You started on page 30, so the finishing page needs to be higher.")
        #expect(Library.problem(from: 0, to: 50, totalPages: 50) == nil)
        withExtendedLifetime(container) {}
    }
}

@MainActor
@Suite struct SyncTests {
    /// Two copies of the same book, as when one backup is imported on two devices before they sync.
    private func twoCopies(_ ctx: ModelContext) -> (Book, Book) {
        let a = Book(uid: "b1", title: "Middlemarch", author: "George Eliot", totalPages: 880)
        let b = Book(uid: "b1", title: "Middlemarch", author: "George Eliot", totalPages: 880)
        a.copyID = "B"; b.copyID = "A"
        b.rating = 4.5
        ctx.insert(a); ctx.insert(b)
        let shared = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for (book, id) in [(a, "x"), (b, "x"), (b, "y")] {   // session "x" exists on both, "y" only on one
            let s = ReadingSession(uid: "s-\(id)", book: book, startedAt: shared, startPage: 0, endPage: 20, minutes: 30)
            s.copyID = book.copyID + id
            ctx.insert(s)
        }
        let n = BookNote(uid: "n1", book: a, kind: .quote, text: "It is never too late.")
        ctx.insert(n)
        try? ctx.save()
        return (a, b)
    }

    @Test func mergesCopiesOfABookKeepingEverything() throws {
        let container = Persistence.makeContainer(inMemory: true) // keep the store alive for the whole test
        let ctx = container.mainContext
        _ = twoCopies(ctx)
        #expect(Sync.dedupe(ctx) == 2)   // one book copy and one session copy
        let books = try ctx.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        let kept = try #require(books.first)
        #expect(kept.copyID == "A")                    // every device keeps the smallest copy ID
        #expect(kept.rating == 4.5)
        #expect(Set((kept.sessions ?? []).map(\.uid)) == ["s-x", "s-y"])
        #expect((kept.notes ?? []).map(\.text) == ["It is never too late."])
        #expect(try ctx.fetch(FetchDescriptor<ReadingSession>()).count == 2)
        #expect(Sync.dedupe(ctx) == 0)   // nothing left to do
    }

    @Test func waitsUntilEveryCopyHasACopyID() throws {
        let container = Persistence.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let (a, _) = twoCopies(ctx)
        a.copyID = ""
        try ctx.save()
        Sync.dedupe(ctx)   // the session copies both have IDs, so they merge; the books must wait
        #expect(try ctx.fetch(FetchDescriptor<Book>()).count == 2)
        #expect(Sync.assignCopyIDs(ctx) == 1)
        #expect(!a.copyID.isEmpty)
        Sync.dedupe(ctx)
        #expect(try ctx.fetch(FetchDescriptor<Book>()).count == 1)
    }

    @Test func newRecordsGetTheirOwnCopyID() {
        let a = Book(title: "A", totalPages: 10), b = Book(title: "B", totalPages: 10)
        #expect(!a.copyID.isEmpty && a.copyID != b.copyID)
        let s = ReadingSession(book: nil, startedAt: .now, startPage: 0, endPage: 1, minutes: nil)
        #expect(!s.copyID.isEmpty)
        #expect(!BookNote(book: nil, kind: .thought, text: "hi").copyID.isEmpty)
    }
}

/// Finds this test bundle (Swift Testing suites are structs, so they can't be used with Bundle(for:)).
private final class BundleToken {}
