import SwiftUI

/// US Drawdown and Downturn (port 8080): GET /api/payload (one large read-only document).
struct DrawdownSection: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var feed = FeedStore()

    var body: some View {
        DrawdownScreen(feed: feed)
            .task(id: settings.refreshToken) {
                await poll(every: 900) { await feed.load(base: settings.dashboardBase(port: 8080), json: ["/api/payload"]) }
            }
    }
}

struct DrawdownScreen: View {
    @ObservedObject var feed: FeedStore

    var body: some View {
        let p = feed["/api/payload"]
        return Screen {
            ScreenHeader(title: "US Drawdown and Downturn",
                         subtitle: "As of \(Fmt.dayLabel(p["as_of"].string)) · rules v\(p["rules_version"].int.map(String.init) ?? "—") · \(p["run_id"].string ?? "")",
                         updated: feed.updated)
            if let e = feed.error { Banner(text: e) }
            if p.exists {
                if let b = p["banner"].string { Banner(text: b, color: Theme.mixed) }
                market(p)
                HStack(alignment: .top, spacing: 18) {
                    composite(p["composites"]["daily"], title: "Daily composite")
                    composite(p["composites"]["monthly"], title: "Monthly composite")
                }
                .fixedSize(horizontal: false, vertical: true)
                signals(p)
                HStack(alignment: .top, spacing: 18) {
                    LineChartPanel(title: "S&P 500, weekly (log scale)",
                                   points: seriesPoints(dates: p["history"]["dates"], values: p["history"]["closes"]),
                                   color: Theme.accent, valueText: { Fmt.grouped($0, 2) }, yearAxis: true, logScale: true, height: 280)
                    LineChartPanel(title: "S&P 500, last 5 years",
                                   points: seriesPoints(dates: p["history"]["dates"], values: p["history"]["closes"], last: 261),
                                   color: Theme.lines[1], valueText: { Fmt.grouped($0, 2) }, yearAxis: true, height: 280)
                }
                .fixedSize(horizontal: false, vertical: true)
                panels(p)
                health(p)
            } else if !feed.attempted {
                LoadingLine(text: "Loading Drawdown (large file)…")
            }
        }
    }

