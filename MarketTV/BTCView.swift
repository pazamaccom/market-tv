import SwiftUI

/// BTC Trading Bot (port 8086) serves only HTML, so the TV reads "/" and extracts the figures.
/// Read-only: the page's Halt / Flatten / Resume controls (POST /control) are never touched or shown.

// MARK: Extraction (Foundation only)

struct BTCTile {
    let label: String
    let value: String
    let sub: String
}

struct BTCCoin: Identifiable {
    let id: String
    let name: String
    let contracts: String?
    let notional: String?
    let held: String?
    let target: String?
    let trend: String?
    let volatility: String?
    let today: String?
}

struct BTCLevel {
    let price: String
    let distance: String?
    let note: String?
}

struct BTCSignals: Identifiable {
    var id: String { coin }
    let coin: String
    let now: String?
    let sell: BTCLevel?
    let buy: BTCLevel?
    let weakens: BTCLevel?
    let strengthens: BTCLevel?
}

struct BTCPage {
    var mode: String?
    var status: String?
    var statusClass: String?
    var checked: Date?
    var value: String?
    var sinceYesterday: String?
    var tiles: [String: BTCTile] = [:]
    var coins: [BTCCoin] = []
    var aboveStop: String?
    var fallToStop: String?
    var stop: String?
    var window: String?
    var signals: [BTCSignals] = []
    var comingUp: [(String, String)] = []

    func tile(_ label: String) -> BTCTile? { tiles[label] }

