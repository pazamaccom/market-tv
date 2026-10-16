import SwiftUI

/// Presentation of snapshot.downturn_panel, following the dashboard's "Downturn warnings" section
/// (downturnSection() in cards.js, warning-display-3 in app.js). Selection, ranking, statistics and the
/// chips/readings in snapshot.card_signals.downturn come from the server; the TV only lays them out.
struct DownturnView: View {
    @EnvironmentObject private var market: MarketStore
    @EnvironmentObject private var settings: AppSettings

    /// Same as DOWNTURN_SHOWN in cards.js.
    private static let shownCount = 4

    private var panel: J { market.snapshot["downturn_panel"] }
    private var stored: J { market.snapshot["card_signals"]["downturn"] }
    private var broad: Bool { (panel["total"].int ?? 0) > 6 }
    private var signals: [J] { market.snapshot["signals"].array }
    /// Active cards without negative controls, which the dashboard never counts as warnings.
    private var active: [J] { panel["cards"].array.filter { !Downturn.isNegativeControl($0) } }
    /// Only a ranked pair with a reliable track record gets a combined card (cards.js `pair`).
    private var pair: J? { panel["ranked_pairs"].array.first { Downturn.hasEdge($0["statistics"]) } }

    var body: some View {
        Screen {
            ScreenHeader(title: "Downturn warnings",
                         subtitle: coverage,
                         badge: settings.demoMode ? "DEMO — SYNTHETIC" : "LIVE",
                         badgeColor: settings.demoMode ? Theme.mixed : Theme.accent,
                         updated: market.updated)
            if let e = market.error { Banner(text: e) }
            if !market.snapshot.exists {
                if market.error == nil { ProgressView("Loading…").foregroundStyle(Theme.onNavy) }
            } else if !panel.exists {
                Banner(text: "This record has no episode downturn panel. Open the dashboard in Safari for the legacy signal table.", color: Theme.mixed)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    if let pair { combined(pair) }
                    summary
                }
                .fixedSize(horizontal: false, vertical: true)
                indicators
                Text("Historical associations, not forecasts or crash probabilities. \(Downturn.reliable)")
                    .font(.system(size: 21)).foregroundStyle(Theme.onNavyMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if !broad {
                    Text("This older record covers six divergence signals only; the broader indicator set was not recorded.")
                        .font(.system(size: 20)).foregroundStyle(Theme.onNavyMuted)
                }
            }
        }
    }

    // MARK: Counts

    /// "3 of 24 on" uses indicator families (stored summary, else downturnCounts() in app.js).
    private var onTotal: (on: Int, total: Int) {
        let s = stored["summary"]
        if let on = s["on"].int, let total = s["total"].int { return (on, total) }
        guard broad else { return (panel["triggered"].int ?? 0, panel["evaluable"].int ?? 0) }
        let indicators = signals.filter { !Downturn.isNegativeControl($0) && !Downturn.isDivergence($0) }
        let family = { (s: J) in String((s["id"].string ?? "").split(separator: "|").first ?? "") }
        return (Set(indicators.filter { $0["active"].bool == true }.map(family)).count, Set(indicators.map(family)).count)
    }

    private var gapCount: Int { signals.filter { !$0["active"].exists }.count }

    private var coverage: String {
        guard panel.exists else { return "Statistics cutoff —" }
        let c = onTotal
        let gaps = gapCount > 0 ? "\(gapCount) can't be assessed until monthly data updates" : "All indicators assessable"
        return "\(c.on) of \(c.total) indicator families on · \(gaps) · cutoff \(panel["cutoff"].string ?? "—")"
    }

    // MARK: Cards

