import Foundation

/// Display formatting mirroring the web dashboard helpers (fmt / signed / pct in app.js).
enum Fmt {
    static func fixed(_ v: Double?, _ digits: Int = 2, _ suffix: String = "") -> String {
        guard let v, v.isFinite else { return "Unavailable" }
        return String(format: "%.\(digits)f", v) + suffix
    }

    static func signed(_ v: Double?, _ digits: Int = 1, _ suffix: String = "") -> String {
        guard let v, v.isFinite else { return "Unavailable" }
        return (v > 0 ? "+" : "") + String(format: "%.\(digits)f", v) + suffix
    }

    static func pct(_ v: Double?) -> String { fixed(v.map { $0 * 100 }, 1, "%") }

    static func count(_ j: J) -> String { j.int.map(String.init) ?? "—" }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dayPrinter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private static let newYork: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let local: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func day(_ s: String) -> Date? { dayParser.date(from: String(s.prefix(10))) }
    static func day(_ d: Date) -> String { dayPrinter.string(from: d) }
    static func ny(_ d: Date) -> String { newYork.string(from: d) }
    static func localTime(_ d: Date) -> String { local.string(from: d) }

    static func iso(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