    /// nil when none of the page's anchors (id="band", data-sec sections) are present.
    static func parse(_ html: String) -> BTCPage? {
        let band = HTMLText.matches("<div([^>]*\\bid=\"band\"[^>]*)>(.*?)</div>", in: html).first
        let sec = { (name: String) -> String? in HTMLText.matches("<section data-sec=\"\(name)\"[^>]*>(.*?)</section>", in: html).first?[1] }
        guard band != nil || html.contains("data-sec=\"") else { return nil }
        var p = BTCPage()

        if let b = band {
            p.statusClass = HTMLText.first("class=\"([^\"]*)\"", in: b[1])
            p.mode = HTMLText.first("id=\"chip\"[^>]*>(.*?)</span>", in: b[2])
            p.status = HTMLText.first("id=\"band-words\"[^>]*>(.*?)</span>", in: b[2])
            p.checked = Fmt.iso(HTMLText.first("class=\"t\" data-utc=\"([^\"]+)\"", in: b[2]))
        }

        func tiles(_ s: String) -> [BTCTile] {
            HTMLText.matches("<div[^>]*>\\s*<div[^>]*>([^<]+)</div>\\s*<div[^>]*>([^<]+)</div>\\s*<div[^>]*>([^<]+)</div>\\s*</div>", in: s)
                .map { BTCTile(label: HTMLText.clean($0[1]), value: HTMLText.clean($0[2]), sub: HTMLText.clean($0[3])) }
        }

        if let s = sec("The account") {
            p.value = HTMLText.first(">\\s*(\\$[\\d,]+)\\s*</div>", in: s)
            p.sinceYesterday = HTMLText.first("<span[^>]*>([^<]+)</span>\\s*<span[^>]*>since yesterday</span>", in: s)
            for t in tiles(s) { p.tiles[t.label] = t }
        }

        if let s = sec("Today") {
            let blocks = s.components(separatedBy: "data-coin=\"").dropFirst()
            p.coins = blocks.compactMap { block in
                guard let id = HTMLText.first("^([a-z0-9]+)\"", in: block),
                      let head = HTMLText.matches("<span[^>]*>([^<]+)</span>\\s*<span[^>]*>([^<]*)</span>", in: block).first else { return nil }
                let parts = HTMLText.clean(head[2]).components(separatedBy: " · ")
                let pct = HTMLText.matches("<span[^>]*>([^<]+%)</span>\\s*<span[^>]*>target ([^<]+)</span>", in: block).first
                let trend = HTMLText.matches("aria-label=\"(\\d+) of (\\d+) trend rules", in: block).first
                return BTCCoin(id: id, name: HTMLText.clean(head[1]),
                               contracts: id == "both" ? nil : parts.first.flatMap { $0.hasPrefix("$") ? nil : $0 },
                               notional: parts.first { $0.hasPrefix("$") },
                               held: pct.map { HTMLText.clean($0[1]) },
                               target: pct.map { HTMLText.clean($0[2]) },
                               trend: trend.map { "\($0[1]) of \($0[2])" },
                               volatility: HTMLText.first("Volatility <span[^>]*>([^<]+)</span>", in: block),
                               today: HTMLText.first("<span[^>]*>Today:</span>([^<]*)</div>", in: block))
            }
        }

        if let s = sec("Risk") {
            p.aboveStop = HTMLText.first(">([^<>]*the stop)</div>", in: s)
            p.fallToStop = HTMLText.first("fall ([\\d.]+%) from here", in: s)
            p.stop = HTMLText.first("<span[^>]*>Stop</span>\\s*(\\$[\\d,]+)", in: s)
            for t in tiles(s) { p.tiles[t.label] = t }
        }

        if let s = sec("Next trade") {
            p.window = HTMLText.first("for the window ([^<]+)</div>", in: localized(s))
            p.signals = s.components(separatedBy: "<details").compactMap { chunk in
                guard let head = HTMLText.matches("<span[^>]*>([A-Z]{2,6})</span>\\s*<span[^>]*>[^<]*?(\\$[\\d,.]+) now</span>", in: chunk).first else { return nil }
                var levels: [String: BTCLevel] = [:]
                for m in HTMLText.matches("(Sell signal|Buy signal|Trend weakens|Trend strengthens) at:? <b[^>]*>([^<]+)</b>\\s*(?:<span[^>]*>\\(([^)<]*)\\)</span>)?(.*?)</div>", in: chunk) {
                    let note = HTMLText.clean(m[4])
                    levels[m[1]] = BTCLevel(price: HTMLText.clean(m[2]), distance: m[3].isEmpty ? nil : HTMLText.clean(m[3]), note: note.isEmpty ? nil : note)
                }
                return BTCSignals(coin: head[1], now: head[2], sell: levels["Sell signal"], buy: levels["Buy signal"],
                                  weakens: levels["Trend weakens"], strengthens: levels["Trend strengthens"])
            }
        }

        if let s = sec("What comes next") {
            p.comingUp = HTMLText.matches("<div[^>]*>\\s*<span[^>]*>([^<]+)</span>\\s*<span[^>]*>(.*?)</span>\\s*</div>", in: localized(s))
                .map { (HTMLText.clean($0[1]), HTMLText.clean($0[2])) }
        }
        return p
    }

    /// Replaces the page's UTC time stamps (<span class="t" data-utc=…>) with times in this TV's time zone,
    /// as the page's own script does in a browser.
    static func localized(_ s: String) -> String {
        var out = s
        for m in HTMLText.matches("<span class=\"t\" data-utc=\"([^\"]+)\"[^>]*>[^<]*</span>", in: s) {
            if let d = Fmt.iso(m[1]) { out = out.replacingOccurrences(of: m[0], with: time(d)) }
        }
        return out
    }

    static func time(_ d: Date, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = Calendar.current.isDate(d, inSameDayAs: now) ? "HH:mm" : "EEE d MMM, HH:mm"
        return f.string(from: d)
    }
}

// MARK: Screen

struct BTCSection: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var feed = FeedStore()

    var body: some View {
        BTCScreen(feed: feed)
            .task(id: settings.refreshToken) {
                // GET "/" only. The page refreshes itself every minute.
                await poll(every: 60) {
                    await feed.load(base: settings.dashboardBase(port: 8086), json: [], text: ["/"])
                }
            }
    }
}

struct BTCScreen: View {
    @ObservedObject var feed: FeedStore

