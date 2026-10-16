import SwiftUI

/// Stock Attractiveness (port 8083): GET /api/overview and /api/alerts.
struct StocksSection: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var feed = FeedStore()

    var body: some View {
        TabView {
            StocksRanked(feed: feed).tabItem { Text("Ranked") }
            StocksMoves(feed: feed).tabItem { Text("Moves & Alerts") }
        }
        .background(Theme.background.ignoresSafeArea())
        .task(id: settings.refreshToken) {
            await poll(every: 600) { await feed.load(base: settings.dashboardBase(port: 8083), json: ["/api/overview", "/api/alerts"]) }
        }
    }
}

enum StockStyle {
    static func tierColor(_ t: String?) -> Color {
        switch t {
        case "A": return Theme.supportive
        case "B": return Theme.accent
        case "C": return Theme.mixed
        case "D": return Theme.adverse
        default: return Theme.unavailable
        }
    }

    static func stanceColor(_ q: String?) -> Color {
        switch q {
        case "act": return Theme.supportive
        case "accumulate": return Theme.accent
        case "trade": return Theme.mixed
        default: return Theme.unavailable
        }
    }

    static func price(_ v: Double?, _ ccy: String?) -> String {
        guard let v, v.isFinite else { return "—" }
        return Fmt.grouped(v, v >= 1000 ? 0 : 2) + (ccy.map { " \($0)" } ?? "")
    }
}

struct StocksRanked: View {
    @ObservedObject var feed: FeedStore