    private var summary: some View {
        let s = stored["summary"]
        let c = onTotal
        let reliable = active.filter { Downturn.hasEdge($0["statistics"]) }.count
        let fallback = c.on == 0 ? "No warning indicators are on, which does not mean no risk."
            : "\(c.on) warning indicator\(c.on == 1 ? " is" : "s are") on; "
              + (reliable > 0 ? "\(reliable) \(reliable == 1 ? "has" : "have") a reliable track record."
                 : pair != nil ? "none alone has a reliable track record, but two together do."
                 : c.on == 1 ? "it has no reliable track record." : "none has a reliable track record.")
        let more = active.count - Self.shownCount
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                Text("DOWNTURN WARNINGS").font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.muted)
                Chips(level: s["level"], trend: s["trend"].array)
                Text("\(c.on) of \(c.total) on").font(.system(size: 56, weight: .heavy)).foregroundStyle(Theme.ink)
                Text(s["reading"].string ?? fallback)
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if more > 0 {
                    Text("\(more) more active indicator\(more == 1 ? "" : "s") not shown here; open the dashboard for details.")
                        .font(.system(size: 20)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func combined(_ pair: J) -> some View {
        let st = pair["statistics"]
        let r = stored["combined"]
        let names = pair["signals"].array.compactMap { $0.string }.map(name).joined(separator: " + ")
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                Text("COMBINED WARNING").font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.adverse)
                Text(names).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if r.exists { Chips(level: r["level"], trend: r["trend"].array) }
                Text(r["value"].string ?? Downturn.upliftText(st) ?? "—").font(.system(size: 56, weight: .heavy)).foregroundStyle(Theme.adverse)
                Text(r["reading"].string ?? "When both were on, downturns followed \(Fmt.fixed((st["follow_through"].finite ?? 0) * 100, 0, "%")) of the time vs \(Fmt.fixed(st["baseline"].finite.map { $0 * 100 }, 0, "%")) usual (\(Fmt.count(st["resolved"])) past joint episodes).")
                    .font(.system(size: 22)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                DownturnBars(stat: st, joint: true)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var indicators: some View {
        let shown = Array(active.prefix(Self.shownCount))
        if !shown.isEmpty {
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, card in
                    IndicatorCard(card: card,
                                  stored: stored["indicators"].array.first { $0["id"].string == card["id"].string } ?? J(nil),
                                  words: market.warning(card))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func name(_ id: String) -> String {
        if let c = panel["cards"].array.first(where: { $0["id"].string == id }) { return market.warning(c).name }
        return signals.first(where: { $0["id"].string == id })?["name"].string ?? id
    }
}

/// The dashboard's warning rules (warning-display-3 in app.js, card-signals-5 in cards.js).
enum Downturn {
    static let reliable = "A reliable track record means downturns followed at least 10 points more often than usual, over at least 10 past episodes."

    static func isNegativeControl(_ j: J) -> Bool {
        (j["name"].string ?? "").range(of: "(negative control)", options: .caseInsensitive) != nil
    }

    static func isDivergence(_ j: J) -> Bool {
        (j["id"].string ?? "").range(of: #"^V\d$"#, options: .regularExpression) != nil
    }

    /// warningHasEdge(): eligible, ≥10 resolved episodes and an uplift of at least +10 pp.
    static func hasEdge(_ s: J) -> Bool {
        s["prominent_eligible"].bool == true && (s["resolved"].int ?? 0) >= 10 && (s["uplift_pp"].finite ?? -.infinity) >= 10 - 1e-9
    }

    static func available(_ s: J) -> Bool { s.exists && s["available"].bool != false }

    /// tooFew in cards.js.
    static func tooFew(_ s: J) -> Bool { available(s) && ((s["resolved"].int ?? 0) < 10 || s["uplift_pp"].finite == nil) }

    /// upliftText in cards.js: "+6 pts", "+0.8 pts".
    static func upliftText(_ s: J) -> String? {
        guard let u = s["uplift_pp"].finite else { return nil }
        if abs(u) < 0.05 { return "0.0 pts" }
        return Fmt.signed(u, abs(u) >= 1 ? 0 : 1, " pts")
    }

    /// edgeText in app.js, capitalised, used when the record has no stored reading.
    static func edgeText(_ s: J) -> String {
        guard available(s) else { return "Track record not available in this record." }
        let resolved = s["resolved"].int ?? 0
        guard resolved >= 10, let u = s["uplift_pp"].finite else {
            return "Too few past episodes to judge (\(resolved) with a known outcome; 10 needed)."
        }
        let n = abs(u)
        let points = (n >= 1 ? String(Int(n.rounded())) : String(format: "%.1f", n)) + ((n * 10).rounded() == 10 ? " point" : " points")
        return "Downturns followed \(points) \(u < 0 ? "less" : "more") often than usual (\(resolved) past episodes)."
    }
}

private struct IndicatorCard: View {
    let card: J
    let stored: J
    let words: (name: String, meaning: String)

    var body: some View {
        let st = card["statistics"]
        let edge = Downturn.hasEdge(st)
        let fewer = (st["uplift_pp"].finite ?? 0) < 0
        let tooFew = stored.exists ? stored["too_few"].bool == true : Downturn.tooFew(st)
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text(edge ? "ACTIVE WARNING" : fewer ? "ACTIVE · HISTORICALLY FEWER DOWNTURNS THAN USUAL" : "ACTIVE · NO RELIABLE TRACK RECORD")
                    .font(.system(size: 17, weight: .heavy)).foregroundStyle(edge ? Theme.adverse : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(words.name).font(.system(size: 27, weight: .bold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if stored.exists { Chips(level: stored["level"], trend: stored["trend"].array) }
                if tooFew {
                    Text("Too few to judge").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.unavailable)
                } else {
                    Text(stored["value"].string ?? Downturn.upliftText(st) ?? "—")
                        .font(.system(size: 46, weight: .heavy)).foregroundStyle(edge ? Theme.adverse : Theme.ink)
                }
                Text(stored["reading"].string ?? Downturn.edgeText(st))
                    .font(.system(size: 21)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if edge { DownturnBars(stat: st, joint: false) }
                Text(words.meaning).font(.system(size: 19)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                if edge, let pending = st["pending"].int {
                    Text("\(pending) recent episode\(pending == 1 ? " is" : "s are") still too new to judge")
                        .font(.system(size: 18)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Level and trend chips from snapshot.card_signals (text and kind are computed by the server).
private struct Chips: View {
    let level: J
    let trend: [J]

    var body: some View {
        let chips = ([level] + trend).filter { $0["text"].string != nil }
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, c in
                    Pill(text: [c["window"].string, c["arrow"].string, c["text"].string]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
                         color: Theme.chip(c["kind"].string), size: 18)
                }
            }
        }
    }
}

private struct DownturnBars: View {
    let stat: J
    let joint: Bool

    var body: some View {
        if let ft = stat["follow_through"].finite, let base = stat["baseline"].finite {
            VStack(spacing: 8) {
                bar(joint ? "Both on" : "After warning", ft, Theme.adverse)
                bar("Usual", base, Theme.unavailable)
            }
        }
    }

    private func bar(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 18)).foregroundStyle(Theme.muted).frame(width: 150, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.unavailable.opacity(0.2))
                    Capsule().fill(color).frame(width: g.size.width * max(0, min(1, value)))
                }
            }
            .frame(height: 16)
            Text(Fmt.fixed(value * 100, 0, "%")).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink).frame(width: 64, alignment: .trailing)
        }
    }
}