    var body: some View {
        let html = feed.text["/"]
        let page = html.flatMap(BTCPage.parse)
        let stale = page?.checked.map { Date().timeIntervalSince($0) > 15 * 60 } ?? false
        return Screen {
            ScreenHeader(title: "BTC Trading Bot", subtitle: "Trend sleeve · BTC and ETH futures · read-only",
                         badge: page?.mode, badgeColor: BTCStyle.statusColor(page), updated: feed.updated)
            if let e = feed.error { Banner(text: e) }
            if let p = page {
                status(p, stale: stale)
                if stale, let c = p.checked {
                    Banner(text: "The bot page was last checked at \(BTCPage.time(c)) (\(Int(Date().timeIntervalSince(c) / 60)) minutes ago). The figures below may be out of date.", color: Theme.mixed)
                }
                account(p)
                SectionTitle(text: "Positions", note: "held vs today's target · trend rules long")
                HStack(alignment: .top, spacing: 18) {
                    if p.coins.isEmpty { KPI(title: "Positions", value: "Unavailable", color: Theme.unavailable) }
                    ForEach(p.coins) { coinPanel($0) }
                }
                .fixedSize(horizontal: false, vertical: true)
                SectionTitle(text: "Risk")
                risk(p)
                SectionTitle(text: "Buy and sell signals", note: p.window.map { "for the window \($0)" })
                HStack(alignment: .top, spacing: 18) {
                    if p.signals.isEmpty { KPI(title: "Signals", value: "Unavailable", color: Theme.unavailable) }
                    ForEach(p.signals) { signalPanel($0) }
                }
                .fixedSize(horizontal: false, vertical: true)
                SectionTitle(text: "Coming up")
                comingUp(p)
                Note(text: "Times are shown in this Apple TV's time zone. Halt, flatten and resume are only available on the web page.")
            } else if html != nil {
                Banner(text: "The BTC Trading Bot page loaded but its layout was not recognised (it may have changed). Open it on the phone: http://100.127.41.102:8086/", color: Theme.mixed)
            } else if !feed.attempted {
                LoadingLine(text: "Loading BTC Trading Bot…")
            }
        }
    }

    private func status(_ p: BTCPage, stale: Bool) -> some View {
        Panel {
            HStack(spacing: 18) {
                Circle().fill(BTCStyle.statusColor(p)).frame(width: 30, height: 30)
                Text(p.status ?? "Status unavailable").font(.system(size: 38, weight: .bold)).foregroundStyle(BTCStyle.statusColor(p))
                Spacer()
                Text("Checked \(p.checked.map { BTCPage.time($0) } ?? "Unavailable") · updates every minute")
                    .font(.system(size: 22)).foregroundStyle(stale ? Theme.mixed : Theme.muted)
            }
        }
    }

