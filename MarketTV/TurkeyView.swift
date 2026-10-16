import SwiftUI
import Charts

/// Turkey Fund Tracker (port 8081): read-only GETs of the same /api endpoints the web page uses.
struct TurkeySection: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var feed = FeedStore()

    static let paths = ["/api/summary", "/api/holdings", "/api/history", "/api/live-fx",
                        "/api/carry-risk-score", "/api/carry-risk-history", "/api/carry-summary", "/api/data-freshness"]

    var body: some View {
        TabView {
            TurkeyPortfolio(feed: feed).tabItem { Text("Portfolio") }
            TurkeyCarry(feed: feed).tabItem { Text("Carry Risk") }
        }
        .background(Theme.background.ignoresSafeArea())
        .task(id: settings.refreshToken) {
            await poll(every: 300) { await feed.load(base: settings.dashboardBase(port: 8081), json: Self.paths) }
        }
    }
}

private func usd(_ v: Double?, signed: Bool = false) -> String { Fmt.compact(v, prefix: "$", signed: signed) }
private func tl(_ v: Double?, signed: Bool = false) -> String { Fmt.compact(v, prefix: "₺", signed: signed) }
private func pctPts(_ v: Double?, _ d: Int = 2) -> String { Fmt.signed(v, d, "%") }

struct TurkeyPortfolio: View {
    @ObservedObject var feed: FeedStore

    var body: some View {
        let s = feed["/api/summary"]["data"]
        let fx = feed["/api/live-fx"]["data"]
        let h = feed["/api/history"]["data"]
        return Screen {
            ScreenHeader(title: "Turkey Fund Tracker",
                         subtitle: "Portfolio · prices as of \(Fmt.dayLabel(s["as_of"].string)) · holding since \(Fmt.dayLabel(s["holding_start"].string))",
                         updated: feed.updated)
            if let e = feed.error { Banner(text: e) }
            if s.exists {
                HStack(alignment: .top, spacing: 18) {
                    KPI(title: "Total value (USD)", value: usd(s["total_value_usd"].finite), sub: tl(s["total_value_tl"].finite))
                    KPI(title: "Today (USD)", value: usd(s["daily_pnl_usd"].finite, signed: true),
                        sub: "\(pctPts(s["daily_pct_usd"].finite)) · TL \(pctPts(s["daily_pct_tl"].finite))",
                        color: Theme.change(s["daily_pnl_usd"].finite))
                    KPI(title: "Year to date (USD)", value: pctPts(s["ytd_usd"].finite, 1),
                        sub: "TL \(pctPts(s["ytd_tl"].finite, 1)) · MTD \(pctPts(s["mtd_usd"].finite))",
                        color: Theme.change(s["ytd_usd"].finite))
                    KPI(title: "Since start (USD)", value: usd(s["pnl_si_usd"].finite, signed: true),
                        sub: tl(s["pnl_si_tl"].finite, signed: true), color: Theme.change(s["pnl_si_usd"].finite))
                    KPI(title: "USD/TRY", value: Fmt.fixed(fx["rate"].finite ?? s["fx_rate"].finite, 4),
                        sub: fx.exists ? "Live, \(pctPts(fx["move_pct"].finite)) vs \(Fmt.dayLabel(fx["anchor_date"].string)) close · \(usd(fx["impact_usd"].finite, signed: true)) impact"
                                       : "Close \(Fmt.dayLabel(s["as_of"].string))")
                }
                .fixedSize(horizontal: false, vertical: true)

                periodRow(s)

                HStack(alignment: .top, spacing: 18) {
                    LineChartPanel(title: "Portfolio value (USD)",
                                   points: seriesPoints(dates: h["dates"], values: h["totals_usd"]),
                                   color: Theme.accent, valueText: { usd($0) })
                    LineChartPanel(title: "Portfolio value (TL)",
                                   points: seriesPoints(dates: h["dates"], values: h["totals_tl"]),
                                   color: Theme.lines[1], valueText: { tl($0) })
                    LineChartPanel(title: "USD/TRY",
                                   points: seriesPoints(dates: h["dates"], values: h["fx_series"]),
                                   color: Theme.adverse, valueText: { Fmt.fixed($0, 4) })
                }
                .fixedSize(horizontal: false, vertical: true)

                holdings
            } else if !feed.attempted {
                LoadingLine(text: "Loading Turkey Fund Tracker…")
            }
        }
    }

