import SwiftUI
import Charts

struct HealthView: View {
    @EnvironmentObject private var market: MarketStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Screen {
            ScreenHeader(title: "US Market Health", subtitle: subtitle,
                         badge: settings.demoMode ? "DEMO — SYNTHETIC" : "LIVE",
                         badgeColor: settings.demoMode ? Theme.mixed : Theme.accent,
                         updated: market.updated)
            if let e = market.error { Banner(text: e) }
            if market.snapshot.exists {
                interpretation
                cards
                charts
                Text("Charts show the last 120 recorded sessions. Daily assessment only; an intraday tick is not a new daily assessment.")
                    .font(.system(size: 20)).foregroundStyle(Theme.onNavyMuted)
            } else if market.error == nil {
                ProgressView("Loading Market Health…").font(.system(size: 28)).foregroundStyle(Theme.onNavy)
            }
        }
    }

    private var subtitle: String {
        let s = market.snapshot
        guard s.exists else { return settings.marketBase }
        var parts = ["Assessment \(s["cutoff"].string ?? "—")"]
        if let status = s["status"].string { parts.append(status) }
        if let reading = s["daily_view"]["assessment"].string { parts.append(reading) }
        return parts.joined(separator: " · ")
    }

    // MARK: Overall reading (dashboard's own interpretRecord output)

    private var interpretation: some View {
        let m = market.model
        return Panel {
            if m.exists {
                HStack(alignment: .top, spacing: 28) {
                    Text(m["healthText"].string ?? "")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.tone(m["healthTone"].string)))
                        .fixedSize()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(m["headline"].string ?? "").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.ink)
                        Text([m["summary"].string, m["context"].string].compactMap { $0 }.joined(separator: " "))
                            .font(.system(size: 23)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("Market interpretation unavailable: \(market.interpretationError ?? "not loaded"). Charts below still show recorded data; open the dashboard in Safari for the full reading.")
                    .font(.system(size: 24)).foregroundStyle(Theme.adverse)
            }
        }
    }

    // MARK: Five overview cards

    private var cards: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(Array(market.model["areas"].array.enumerated()), id: \.offset) { _, area in
                OverviewCard(area: area)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Charts

    private var charts: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 3)
        return LazyVGrid(columns: columns, spacing: 18) {
            CurveChart(market: market)
            HistoryChart(title: "10Y real yield (TIPS)", unit: "%", decimals: 2, color: Theme.lines[0], points: market.history("real10"))
            HistoryChart(title: "10Y nominal Treasury yield", unit: "%", decimals: 2, color: Theme.lines[1], points: market.history("nominal10Y"))
            HistoryChart(title: "High-yield credit spread", unit: " bp", decimals: 0, color: Theme.adverse, points: market.history("hy"))
            HistoryChart(title: "Breadth: S&P 500 above 200-day average", unit: "%", decimals: 0, color: Theme.supportive, points: market.history("breadth"))
            HistoryChart(title: "Leadership: equal weight ÷ cap weight", unit: "", decimals: 3, color: Theme.lines[3], points: market.history("ratio"))
        }
    }
}

private struct OverviewCard: View {
    let area: J

    private var key: String { area["key"].string ?? "" }
    private var tone: String? { area["tone"].string }
    private var usable: Bool { area["usable"].bool == true }

    /// Same level wording as overviewCards() in app.js.
    private var level: String {
        switch key {
        case "ratio":
            return usable ? (area["directionText"].string ?? "").replacingOccurrences(of: " over 20 sessions", with: "") : "Unavailable"
        case "dollar":
            if let s = area["state"].string, s != "UNKNOWN" { return s.replacingOccurrences(of: "_", with: " ") }
            return "Unavailable"
        case "hy":
            return Fmt.fixed(area["level"].finite, 0, " bp")
        default:
            return Fmt.fixed(area["level"].finite, 2, "%")
        }
    }