    var body: some View {
        let o = feed["/api/overview"]
        let rows = o["rows"].array
        let ranked = rows.filter { $0["ranked"].bool == true }
        let unranked = rows.count - ranked.count
        let unseen = feed["/api/alerts"]["unseen"].int
        return Screen {
            ScreenHeader(title: "Stock Attractiveness",
                         subtitle: "Scores for \(Fmt.dayLabel(o["date"].string)) · \(rows.count) names in the universe",
                         updated: feed.updated)
            if let e = feed.error { Banner(text: e) }
            if o.exists {
                HStack(alignment: .top, spacing: 18) {
                    KPI(title: "Ranked", value: Fmt.count(o["n_ranked"]), sub: unranked > 0 ? "\(unranked) not ranked" : nil)
                    KPI(title: "Above the hurdle", value: Fmt.count(o["n_above"]), sub: "Expected return above the hurdle")
                    KPI(title: "Tier A", value: "\(rows.filter { $0["tier"].string == "A" }.count)", color: Theme.supportive)
                    KPI(title: "Tier B", value: "\(rows.filter { $0["tier"].string == "B" }.count)", color: Theme.accent)
                    KPI(title: "Unseen alerts", value: unseen.map(String.init) ?? "—", color: (unseen ?? 0) > 0 ? Theme.mixed : Theme.ink)
                }
                .fixedSize(horizontal: false, vertical: true)

                SectionTitle(text: "Ranked names", note: "Owner's score 3–5 years · tactical 6–18 months")
                header
                ForEach(Array(ranked.enumerated()), id: \.offset) { i, r in row(i + 1, r) }
                Note(text: "Tier letters are shown only for names whose expected return clears the hurdle; \"below\" means it does not. Price versus buy-below is how far the price sits from the buy-below level (negative = already below it).")
            } else if !feed.attempted {
                LoadingLine(text: "Loading Stock Attractiveness…")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HeaderCell(text: "#", width: 50)
            HeaderCell(text: "Company")
            HeaderCell(text: "Tier", width: 100, alignment: .center)
            HeaderCell(text: "Owner", width: 100, alignment: .trailing)
            HeaderCell(text: "Tactical", width: 110, alignment: .trailing)
            HeaderCell(text: "Exp. return", width: 140, alignment: .trailing)
            HeaderCell(text: "Price", width: 190, alignment: .trailing)
            HeaderCell(text: "vs buy-below", width: 160, alignment: .trailing)
            HeaderCell(text: "Stance", width: 160, alignment: .center)
        }
        .padding(.horizontal, 20)
    }

    private func row(_ n: Int, _ r: J) -> some View {
        let tier = r["tier"].string
        let dist = r["distance_to_buy_below"].finite
        return FocusRow {
            HStack(spacing: 12) {
                Cell(text: "\(n)", width: 50, alignment: .leading, color: Theme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r["name"].string ?? r["company_id"].string ?? "").font(.system(size: 23, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(r["industry_name"].string ?? "").font(.system(size: 17)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Pill(text: tier ?? "—", color: StockStyle.tierColor(tier)).frame(width: 100)
                Cell(text: Fmt.fixed(r["owner_score"].finite, 1), width: 100, weight: .semibold)
                Cell(text: Fmt.fixed(r["tactical_score"].finite, 1), width: 110)
                Cell(text: Fmt.pct(r["expected_return"].finite), width: 140,
                     color: r["above_hurdle"].bool == true ? Theme.supportive : Theme.ink, weight: .semibold)
                Cell(text: StockStyle.price(r["price"].finite, r["price_currency"].string), width: 190)
                Cell(text: Fmt.signed(dist.map { $0 * 100 }, 0, "%"), width: 160,
                     color: (dist ?? 1) <= 0 ? Theme.supportive : Theme.ink)
                Pill(text: r["quadrant"].string ?? "—", color: StockStyle.stanceColor(r["quadrant"].string)).frame(width: 160)
            }
        }
    }
}

struct StocksMoves: View {
    @ObservedObject var feed: FeedStore

    var body: some View {
        let o = feed["/api/overview"]
        var names: [String: String] = [:]
        for r in o["rows"].array { if let id = r["company_id"].string { names[id] = r["name"].string ?? id } }
        let moves = o["changed"]["moves"].array
        let tierChanges = o["changed"]["tier_changes"].array
        let alerts = feed["/api/alerts"]["alerts"].array
        return Screen {
            ScreenHeader(title: "Moves & Alerts",
                         subtitle: "Stock Attractiveness · changes since \(Fmt.dayLabel(o["changed"]["previous"].string))",
                         updated: feed.updated)
            if let e = feed.error { Banner(text: e) }
            if o.exists {
                SectionTitle(text: "Biggest moves", note: "\(moves.count) names · \(tierChanges.count) tier changes")
                ForEach(Array(moves.enumerated()), id: \.offset) { _, m in
                    let total = m["total"].finite.map { $0 * 100 }
                    FocusRow {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(names[m["company_id"].string ?? ""] ?? m["company_id"].string ?? "")
                                    .font(.system(size: 23, weight: .semibold)).foregroundStyle(Theme.ink)
                                Text("Driver: \(m["largest"].string ?? "—")").font(.system(size: 18)).foregroundStyle(Theme.muted)
                            }
                            .frame(width: 380, alignment: .leading)
                            Text(Fmt.signed(total, 0, " pts")).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.ink)
                                .frame(width: 140, alignment: .trailing)
                            Text(m["sentence"].string ?? "").font(.system(size: 19)).foregroundStyle(Theme.ink)
                                .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            if !alerts.isEmpty {
                SectionTitle(text: "Alerts", note: "\(feed["/api/alerts"]["unseen"].int ?? 0) unseen")
                ForEach(Array(alerts.prefix(30).enumerated()), id: \.offset) { _, a in
                    let kind = a["kind"].string ?? "alert"
                    FocusRow {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(Fmt.dayLabel(a["date"].string)).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                                Pill(text: kind.replacingOccurrences(of: "_", with: " "),
                                     color: kind == "buy_below" ? Theme.supportive : kind == "digest" ? Theme.unavailable : Theme.accent)
                                if a["seen_at"].string == nil { Text("Unseen").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.mixed) }
                            }
                            .frame(width: 200, alignment: .leading)
                            Text(a["cause"].string ?? "").font(.system(size: 19)).foregroundStyle(Theme.ink)
                                .lineLimit(6).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            if !o.exists && !feed.attempted { LoadingLine(text: "Loading…") }
        }
    }
}