    private func market(_ p: J) -> some View {
        let m = p["market"]
        let ip = p["history"]["in_progress"]
        let above = m["above_200d"].bool
        return HStack(alignment: .top, spacing: 18) {
            KPI(title: "S&P 500 close", value: Fmt.grouped(m["close"].finite, 2), sub: Fmt.dayLabel(m["date"].string))
            KPI(title: "From all-time high", value: Fmt.signed(m["ddath"].finite.map { $0 * 100 }, 1, "%"),
                sub: "1-year high \(Fmt.signed(m["dd1y"].finite.map { $0 * 100 }, 1, "%"))", color: Theme.change(m["ddath"].finite))
            KPI(title: "200-day average", value: Fmt.grouped(m["sma200"].finite, 0),
                sub: above == nil ? nil : (above == true ? "Price above" : "Price below"),
                color: above == false ? Theme.adverse : Theme.ink)
            KPI(title: "Current move", value: (ip["type"].string ?? "—").capitalized,
                sub: ip.exists ? "Since \(Fmt.dayLabel(ip["start"].string)) from \(Fmt.grouped(ip["start_level"].finite, 0)); extreme \(Fmt.grouped(ip["extreme_so_far"].finite, 0)) on \(Fmt.dayLabel(ip["extreme_date"].string)) (\(ip["note"].string ?? ""))" : nil,
                valueSize: 36)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func composite(_ c: J, title: String) -> some View {
        let on = c["state"].bool == true
        return Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Pill(text: on ? "ALARM ON" : "ALARM OFF", color: on ? Theme.adverse : Theme.supportive, size: 21)
                    Pill(text: c["label"].string ?? "—", color: Theme.unavailable, size: 18)
                }
                Text(c["sentence"].string ?? "").font(.system(size: 21)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Inputs: \(c["inputs"].array.compactMap { $0.string }.joined(separator: ", ")) · needs \(c["k"].int.map(String.init) ?? "—") on")
                    .font(.system(size: 17)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private func signals(_ p: J) -> some View {
        let daily = p["signals"]["daily"]["rows"].array
        let monthly = p["signals"]["monthly"]["rows"].array
        var names: [String: String] = [:]
        for r in daily { if let c = r["column"].string, let n = r["plain_name"].string { names[c] = n } }
        let onDaily = daily.filter { $0["alarm"].bool == true }
        let onMonthly = monthly.filter { $0["alarm"].bool == true }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Signals on today",
                         note: "Daily \(onDaily.count) of \(daily.count) (\(Fmt.dayLabel(p["signals"]["daily"]["evaluation_day"].string))) · monthly \(onMonthly.count) of \(monthly.count) (\(Fmt.dayLabel(p["signals"]["monthly"]["evaluation_day"].string)))")
            if onDaily.isEmpty && onMonthly.isEmpty {
                Note(text: "No individual signal is on.")
            }
            ForEach(Array(onDaily.enumerated()), id: \.offset) { _, r in signalRow(r, names: names, frequency: "Daily") }
            ForEach(Array(onMonthly.enumerated()), id: \.offset) { _, r in signalRow(r, names: names, frequency: "Monthly") }
        }
    }

    private func signalRow(_ r: J, names: [String: String], frequency: String) -> some View {
        let column = r["column"].string ?? ""
        return FocusRow {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Pill(text: frequency, color: frequency == "Daily" ? Theme.accent : Theme.lines[1])
                    Text(r["family"].string ?? "").font(.system(size: 17)).foregroundStyle(Theme.muted)
                }
                .frame(width: 130, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(r["plain_name"].string ?? names[column] ?? column).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(column).font(.system(size: 16, design: .monospaced)).foregroundStyle(Theme.muted)
                    if let beside = r["beside"].string {
                        Text(beside).font(.system(size: 18)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Value \(Fmt.fixed(r["value"].finite, 2))").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("Percentile \(Fmt.fixed(r["percentile"].finite, 1)) · threshold \(Fmt.fixed(r["threshold"].finite, 0))")
                        .font(.system(size: 17)).foregroundStyle(Theme.muted)
                    Text("On for \(r["days_on"].int.map(String.init) ?? "—") days · last \(Fmt.dayLabel(r["last_value_period"].string))")
                        .font(.system(size: 17)).foregroundStyle(Theme.muted)
                }
                .frame(width: 380, alignment: .trailing)
            }
        }
    }

    private func panels(_ p: J) -> some View {
        HStack(alignment: .top, spacing: 18) {
            KPI(title: "Triage (bear-market entries)",
                value: p["triage_panel"]["active_entry"].exists ? "Active" : "None active",
                sub: "\(p["triage_panel"]["note"].string ?? "") Bear share \(Fmt.pct(p["triage_panel"]["bear_share"].finite)) of \(p["triage_panel"]["resolved_entries"].int.map(String.init) ?? "—") entries.",
                valueSize: 32)
            KPI(title: "Rally zone",
                value: p["rally_panel"]["in_rally_zone"].bool == true ? "In rally zone" : "Not in rally zone",
                sub: "\(p["rally_panel"]["note"].string ?? "") Up share \(Fmt.pct(p["rally_panel"]["up_share"].finite)).",
                valueSize: 32)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func health(_ p: J) -> some View {
        let series = p["health"]["series"].array
        let stale = series.filter { $0["stale"].bool == true }
        let staleNames = stale.compactMap { $0["series"].string }.joined(separator: ", ")
        return Note(text: "Data health: \(series.count - stale.count) of \(series.count) input series current\(stale.isEmpty ? "." : "; stale: \(staleNames).") Code \(p["code_commit"].string ?? "—").")
    }
}
