import SwiftUI
import Charts

/// The Yield Curve dashboard (port 8084) is a Streamlit app with no data API, so the TV reads the
/// same official source it benchmarks against: the US Treasury daily par yield curve (Treasury.gov XML).
@MainActor
final class TreasuryStore: ObservableObject {
    struct Day {
        let date: Date
        let iso: String
        let rates: [String: Double]
    }

    static let tenors: [(key: String, label: String)] = [
        ("BC_1MONTH", "1M"), ("BC_1_5MONTH", "6W"), ("BC_2MONTH", "2M"), ("BC_3MONTH", "3M"), ("BC_4MONTH", "4M"),
        ("BC_6MONTH", "6M"), ("BC_1YEAR", "1Y"), ("BC_2YEAR", "2Y"), ("BC_3YEAR", "3Y"), ("BC_5YEAR", "5Y"),
        ("BC_7YEAR", "7Y"), ("BC_10YEAR", "10Y"), ("BC_20YEAR", "20Y"), ("BC_30YEAR", "30Y"),
    ]

    @Published private(set) var days: [Day] = []
    @Published private(set) var error: String?
    @Published private(set) var updated: Date?
    @Published private(set) var attempted = false

    func load() async {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        var collected: [String: Day] = [:]
        var firstError: String?
        for y in [year - 1, year] {
            do {
                let data = try await API.data("https://home.treasury.gov",
                                              "/resource-center/data-chart-center/interest-rates/pages/xml?data=daily_treasury_yield_curve&field_tdr_date_value=\(y)")
                for d in TreasuryXML.parse(data) { collected[d.iso] = d }
            } catch let e {
                if firstError == nil { firstError = API.describe(e) }
            }
        }
        if !collected.isEmpty {
            days = collected.values.sorted { $0.date < $1.date }
            updated = Date()
            error = firstError.map { "Part of the Treasury history could not be loaded: \($0)" }
        } else {
            error = firstError ?? "Treasury.gov returned no curve data."
        }
        attempted = true
    }

    var latest: Day? { days.last }

    /// The last session on or before `latest - days`.
    func day(back calendarDays: Int) -> Day? {
        guard let last = days.last else { return nil }
        let target = last.date.addingTimeInterval(-Double(calendarDays) * 86_400)
        return days.last { $0.date <= target }
    }

    var previous: Day? { days.count >= 2 ? days[days.count - 2] : nil }

    func series(_ f: (Day) -> Double?) -> [SeriesPoint] {
        days.enumerated().compactMap { i, d in f(d).map { SeriesPoint(id: i, date: d.date, value: $0) } }
    }
}

private final class TreasuryXML: NSObject, XMLParserDelegate {
    private var out: [TreasuryStore.Day] = []
    private var current: [String: Double]?
    private var date: String?
    private var buffer = ""

    static func parse(_ data: Data) -> [TreasuryStore.Day] {
        let delegate = TreasuryXML()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.out
    }

    private static func local(_ name: String) -> String { name.components(separatedBy: ":").last ?? name }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if Self.local(elementName) == "properties" {
            current = [:]
            date = nil
        }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = Self.local(elementName)
        if name == "properties" {
            if let iso = date, let rates = current, let d = Fmt.day(iso), !rates.isEmpty {
                out.append(TreasuryStore.Day(date: d, iso: iso, rates: rates))
            }
            current = nil
        } else if current != nil {
            let v = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "NEW_DATE" {
                date = String(v.prefix(10))
            } else if name.hasPrefix("BC_"), let x = Double(v) {
                current?[name] = x
            }
        }
        buffer = ""
    }
}

private struct CurveMark: Identifiable {
    let id: String
    let tenor: String
    let value: Double
    let series: String
}

struct YieldSection: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var store = TreasuryStore()

    var body: some View {
        YieldScreen(store: store)
            .task(id: settings.refreshToken) { await poll(every: 3600) { await store.load() } }
    }
}

struct YieldScreen: View {
    @ObservedObject var store: TreasuryStore

    private func bp(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return (a - b) * 100
    }

    var body: some View {
        let last = store.latest
        let prev = store.previous
        let month = store.day(back: 30)
        let year = store.day(back: 365)
        return Screen {
            ScreenHeader(title: "Yield Curve",
                         subtitle: "US Treasury par yield curve · Treasury.gov · \(last.map { Fmt.day($0.date) } ?? "—")",
                         updated: store.updated)
            if let e = store.error { Banner(text: e) }
            if let last {
                kpis(last, prev)
                HStack(alignment: .top, spacing: 18) {
                    curveChart([("Latest", last), ("1 month earlier", month), ("1 year earlier", year)])
                        .frame(maxWidth: .infinity)
                    table(last, prev, month, year).frame(width: 640)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 18) {
                    LineChartPanel(title: "10Y − 2Y spread (bp)",
                                   points: store.series { d in bp(d.rates["BC_10YEAR"], d.rates["BC_2YEAR"]) },
                                   color: Theme.accent, valueText: { Fmt.signed($0, 0, " bp") }, zeroLine: true)
                    LineChartPanel(title: "10Y − 3M spread (bp)",
                                   points: store.series { d in bp(d.rates["BC_10YEAR"], d.rates["BC_3MONTH"]) },
                                   color: Theme.lines[1], valueText: { Fmt.signed($0, 0, " bp") }, zeroLine: true)
                    LineChartPanel(title: "10-year yield (%)",
                                   points: store.series { $0.rates["BC_10YEAR"] },
                                   color: Theme.adverse, valueText: { Fmt.fixed($0, 2, "%") })
                }
                .fixedSize(horizontal: false, vertical: true)
                Note(text: "Source: US Treasury daily par yield curve rates, the benchmark the Yield Curve dashboard uses. Your municipal-bond holdings and peer checks are only in the web dashboard; it is a Streamlit app with no data feed the TV can read.")
            } else if !store.attempted {
                LoadingLine(text: "Loading Treasury curve…")
            }
        }
    }

