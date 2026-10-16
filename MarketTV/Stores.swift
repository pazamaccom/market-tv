import Foundation

/// US Market Health daily record: GET /api/latest plus the dashboard's own interpretation code.
@MainActor
final class MarketStore: ObservableObject {
    @Published private(set) var snapshot = J(nil)
    @Published private(set) var selection = J(nil)
    @Published private(set) var model = J(nil)
    @Published private(set) var commit: String?
    @Published private(set) var error: String?
    @Published private(set) var interpretationError: String?
    @Published private(set) var updated: Date?
    @Published private(set) var loading = false

    private let interpreter = Interpreter()
    private var interpreterBase: String?

    func refresh(base: String, demo: Bool) async {
        loading = true
        defer { loading = false }
        do {
            let data = try await API.data(base, "/api/latest?mode=\(demo ? "demo" : "live")")
            let root = try API.parse(data)
            let commit = root["application"]["commit"].string
            // Reload the interpretation code whenever the server's deployed commit changes.
            if !interpreter.isReady || interpreterBase != base || interpreter.loadedCommit != commit {
                do {
                    let js = try await API.data(base, "/app.js")
                    try interpreter.load(appJS: String(decoding: js, as: UTF8.self), commit: commit)
                    interpreterBase = base
                } catch {
                    interpretationError = API.describe(error)
                }
            }
            snapshot = root["snapshot"]
            selection = root["selection"]
            self.commit = commit
            if interpreter.isReady {
                if let m = interpreter.interpret(data) {
                    model = m
                    interpretationError = nil
                } else {
                    model = J(nil)
                    interpretationError = interpreter.lastError ?? "Interpretation failed."
                }
            }
            error = nil
            updated = Date()
        } catch {
            self.error = API.describe(error)
        }
    }

    func warning(_ card: J) -> (name: String, meaning: String) {
        if let w = interpreter.warningLanguage(card) { return w }
        return (card["name"].string ?? card["id"].string ?? "Signal", card["meaning"].string ?? "")
    }

    /// Sorted (date, value) pairs from snapshot.histories[key].
    func history(_ key: String, last n: Int = 120) -> [(date: Date, value: Double)] {
        let points = snapshot["histories"][key].object.compactMap { (k, v) -> (date: Date, value: Double)? in
            guard let d = Fmt.day(k), let x = v.finite else { return nil }
            return (d, x)
        }.sorted { $0.date < $1.date }
        return Array(points.suffix(n))
    }
}

/// Provisional intraday view: GET /api/today.
@MainActor
final class TodayStore: ObservableObject {
    @Published private(set) var today = J(nil)
    @Published private(set) var error: String?
    @Published private(set) var updated: Date?

    func refresh(base: String, demo: Bool) async {
        do {
            today = try API.parse(try await API.data(base, "/api/today?mode=\(demo ? "demo" : "live")"))
            error = nil
            updated = Date()
        } catch {
            self.error = API.describe(error)
        }
    }
}

struct DashboardInfo: Identifiable {
    let id: String
    let name: String
    let port: Int
    let onTV: String?
}

/// P | ANALYTICS hub reachability: GET /api/status (HTTP reachability only, not data freshness).
@MainActor
final class HubStore: ObservableObject {
    static let dashboards: [DashboardInfo] = [
        .init(id: "market", name: "US Market Health", port: 8085, onTV: "On this TV: Market Health, Downturn and Today tabs"),
        .init(id: "turkey", name: "Turkey Fund Tracker", port: 8081, onTV: nil),
        .init(id: "stocks", name: "Stock Attractiveness", port: 8083, onTV: nil),
        .init(id: "drawdown", name: "US Drawdown and Downturn", port: 8080, onTV: nil),
        .init(id: "yield", name: "Yield Curve", port: 8084, onTV: nil),
        .init(id: "alpha", name: "Alpha Signal Scout", port: 8082, onTV: nil),
        .init(id: "btc", name: "BTC Trading Bot", port: 8086, onTV: nil),
    ]

    @Published private(set) var online: [String: Bool] = [:]
    @Published private(set) var urls: [String: String] = [:]
    @Published private(set) var error: String?
    @Published private(set) var updated: Date?

    func refresh(base: String) async {
        do {
            let rows = try API.parse(try await API.data(base, "/api/status")).array
            var states: [String: Bool] = [:]
            var links: [String: String] = [:]
            for row in rows {
                guard let id = row["id"].string else { continue }
                states[id] = row["online"].bool ?? false
                if let url = row["url"].string { links[id] = url }
            }
            online = states
            urls = links
            error = nil
            updated = Date()
        } catch {
            self.error = API.describe(error)
        }
    }
}
