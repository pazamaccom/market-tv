import SwiftUI

/// Presentation of snapshot.downturn_panel. Selection, ranking and statistics come from the server;
/// the display gate below is the same as warningRate() in app.js.
struct DownturnView: View {
    @EnvironmentObject private var market: MarketStore
    @EnvironmentObject private var settings: AppSettings

    private var panel: J { market.snapshot["downturn_panel"] }
    private var broad: Bool { (panel["total"].int ?? 0) > 6 }
    private var cards: [J] { panel["cards"].array }

    var body: some View {
        Screen {
            ScreenHeader(title: "Downturn warning signals",
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
                notes
                highlights
                others
                Text("These are historical associations, not forecasts or current crash probabilities.")
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.onNavy)
                if let caveat = panel["selection_caveat"].string {
                    Text(caveat).font(.system(size: 20)).foregroundStyle(Theme.onNavyMuted)
                }
            }
        }
    }

    private var coverage: String {
        guard panel.exists else { return "Statistics cutoff —" }
        return "\(Fmt.count(panel["triggered"])) active warnings · \(Fmt.count(panel["evaluable"])) assessable signals · \(Fmt.count(panel["unavailable"])) unavailable · cutoff \(panel["cutoff"].string ?? "—")"
    }

    @ViewBuilder private var notes: some View {
        if !broad {
            Text("This frozen record covers V1–V6 divergences only; the broader indicator set was not recorded.")
                .font(.system(size: 20)).foregroundStyle(Theme.onNavyMuted)
        }
        if (panel["unavailable"].int ?? 0) > 0 {
            Text("Current signal coverage incomplete; omitted signals are not assumed OFF.")
                .font(.system(size: 20)).foregroundStyle(Theme.onNavyMuted)
        }
    }

    private var shown: [J] { broad ? Array(cards.prefix(2)) : cards }

    private var pairRows: [(signals: [String], stat: J)] {
        let ranked = panel["ranked_pairs"].array
        if !ranked.isEmpty { return ranked.map { ($0["signals"].array.compactMap { $0.string }, $0["statistics"]) } }
        guard broad else { return [] }
        return panel["current_pair_evidence"].array.map { ($0["signals"].array.compactMap { $0.string }, $0["periods"]["test"]) }
    }

    @ViewBuilder private var highlights: some View {
        if (panel["triggered"].int ?? 0) == 0 {
            Panel { Text("No active warnings among assessable signals. This does not mean no risk.").font(.system(size: 26)).foregroundStyle(Theme.ink) }
        } else {
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, card in
                    let words = market.warning(card)
                    WarningCard(badge: "ACTIVE WARNING", title: words.name, subtitle: nil, stat: card["statistics"], joint: false, meaning: words.meaning)
                }
                if (panel["triggered"].int ?? 0) >= 2 { joint }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var joint: some View {
        if let pair = pairRows.first {
            let names = pair.signals.map { id -> String in
                if let c = cards.first(where: { $0["id"].string == id }) { return market.warning(c).name }
                return market.snapshot["signals"].array.first(where: { $0["id"].string == id })?["name"].string ?? id
            }.joined(separator: " + ")
            let st = pair.stat
            let valid = WarningCard.valid(st)
            let meaning = !valid ? "There are too few resolved joint episodes for a reliable historical comparison."
                : (st["uplift_pp"].finite ?? 0) > 0 ? "This combination has historically been associated with higher downside risk than normal, although the sample is relatively small."
                : "This combination has not historically shown higher downside risk than its typical background rate."
            WarningCard(badge: broad ? "BOTH STRONGEST WARNINGS ACTIVE TOGETHER" : "BOTH WARNINGS ACTIVE TOGETHER",
                        title: names, subtitle: nil, stat: st, joint: true, meaning: meaning)
        } else {
            let selected = !panel["selected_pair"].array.isEmpty
            Panel {
                Text(selected ? "Joint statistics unavailable for the selected two signals."
                     : broad ? "Fewer than two active signals have sufficient comparable episode evidence."
                     : "No current signal pair has sufficient resolved historical episodes for a prominent joint statistic.")
                .font(.system(size: 24)).foregroundStyle(Theme.ink)
            }
        }
    }

    @ViewBuilder private var others: some View {
        let rest = broad ? Array(cards.dropFirst(2)) : []
        if !rest.isEmpty {
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(rest.count) other active signals").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.ink)
                    ForEach(Array(rest.enumerated()), id: \.offset) { _, card in
                        let st = card["statistics"]
                        HStack(alignment: .firstTextBaseline) {
                            Text(market.warning(card).name).font(.system(size: 23, weight: .semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text(WarningCard.valid(st)
                                 ? "\(Fmt.fixed((st["follow_through"].finite ?? 0) * 100, 0, "%")) vs \(Fmt.fixed(st["baseline"].finite.map { $0 * 100 }, 0, "%")) background · \(Fmt.count(st["successes"]))/\(Fmt.count(st["resolved"])) resolved"
                                 : st.exists ? "Insufficient episode history (\(Fmt.count(st["successes"]))/\(Fmt.count(st["resolved"])) resolved)" : "Episode evidence unavailable")
                                .font(.system(size: 21)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }
}

struct WarningCard: View {
    let badge: String
    let title: String
    let subtitle: String?
    let stat: J
    let joint: Bool
    let meaning: String

    static func available(_ s: J) -> Bool { s.exists && s["available"].bool != false }

    static func valid(_ s: J) -> Bool {
        s["prominent_eligible"].bool == true && (s["resolved"].int ?? 0) >= 10 && s["follow_through"].finite != nil && s["baseline"].finite != nil
    }

    var body: some View {
        let ft = stat["follow_through"].finite
        let base = stat["baseline"].finite
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text(badge).font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.adverse)
                Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if !Self.available(stat) {
                    Text("Historical episode evidence unavailable in this record.").font(.system(size: 22)).foregroundStyle(Theme.muted)
                } else {
                    if Self.valid(stat), let ft {
                        Text(Fmt.fixed(ft * 100, 0, "%")).font(.system(size: 80, weight: .heavy)).foregroundStyle(Theme.adverse)
                        Text(joint ? "\(Fmt.count(stat["successes"])) of \(Fmt.count(stat["resolved"])) resolved joint episodes were followed by a ≥10% downturn within 12 months"
                             : "of comparable historical episodes were followed by a ≥10% market downturn within 12 months")
                            .font(.system(size: 21)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Insufficient episode history (\(Fmt.count(stat["successes"]))/\(Fmt.count(stat["resolved"])) resolved)")
                            .font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.ink)
                    }
                    Text("Typical background rate: \(Fmt.fixed(base.map { $0 * 100 }, 0, "%"))").font(.system(size: 21)).foregroundStyle(Theme.ink)
                    Text("Historical uplift: \(Fmt.signed(stat["uplift_pp"].finite, 1)) percentage points").font(.system(size: 21)).foregroundStyle(Theme.ink)
                    if Self.valid(stat), let ft, let base {
                        bar("After warning", ft, Theme.adverse)
                        bar("Background", base, Theme.unavailable)
                    }
                }
                Text("What it means: \(meaning)").font(.system(size: 20)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if Self.available(stat) {
                    Text("\(Fmt.count(stat["resolved"])) resolved \(joint ? "joint " : "")historical episodes · \(Fmt.count(stat["pending"])) current/pending episodes")
                        .font(.system(size: 18)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
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
