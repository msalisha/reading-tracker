import Foundation
import CoreData
import CloudKit
import SwiftData

/// iCloud sync housekeeping. SwiftData does the syncing itself; this keeps the library tidy when the same book,
/// session or note ends up on a device twice (for example after importing the same backup on two devices).
@MainActor
enum Sync {
    private static var pending: Task<Void, Never>?
    private static var observer: NSObjectProtocol?

    /// Merge duplicates now, and again shortly after each batch of changes arrives from iCloud.
    static func watch(_ container: ModelContainer) {
        dedupe(container.mainContext)
        if let observer { NotificationCenter.default.removeObserver(observer) }   // only watch the current library
        pending?.cancel()
        observer = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                pending?.cancel()
                pending = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))   // let a burst of changes land first
                    guard !Task.isCancelled else { return }
                    dedupe(container.mainContext)
                }
            }
        }
    }

    /// Give a copy ID to every record that doesn't have one yet. Returns how many were updated.
    @discardableResult
    nonisolated static func assignCopyIDs(_ ctx: ModelContext) -> Int {
        var n = 0
        for b in (try? ctx.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.copyID == "" }))) ?? [] {
            b.copyID = UUID().uuidString; n += 1
        }
        for x in (try? ctx.fetch(FetchDescriptor<ReadingSession>(predicate: #Predicate { $0.copyID == "" }))) ?? [] {
            x.copyID = UUID().uuidString; n += 1
        }
        for x in (try? ctx.fetch(FetchDescriptor<BookNote>(predicate: #Predicate { $0.copyID == "" }))) ?? [] {
            x.copyID = UUID().uuidString; n += 1
        }
        if n > 0 { try? ctx.save() }
        return n
    }

    /// Merge records that share a `uid`. Every device keeps the copy with the smallest copy ID, so two devices
    /// tidying up at the same time make the same choice and never delete both copies. A merged book keeps all
    /// sessions and notes from every copy, and fills in a cover or rating that only one copy had.
    /// Returns how many duplicate records were removed.
    @discardableResult
    nonisolated static func dedupe(_ ctx: ModelContext) -> Int {
        var removed = 0

        // 1. Books: move everything onto the kept copy and save, then remove the others.
        let books = (try? ctx.fetch(FetchDescriptor<Book>())) ?? []
        var extraBooks: [Book] = []
        for group in Dictionary(grouping: books, by: \.uid).values where group.count > 1 {
            guard let keep = keeper(group, id: \.copyID) else { continue }
            for dup in group where dup !== keep {
                for s in dup.sessions ?? [] { s.book = keep }
                for n in dup.notes ?? [] { n.book = keep }
                if keep.coverData == nil, let c = dup.coverData { keep.coverData = c }
                if keep.rating == nil, let r = dup.rating { keep.rating = r }
                if keep.isbn == nil, let i = dup.isbn { keep.isbn = i }
                if keep.finishedDay == nil, let d = dup.finishedDay { keep.finishedDay = d }
                if dup.lastAt.seconds > keep.lastAt.seconds { keep.lastAt = dup.lastAt }
                extraBooks.append(dup)
            }
        }
        if !extraBooks.isEmpty {
            try? ctx.save()  // the sessions and notes are now attached to the kept book, so deleting the copy can't take them
            for b in extraBooks where (b.sessions ?? []).isEmpty && (b.notes ?? []).isEmpty {
                ctx.delete(b); removed += 1
            }
        }

        // 2. Sessions and notes: identical copies, so just keep one.
        let sessions = (try? ctx.fetch(FetchDescriptor<ReadingSession>())) ?? []
        for group in Dictionary(grouping: sessions, by: \.uid).values where group.count > 1 {
            guard let keep = keeper(group, id: \.copyID) else { continue }
            for dup in group where dup !== keep { ctx.delete(dup); removed += 1 }
        }
        let notes = (try? ctx.fetch(FetchDescriptor<BookNote>())) ?? []
        for group in Dictionary(grouping: notes, by: \.uid).values where group.count > 1 {
            guard let keep = keeper(group, id: \.copyID) else { continue }
            for dup in group where dup !== keep { ctx.delete(dup); removed += 1 }
        }

        if removed > 0 { try? ctx.save() }
        return removed
    }

    /// The copy every device agrees to keep; nil while any copy is still waiting for its copy ID.
    nonisolated private static func keeper<T>(_ group: [T], id: KeyPath<T, String>) -> T? {
        guard group.allSatisfy({ !$0[keyPath: id].isEmpty }) else { return nil }
        return group.min { $0[keyPath: id] < $1[keyPath: id] }
    }

    // MARK: - Status for Settings

    enum Status: Equatable {
        case on, turnedOff, signedOut, restricted, unavailable, checking
        var title: String {
            switch self {
            case .on: return "On"
            case .turnedOff: return "Off"
            case .signedOut: return "Off"
            case .restricted: return "Off"
            case .unavailable: return "Not available"
            case .checking: return "Checking…"
            }
        }
        var detail: String {
            switch self {
            case .on: return "Your books, sessions, notes and covers stay in sync on every iPhone and iPad signed in to your Apple Account. Changes can take a minute to appear."
            case .turnedOff: return "Your library is kept on this device only. Anything already in iCloud stays there, and syncing picks up again when you turn this back on."
            case .signedOut: return "Sign in to iCloud in the Settings app (tap your name, then iCloud) and make sure Pageturner is allowed to use it, to keep your library in sync and safe if you change phones."
            case .restricted: return "iCloud is restricted on this device (for example by Screen Time or a work profile), so your library is kept on this device only."
            case .unavailable: return "Your library is kept on this device only."
            case .checking: return ""
            }
        }
    }

    static func status() async -> Status {
        guard Persistence.syncEnabled else { return .turnedOff }
        guard let id = Persistence.cloudContainerID else {
            return FileManager.default.ubiquityIdentityToken != nil ? .on : .unavailable
        }
        do {
            switch try await CKContainer(identifier: id).accountStatus() {
            case .available: return .on
            case .restricted: return .restricted
            case .noAccount, .couldNotDetermine, .temporarilyUnavailable: return .signedOut
            @unknown default: return .signedOut
            }
        } catch {
            return .signedOut
        }
    }
}
