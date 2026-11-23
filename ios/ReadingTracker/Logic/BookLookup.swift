import Foundation
import UIKit

/// Finds a book's details and cover from its ISBN. Only the ISBN is sent anywhere.
enum BookLookup {
    struct Found: Equatable {
        var title: String
        var author: String
        var pages: Int?
        var coverURL: URL?
    }

    static func find(isbn: String) async -> Found? {
        var found = await openLibrary(isbn)
        if found == nil || found?.pages == nil || found?.coverURL == nil, let g = await googleBooks(isbn) {
            if var f = found {
                if f.pages == nil { f.pages = g.pages }
                if f.coverURL == nil { f.coverURL = g.coverURL }
                if f.author.isEmpty { f.author = g.author }
                found = f
            } else {
                found = g
            }
        }
        return found
    }

    /// Downloads a cover: Open Library by ISBN first, then the given fallback URL. Returns a resized JPEG.
    static func cover(isbn: String?, fallback: URL?) async -> Data? {
        var urls: [URL] = []
        if let isbn, let u = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false") { urls.append(u) }
        if let fallback { urls.append(fallback) }
        for url in urls {
            if let data = try? await get(url), let jpeg = Covers.thumbnail(data, maxSide: 600), data.count > 1000 {
                return jpeg
            }
        }
        return nil
    }

    private static func openLibrary(_ isbn: String) async -> Found? {
        guard let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data"),
              let data = try? await get(url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = json["ISBN:\(isbn)"] as? [String: Any],
              let title = r["title"] as? String else { return nil }
        let subtitle = r["subtitle"] as? String
        let authors = (r["authors"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let cover = (r["cover"] as? [String: Any])?["large"] as? String
        return Found(title: subtitle.map { "\(title): \($0)" } ?? title,
                     author: authors.joined(separator: ", "),
                     pages: r["number_of_pages"] as? Int,
                     coverURL: cover.flatMap(URL.init(string:)))
    }

    private static func googleBooks(_ isbn: String) async -> Found? {
        guard let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)"),
              let data = try? await get(url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = (json["items"] as? [[String: Any]])?.first,
              let v = item["volumeInfo"] as? [String: Any],
              let title = v["title"] as? String else { return nil }
        let subtitle = v["subtitle"] as? String
        let thumb = ((v["imageLinks"] as? [String: Any])?["thumbnail"] as? String)?
            .replacingOccurrences(of: "http://", with: "https://")
        return Found(title: subtitle.map { "\(title): \($0)" } ?? title,
                     author: ((v["authors"] as? [String]) ?? []).joined(separator: ", "),
                     pages: v["pageCount"] as? Int,
                     coverURL: thumb.flatMap(URL.init(string:)))
    }

    private static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("ReadingTracker-iOS", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
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
