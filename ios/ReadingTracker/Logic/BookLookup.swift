import Foundation
import UIKit

/// Finds a book's details and cover from its ISBN. Only the ISBN is sent anywhere.
/// Three free catalogues are asked at the same time; whatever they find is combined.
enum BookLookup {
    struct Found: Equatable, Sendable {
        var title: String
        var author: String
        var pages: Int?
        var coverURL: URL?
    }

    enum Outcome: Equatable, Sendable {
        case found(Found)
        /// The catalogues answered but don't know this ISBN (common for very new or local editions).
        case notFound
        /// None of the catalogues could be reached.
        case offline
    }

    /// What one catalogue said.
    private enum Answer: Sendable {
        case found(Found)
        case none
        case unreachable
    }

    static func lookup(isbn raw: String) async -> Outcome {
        guard let isbn = ISBN.normalize(raw) else { return .notFound }
        async let a = openLibraryBook(isbn)
        async let b = openLibrarySearch(isbn)
        async let c = googleBooks(isbn)
        let answers = await [a, b, c]
        let finds = answers.compactMap { if case .found(let f) = $0 { return f } else { return nil } }
        if finds.isEmpty {
            return answers.allSatisfy { if case .unreachable = $0 { return true } else { return false } } ? .offline : .notFound
        }
        return .found(merge(finds))
    }

    /// Kept for callers that only need the details.
    static func find(isbn: String) async -> Found? {
        if case .found(let f) = await lookup(isbn: isbn) { return f }
        return nil
    }

    /// Combines answers: the first title, the longest author list, the most common page count, the first cover.
    static func merge(_ finds: [Found]) -> Found {
        var out = finds[0]
        if let author = finds.map(\.author).max(by: { $0.count < $1.count }), !author.isEmpty { out.author = author }
        let pages = finds.compactMap(\.pages).filter { $0 > 0 }
        if !pages.isEmpty {
            let counts = Dictionary(grouping: pages, by: { $0 }).mapValues(\.count)
            out.pages = counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
        }
        out.coverURL = finds.compactMap(\.coverURL).first
        return out
    }

    /// Downloads a cover: Open Library by ISBN first, then the given fallback URL. Returns a resized JPEG.
    static func cover(isbn: String?, fallback: URL?) async -> Data? {
        var urls: [URL] = []
        if let fallback { urls.append(fallback) }
        if let isbn = isbn.flatMap(ISBN.normalize),
           let u = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false") { urls.append(u) }
        for url in urls {
            if let jpeg = await download(url) { return jpeg }
        }
        return nil
    }

    /// Downloads a picture and shrinks it to cover size.
    static func download(_ url: URL) async -> Data? {
        guard case .ok(let data) = await fetch(url), data.count > 1000 else { return nil }
        return Covers.thumbnail(data, maxSide: 600)
    }

    // MARK: catalogues

    private static func openLibraryBook(_ isbn: String) async -> Answer {
        guard let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data") else { return .none }
        switch await fetch(url) {
        case .unreachable: return .unreachable
        case .failed: return .none
        case .ok(let data):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let r = json["ISBN:\(isbn)"] as? [String: Any],
                  let title = r["title"] as? String else { return .none }
            let subtitle = r["subtitle"] as? String
            let authors = (r["authors"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let cover = (r["cover"] as? [String: Any])?["large"] as? String
            return .found(Found(title: subtitle.map { "\(title): \($0)" } ?? title,
                                author: authors.joined(separator: ", "),
                                pages: r["number_of_pages"] as? Int,
                                coverURL: cover.flatMap(URL.init(string:))))
        }
    }

    private static func openLibrarySearch(_ isbn: String) async -> Answer {
        guard let url = URL(string: "https://openlibrary.org/search.json?isbn=\(isbn)&limit=1&fields=title,subtitle,author_name,number_of_pages_median,cover_i") else { return .none }
        switch await fetch(url) {
        case .unreachable: return .unreachable
        case .failed: return .none
        case .ok(let data):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let doc = (json["docs"] as? [[String: Any]])?.first,
                  let title = doc["title"] as? String else { return .none }
            let subtitle = doc["subtitle"] as? String
            let cover = (doc["cover_i"] as? Int).flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg") }
            return .found(Found(title: subtitle.map { "\(title): \($0)" } ?? title,
                                author: ((doc["author_name"] as? [String]) ?? []).joined(separator: ", "),
                                pages: doc["number_of_pages_median"] as? Int,
                                coverURL: cover))
        }
    }

    private static func googleBooks(_ isbn: String) async -> Answer {
        guard let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)") else { return .none }
        switch await fetch(url) {
        case .unreachable: return .unreachable
        case .failed: return .none
        case .ok(let data):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let item = (json["items"] as? [[String: Any]])?.first,
                  let v = item["volumeInfo"] as? [String: Any],
                  let title = v["title"] as? String else { return .none }
            let subtitle = v["subtitle"] as? String
            let links = v["imageLinks"] as? [String: Any]
            let thumb = ((links?["thumbnail"] as? String) ?? (links?["smallThumbnail"] as? String))?
                .replacingOccurrences(of: "http://", with: "https://")
                .replacingOccurrences(of: "&edge=curl", with: "")
            return .found(Found(title: subtitle.map { "\(title): \($0)" } ?? title,
                                author: ((v["authors"] as? [String]) ?? []).joined(separator: ", "),
                                pages: v["pageCount"] as? Int,
                                coverURL: thumb.flatMap(URL.init(string:))))
        }
    }

    // MARK: network

    private enum Fetch: Sendable {
        case ok(Data)
        /// The server answered, but not with something useful (e.g. 404, or a busy-server error).
        case failed
        /// No connection, timed out, or the server couldn't be found.
        case unreachable
    }

    private static func fetch(_ url: URL) async -> Fetch {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Pageturner-iOS (book lookup)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return .failed }
            return .ok(data)
        } catch {
            return .unreachable
        }
    }
}

enum Covers {
    /// Shrinks an image so its longest side is at most `maxSide` points, as JPEG.
    static func thumbnail(_ data: Data, maxSide: CGFloat) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 1 else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.82)
    }
}