    private func account(_ p: BTCPage) -> some View {
        HStack(alignment: .top, spacing: 18) {
            KPI(title: "Account value", value: p.value ?? "Unavailable",
                sub: p.sinceYesterday.map { "\($0) since yesterday" } ?? "Since yesterday: Unavailable",
                color: p.value == nil ? Theme.unavailable : Theme.ink, valueSize: 50)
                .frame(maxWidth: .infinity)
            ForEach(["Last day", "Last 7 days", "This month", "Since first order"], id: \.self) { label in
                let t = p.tile(label)
                KPI(title: label, value: t?.value ?? "Unavailable", sub: t?.sub, color: BTCStyle.signColor(t?.value))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func coinPanel(_ c: BTCCoin) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.name).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    if let t = c.trend { Pill(text: "Trend \(t)", color: Theme.accent) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(c.held ?? "Unavailable").font(.system(size: 46, weight: .heavy))
                        .foregroundStyle(c.held == nil ? Theme.unavailable : Theme.ink)
                    Text("held · target \(c.target ?? "Unavailable")").font(.system(size: 22)).foregroundStyle(Theme.muted)
                }
                fact("Notional", c.notional)
                if c.id != "both" {
                    fact("Contracts", c.contracts)
                    fact("Volatility", c.volatility)
                }
                if let t = c.today {
                    Text("Today: \(t)").font(.system(size: 19)).foregroundStyle(Theme.muted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func risk(_ p: BTCPage) -> some View {
        let var95 = p.tile("VaR 95%, 1 day"), var99 = p.tile("VaR 99%, 1 day"), margin = p.tile("Margin used")
        return HStack(alignment: .top, spacing: 18) {
            KPI(title: "Distance to the stop", value: p.aboveStop?.replacingOccurrences(of: " the stop", with: "") ?? "Unavailable",
                sub: p.fallToStop.map { "Account would have to fall \($0) before everything is sold" },
                color: p.aboveStop == nil ? Theme.unavailable : Theme.ink)
            KPI(title: "Stop level", value: p.stop ?? "Unavailable", color: p.stop == nil ? Theme.unavailable : Theme.ink)
            KPI(title: "VaR 95%, 1 day", value: var95?.value ?? "Unavailable", sub: var95?.sub, color: var95 == nil ? Theme.unavailable : Theme.adverse)
            KPI(title: "VaR 99%, 1 day", value: var99?.value ?? "Unavailable", sub: var99?.sub, color: var99 == nil ? Theme.unavailable : Theme.adverse)
            KPI(title: "Margin used", value: margin?.value ?? "Unavailable", sub: margin?.sub, color: margin == nil ? Theme.unavailable : Theme.ink)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func signalPanel(_ s: BTCSignals) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.coin).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(s.now ?? "Unavailable") now").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                level("Sell signal", s.sell, Theme.adverse, big: true)
                level("Buy signal", s.buy, Theme.supportive, big: true)
                level("Trend weakens", s.weakens, Theme.muted)
                level("Trend strengthens", s.strengthens, Theme.muted)
            }
        }
    }

    private func level(_ label: String, _ l: BTCLevel?, _ color: Color, big: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: big ? 22 : 19, weight: .semibold)).foregroundStyle(big ? color : Theme.muted)
                .frame(width: 210, alignment: .leading)
            Text(l?.price ?? "Unavailable").font(.system(size: big ? 30 : 22, weight: .bold))
                .foregroundStyle(l == nil ? Theme.unavailable : Theme.ink)
            if let d = l?.distance { Text(d).font(.system(size: big ? 24 : 20, weight: .semibold)).foregroundStyle(BTCStyle.signColor(d)) }
            if let n = l?.note { Text(n).font(.system(size: 19)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7) }
        }
    }

    private func comingUp(_ p: BTCPage) -> some View {
        HStack(alignment: .top, spacing: 18) {
            if p.comingUp.isEmpty { KPI(title: "Next signal", value: "Unavailable", color: Theme.unavailable) }
            ForEach(Array(p.comingUp.enumerated()), id: \.offset) { _, row in
                KPI(title: row.0, value: row.1, valueSize: 32)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func fact(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 20)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value ?? "Unavailable").font(.system(size: 22, weight: .semibold))
                .foregroundStyle(value == nil ? Theme.unavailable : Theme.ink)
        }
    }
}

enum BTCStyle {
    /// Green when the page says it is running / OK, red for halted / stopped / error wording, amber otherwise.
    static func statusColor(_ p: BTCPage?) -> Color {
        guard let p else { return Theme.unavailable }
        let words = (p.status ?? "").lowercased()
        let cls = (p.statusClass ?? "").split(separator: " ").map(String.init)
        if ["halt", "stop", "error", "fail", "not running", "down", "flatten"].contains(where: words.contains)
            || cls.contains(where: { ["bad", "err", "error", "halt", "halted", "down", "red"].contains($0) }) { return Theme.adverse }
        if cls.contains("ok") || words.contains("running") || words.hasPrefix("ok") || words.contains("all good") { return Theme.supportive }
        return Theme.mixed
    }

    /// "+$6,050" green, "−0.8%" red (the page uses the U+2212 minus sign).
    static func signColor(_ s: String?) -> Color {
        guard let s, let c = s.first else { return Theme.unavailable }
        return c == "+" ? Theme.supportive : (c == "−" || c == "-") ? Theme.adverse : Theme.ink
    }
}