    private func kpis(_ last: TreasuryStore.Day, _ prev: TreasuryStore.Day?) -> some View {
        let r = last.rates
        let s2 = bp(r["BC_10YEAR"], r["BC_2YEAR"])
        let s3 = bp(r["BC_10YEAR"], r["BC_3MONTH"])
        return HStack(alignment: .top, spacing: 18) {
            ForEach([("BC_3MONTH", "3-month"), ("BC_2YEAR", "2-year"), ("BC_10YEAR", "10-year"), ("BC_30YEAR", "30-year")], id: \.0) { key, label in
                KPI(title: "\(label) yield", value: Fmt.fixed(r[key], 2, "%"),
                    sub: "\(Fmt.signed(bp(r[key], prev?.rates[key]), 0, " bp")) on the day")
            }
            KPI(title: "10Y − 2Y", value: Fmt.signed(s2, 0, " bp"), sub: (s2 ?? 0) < 0 ? "Inverted" : "Positive slope",
                color: (s2 ?? 0) < 0 ? Theme.adverse : Theme.ink)
            KPI(title: "10Y − 3M", value: Fmt.signed(s3, 0, " bp"), sub: (s3 ?? 0) < 0 ? "Inverted" : "Positive slope",
                color: (s3 ?? 0) < 0 ? Theme.adverse : Theme.ink)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func curveChart(_ curves: [(String, TreasuryStore.Day?)]) -> some View {
        var marks: [CurveMark] = []
        var legend: [String] = []
        for (label, day) in curves {
            guard let day else { continue }
            let name = "\(label) (\(Fmt.day(day.date)))"
            legend.append(name)
            for t in TreasuryStore.tenors {
                if let v = day.rates[t.key] { marks.append(CurveMark(id: name + t.key, tenor: t.label, value: v, series: name)) }
            }
        }
        let colors: [Color] = [Theme.accent, Theme.mixed, Theme.unavailable]
        return Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Par yield curve (%)").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.ink)
                Chart(marks) { m in
                    LineMark(x: .value("Tenor", m.tenor), y: .value("Yield %", m.value), series: .value("Curve", m.series))
                        .foregroundStyle(by: .value("Curve", m.series))
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .symbol(by: .value("Curve", m.series))
                }
                .chartForegroundStyleScale(domain: legend, range: Array(colors.prefix(legend.count)))
                .chartXScale(domain: TreasuryStore.tenors.map { $0.label })
                .chartYScale(domain: .automatic(includesZero: false))
                .chartLegend(position: .bottom)
                .frame(height: 420)
            }
        }
    }

    private func table(_ last: TreasuryStore.Day, _ prev: TreasuryStore.Day?, _ month: TreasuryStore.Day?, _ year: TreasuryStore.Day?) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Cell(text: "Tenor", alignment: .leading, color: Theme.muted, weight: .semibold, size: 19)
                    Cell(text: "Yield", width: 110, color: Theme.muted, weight: .semibold, size: 19)
                    Cell(text: "1 day", width: 110, color: Theme.muted, weight: .semibold, size: 19)
                    Cell(text: "1 month", width: 120, color: Theme.muted, weight: .semibold, size: 19)
                    Cell(text: "1 year", width: 120, color: Theme.muted, weight: .semibold, size: 19)
                }
                ForEach(TreasuryStore.tenors, id: \.key) { t in
                    HStack {
                        Cell(text: t.label, alignment: .leading, weight: .semibold, size: 21)
                        Cell(text: Fmt.fixed(last.rates[t.key], 2, "%"), width: 110, weight: .semibold, size: 21)
                        Cell(text: Fmt.signed(bp(last.rates[t.key], prev?.rates[t.key]), 0), width: 110, size: 21)
                        Cell(text: Fmt.signed(bp(last.rates[t.key], month?.rates[t.key]), 0), width: 120, size: 21)
                        Cell(text: Fmt.signed(bp(last.rates[t.key], year?.rates[t.key]), 0), width: 120, size: 21)
                    }
                }
                Text("Changes in basis points").font(.system(size: 17)).foregroundStyle(Theme.muted)
            }
        }
    }
}
