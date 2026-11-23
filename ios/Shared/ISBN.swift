import Foundation

enum ISBN {
    static func ean13IsValid(_ s: String) -> Bool {
        let digits = s.compactMap(\.wholeNumberValue)
        guard digits.count == 13 else { return false }
        let total = digits.enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 1 ? 3 : 1) }
        return total % 10 == 0
    }

    /// Turns a scanned or typed code into a 13-digit ISBN, or nil if it isn't a book ISBN.
    /// Accepts ISBN-13 (978/979…) and ISBN-10 (converted to 13).
    static func normalize(_ raw: String) -> String? {
        let s = raw.uppercased().filter { $0.isNumber || $0 == "X" }
        if s.count == 13, s.hasPrefix("978") || s.hasPrefix("979"), !s.contains("X"), ean13IsValid(s) { return s }
        if s.count == 10, s.dropLast().allSatisfy(\.isNumber) {
            let chars = Array(s)
            var total = 0
            for (i, c) in chars.enumerated() {
                let v = c == "X" ? 10 : (c.wholeNumberValue ?? -100)
                if v < 0 || (c == "X" && i != 9) { return nil }
                total += (10 - i) * v
            }
            guard total % 11 == 0 else { return nil }
            let body = "978" + String(chars.prefix(9))
            let digits = body.compactMap(\.wholeNumberValue)
            let sum = digits.enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 1 ? 3 : 1) }
            return body + String((10 - sum % 10) % 10)
        }
        return nil
    }
}