    private var toneLabel: String {
        switch tone {
        case "adverse": return "↓ Worsening"
        case "supportive": return "↑ Improving"
        case "unavailable": return "— Cannot assess"
        default: return "→ Stable / Mixed"
        }
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Text(area["title"].string ?? key)
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.muted)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(toneLabel).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.tone(tone))
                Text(level)
                    .font(.system(size: key == "ratio" || key == "dollar" ? 28 : 46, weight: .bold))
                    .foregroundStyle(Theme.ink).lineLimit(2).minimumScaleFactor(0.6)
                Text("\(area["arrow"].string ?? "") \(area["directionText"].string ?? "")")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(area["magnitude"].string ?? "").font(.system(size: 20)).foregroundStyle(Theme.ink)
                Text("\(area["recentArrow"].string ?? "") \(area["recentLabel"].string ?? "") · \(area["recentPeriod"].string ?? "")  \(area["recentMagnitude"].string ?? "")")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.tone(area["recentTone"].string))
                    .fixedSize(horizontal: false, vertical: true)
                Text(area["implication"].string ?? "")
                    .font(.system(size: 18)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Observation \(area["date"].string ?? "not recorded")\(usable ? "" : " · unavailable for interpretation")")
                    .font(.system(size: 16)).foregroundStyle(Theme.muted)
            }
        }
    }
}

private struct DatedPoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double
}

struct HistoryChart: View {
    let title: String
    let unit: String
    let decimals: Int
    let color: Color
    let points: [(date: Date, value: Double)]

    var body: some View {
        let data = points.enumerated().map { DatedPoint(id: $0.offset, date: $0.element.date, value: $0.element.value) }
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
                if let last = data.last {
                    Text("\(Fmt.fixed(last.value, decimals, unit)) · \(Fmt.day(last.date))")
                        .font(.system(size: 20)).foregroundStyle(Theme.muted)
                    Chart(data) { p in
                        LineMark(x: .value("Date", p.date), y: .value(title, p.value))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                        }
                    }
                    .frame(height: 220)
                } else {
                    Text("No recorded history in this record.").font(.system(size: 20)).foregroundStyle(Theme.muted)
                        .frame(height: 250)
                }
            }
        }
    }
}

private struct CurvePoint: Identifiable {
    let id: String
    let years: Double
    let value: Double
    let series: String
}

/// Real (TIPS) curve at the latest session versus 20 sessions earlier.
private struct CurveChart: View {
    @ObservedObject var market: MarketStore
    private let tenors: [(key: String, years: Double)] = [("real5Y", 5), ("real7Y", 7), ("real10", 10), ("real20Y", 20), ("real30Y", 30)]

    var body: some View {
        let ten = market.history("real10", last: 21)
        let latest = ten.last.map { iso($0.date) }
        let earlier = ten.count >= 21 ? iso(ten[0].date) : nil
        var data: [CurvePoint] = []
        for (label, date) in [("Latest", latest), ("20 sessions earlier", earlier)] {
            guard let date else { continue }
            for t in tenors {
                if let v = market.snapshot["histories"][t.key][date].finite {
                    data.append(CurvePoint(id: "\(label)\(t.key)", years: t.years, value: v, series: label))
                }
            }
        }
        return Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text("Real yield curve (TIPS)").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("\(latest ?? "—") versus \(earlier ?? "—")").font(.system(size: 20)).foregroundStyle(Theme.muted)
                if data.isEmpty {
                    Text("Curve unavailable in this record.").font(.system(size: 20)).foregroundStyle(Theme.muted).frame(height: 220)
                } else {
                    Chart(data) { p in
                        LineMark(x: .value("Maturity (years)", p.years), y: .value("Real yield %", p.value), series: .value("Date", p.series))
                            .foregroundStyle(by: .value("Date", p.series))
                            .lineStyle(StrokeStyle(lineWidth: 3))
                            .symbol(by: .value("Date", p.series))
                    }
                    .chartForegroundStyleScale(["Latest": Theme.accent, "20 sessions earlier": Theme.unavailable])
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis { AxisMarks(values: [5, 7, 10, 20, 30]) { v in
                        AxisGridLine()
                        AxisValueLabel { if let y = v.as(Double.self) { Text("\(Int(y))Y") } }
                    } }
                    .chartLegend(position: .bottom)
                    .frame(height: 220)
                }
            }
        }
    }

    private func iso(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