    private func periodRow(_ s: J) -> some View {
        let periods: [(String, String)] = [("1 day", "1d"), ("1 week", "1w"), ("2 weeks", "2w"), ("1 month", "1m"), ("3 months", "3m")]
        return HStack(alignment: .top, spacing: 18) {
            ForEach(periods, id: \.1) { label, key in
                KPI(title: "P&L \(label)", value: usd(s["pnl_\(key)_usd"].finite, signed: true),
                    sub: tl(s["pnl_\(key)_tl"].finite, signed: true),
                    color: Theme.change(s["pnl_\(key)_usd"].finite), valueSize: 34)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var holdings: some View {
        let funds = feed["/api/holdings"]["data"]["funds"].array
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Holdings", note: "Returns in USD")
            HStack(spacing: 12) {
                HeaderCell(text: "Fund")
                HeaderCell(text: "Weight", width: 130, alignment: .trailing)
                HeaderCell(text: "Value", width: 170, alignment: .trailing)
                HeaderCell(text: "1 day", width: 130, alignment: .trailing)
                HeaderCell(text: "1 month", width: 130, alignment: .trailing)
                HeaderCell(text: "3 months", width: 130, alignment: .trailing)
                HeaderCell(text: "1 year", width: 130, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            ForEach(Array(funds.enumerated()), id: \.offset) { _, f in
                FocusRow {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f["name"].string ?? f["code"].string ?? "Fund").font(.system(size: 23, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text("\(f["code"].string ?? "") · \(f["bank"].string ?? "")").font(.system(size: 18)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Cell(text: Fmt.fixed(f["weight"].finite, 1, "%"), width: 130, weight: .semibold)
                        Cell(text: usd(f["value_usd"].finite), width: 170)
                        ForEach(["1d", "1m", "3m", "1y"], id: \.self) { k in
                            Cell(text: pctPts(f["ret_\(k)_usd"].finite), width: 130, color: Theme.change(f["ret_\(k)_usd"].finite))
                        }
                    }
                }
            }
        }
    }
}

struct TurkeyCarry: View {
    @ObservedObject var feed: FeedStore

    private func recColor(_ r: String?) -> Color {
        switch r?.lowercased() {
        case "full": return Theme.supportive
        case "reduce": return Theme.mixed
        case nil: return Theme.unavailable
        default: return Theme.adverse
        }
    }

    var body: some View {
        let c = feed["/api/carry-risk-score"]["data"]
        return Screen {
            ScreenHeader(title: "Carry Risk", subtitle: "Turkey Fund Tracker · score as of \(Fmt.dayLabel(c["as_of"].string))",
                         badge: c["recommendation"].string?.uppercased(), badgeColor: recColor(c["recommendation"].string),
                         updated: feed.updated)
            if let e = feed.error { Banner(text: e) }
            if c.exists {
                headline(c)
                buckets(c)
                HStack(alignment: .top, spacing: 18) {
                    LineChartPanel(title: "Composite carry-risk score",
                                   points: compositeHistory, color: Theme.adverse, valueText: { Fmt.fixed($0, 1) }, height: 260)
                    carryTable
                }
                .fixedSize(horizontal: false, vertical: true)
                tripWires(c)
                freshness
            } else if !feed.attempted {
                LoadingLine(text: "Loading carry risk…")
            }
        }
    }

    private func headline(_ c: J) -> some View {
        Panel {
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Composite score").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text(Fmt.fixed(c["composite_score"].finite, 1)).font(.system(size: 84, weight: .heavy)).foregroundStyle(Theme.ink)
                    Text("\(Fmt.signed(c["composite_delta_1w"].finite, 1)) vs \(Fmt.dayLabel(c["composite_delta_1w_vs"].string))")
                        .font(.system(size: 21, weight: .semibold)).foregroundStyle(Theme.muted)
                    Pill(text: (c["recommendation"].string ?? "—").uppercased(), color: recColor(c["recommendation"].string), size: 24)
                        .padding(.top, 6)
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 14) {
                    Text(c["recommendation_text"].string ?? "")
                        .font(.system(size: 24)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 34) {
                        fact("Position", Fmt.fixed(c["position_pct"].finite, 0, "%"))
                        fact("Carry spread (20d)", Fmt.fixed(c["carry_spread_20d"].finite, 2, "%"))
                        fact("Daily carry", usd(c["daily_usd_yield"].finite))
                        fact("Trip wires fired", Fmt.count(c["fired_trip_wires"]))
                        fact("EM contagion", "\(c["contagion"]["state"].string ?? "—") ×\(Fmt.fixed(c["contagion"]["multiplier"].finite, 1))")
                        fact("Lira overvaluation", "\(c["overvaluation"]["state"].string ?? "—") · gap \(Fmt.fixed(c["overvaluation"]["gap_12m"].finite, 1, "%"))")
                    }
                    let z = c["zone_boundaries"]
                    Text("Zone boundaries: full \(Fmt.fixed(z["full"].finite, 0)) · reduce \(Fmt.fixed(z["reduce"].finite, 0)) · minimum \(Fmt.fixed(z["minimum"].finite, 0))")
                        .font(.system(size: 19)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 17)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func buckets(_ c: J) -> some View {
        let names: [(String, String)] = [("fx", "FX"), ("reserve", "Reserves"), ("policy", "Policy"), ("flow", "Flows")]
        return HStack(alignment: .top, spacing: 18) {
            ForEach(names, id: \.0) { key, label in
                let b = c["buckets"][key]
                let delta = c["bucket_deltas"][key].finite
                KPI(title: "\(label) · weight \(Fmt.fixed(b["weight"].finite.map { $0 * 100 }, 0, "%"))",
                    value: Fmt.fixed(b["score"].finite, 1),
                    sub: "\(Fmt.signed(delta, 1)) vs \(Fmt.dayLabel(c["bucket_deltas_vs"].string))",
                    color: Theme.ink)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var compositeHistory: [SeriesPoint] {
        feed["/api/carry-risk-history"]["data"].array.enumerated().compactMap { i, r in
            guard let s = r["date"].string, let d = Fmt.day(s), let v = r["composite"].finite else { return nil }
            return SeriesPoint(id: i, date: d, value: v)
        }
    }

    private var carryTable: some View {
        let s = feed["/api/carry-summary"]["data"]
        let horizons = ["1d", "5d", "10d", "20d", "60d"]
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Carry summary (annualised %)").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.ink)
                HStack {
                    Cell(text: "", alignment: .leading)
                    ForEach(horizons, id: \.self) { Cell(text: $0, width: 110, color: Theme.muted, weight: .semibold, size: 19) }
                }
                ForEach([("TRY yield", "try_yield"), ("FX depreciation", "fx_dep"), ("Carry spread", "spread")], id: \.1) { label, key in
                    HStack {
                        Cell(text: label, alignment: .leading, weight: .semibold, size: 21)
                        ForEach(horizons, id: \.self) { h in Cell(text: Fmt.fixed(s["\(key)_\(h)"].finite, 1), width: 110, size: 21) }
                    }
                }
                HStack {
                    Cell(text: "P&L (USD)", alignment: .leading, weight: .semibold, size: 21)
                    ForEach(horizons, id: \.self) { h in
                        Cell(text: usd(s["pnl_\(h)"].finite, signed: true), width: 110, color: Theme.change(s["pnl_\(h)"].finite), size: 21)
                    }
                }
                let g = s["inflation_gap"]
                Text("12-month CPI \(Fmt.fixed(g["cpi_cum_12m"].finite, 1, "%")) vs lira depreciation \(Fmt.fixed(g["fx_dep_cum_12m"].finite, 1, "%")) · gap \(Fmt.fixed(g["gap_12m"].finite, 1, " pts")) (\(Fmt.dayLabel(g["date"].string)))")
                    .font(.system(size: 18)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tripWires(_ c: J) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Trip wires", note: "\(Fmt.count(c["fired_trip_wires"])) fired")
            ForEach(Array(c["trip_wires"].array.enumerated()), id: \.offset) { _, w in
                let status = w["status"].string ?? "—"
                FocusRow {
                    HStack(spacing: 18) {
                        Pill(text: status.uppercased(), color: status == "inactive" ? Theme.unavailable : status == "watch" ? Theme.mixed : Theme.adverse)
                            .frame(width: 150, alignment: .leading)
                        Text(w["name"].string ?? w["id"].string ?? "").font(.system(size: 23, weight: .semibold)).foregroundStyle(Theme.ink)
                            .frame(width: 380, alignment: .leading)
                        Text(conditions(w["conditions"])).font(.system(size: 19)).foregroundStyle(Theme.muted).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func conditions(_ j: J) -> String {
        j.object.keys.sorted().map { k in
            let v = j[k]
            let text = v.finite.map { Fmt.fixed($0, abs($0) < 10 ? 2 : 1) } ?? v.string ?? v.bool.map { $0 ? "yes" : "no" } ?? "—"
            return "\(k.replacingOccurrences(of: "_", with: " ")) \(text)"
        }.joined(separator: " · ")
    }

    private var freshness: some View {
        let rows = feed["/api/data-freshness"]["data"].array
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Data freshness")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    let st = r["status"].string ?? "—"
                    FocusRow {
                        HStack(spacing: 14) {
                            Pill(text: st.uppercased(), color: st == "fresh" ? Theme.supportive : st == "amber" ? Theme.mixed : Theme.adverse)
                            Text(r["name"].string ?? "").font(.system(size: 21, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer()
                            Text("\(Fmt.fixed(r["hours_since_update"].finite, 0)) h ago").font(.system(size: 19)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }
}
