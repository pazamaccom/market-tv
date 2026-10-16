import SwiftUI
import Charts

private struct IntradayPoint: Identifiable {
    let id: String
    let time: Date
    let index: Double
    let symbol: String
    let segment: String
}

/// Provisional intraday view. Observed venue minutes only; gaps stay gaps (never filled).
struct TodayView: View {
    @EnvironmentObject private var store: TodayStore
    @EnvironmentObject private var settings: AppSettings

    private let headline = ["SPY", "RSP", "QQQ", "IWM"]
    private let order = ["SPY", "RSP", "QQQ", "IWM", "XLK", "XLF", "XLE", "XLV", "XLI", "XLP", "XLY", "XLU", "XLB", "XLRE", "XLC", "SMH", "HYG", "LQD", "TLT", "IEF"]

    private var t: J { store.today }
    private var instruments: J { t["instruments"] }

    private var symbols: [String] {
        let keys = Set(instruments.object.keys)
        return order.filter(keys.contains) + keys.subtracting(order).sorted()
    }

    var body: some View {
        Screen {
            ScreenHeader(title: "Today", subtitle: status,
                         badge: t["synthetic"].bool == true ? "DEMO — SYNTHETIC" : "LIVE · PROVISIONAL",
                         badgeColor: t["synthetic"].bool == true ? Theme.mixed : Theme.accent,
                         updated: store.updated)
            if let e = store.error { Banner(text: e) }
            if t.exists {
                HStack(spacing: 18) {
                    ForEach(headline, id: \.self) { s in headlineTile(s) }
                }
                .fixedSize(horizontal: false, vertical: true)
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Headline price development · previous close = 100").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.ink)
                        chart(headline, height: 380, axes: true)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                    ForEach(symbols.filter { !headline.contains($0) }, id: \.self) { s in smallTile(s) }
                }
                Text([t["source"].string, t["timestamp_basis"].string].compactMap { $0 }.joined(separator: " · ") + ". Venue minutes, not consolidated prices; missing minutes are left as gaps.")
                    .font(.system(size: 20)).foregroundStyle(Theme.onNavyMuted)
            } else if store.error == nil {
                ProgressView("Loading Today…").foregroundStyle(Theme.onNavy)
            }
        }
    }

    private var status: String {
        let s = t["session"]
        guard s.exists else { return "Intraday context" }
        var parts = [s["day"].string ?? "—", s["state"].string ?? ""]
        if let tr = t["transport"]["state"].string, tr != s["state"].string { parts.append(tr) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func change(_ s: String) -> Double? { instruments[s]["change_percent"].finite }

    private func observed(_ s: String) -> String {
        guard let d = Fmt.iso(instruments[s]["timestamp"].string) else { return "No verified observation" }
        return "\(Fmt.ny(d)) New York"
    }

    private func headlineTile(_ s: String) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(s) · ETF price").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.muted)
                Text(Fmt.signed(change(s), 2, "%")).font(.system(size: 56, weight: .heavy)).foregroundStyle(Theme.change(change(s)))
                Text(instruments[s]["state"].string ?? "").font(.system(size: 19)).foregroundStyle(Theme.muted)
                Text(observed(s)).font(.system(size: 19)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func smallTile(_ s: String) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(Fmt.signed(change(s), 2, "%")).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.change(change(s)))
                }
                chart([s], height: 70, axes: false)
                Text(observed(s)).font(.system(size: 16)).foregroundStyle(Theme.muted)
            }
        }
    }

    /// Lines break wherever consecutive observations are not exactly one minute apart (as in today.js).
    private func points(_ syms: [String]) -> [IntradayPoint] {
        var out: [IntradayPoint] = []
        for s in syms {
            var previous: Double?
            var segment = 0
            for (i, p) in instruments[s]["history"].array.enumerated() {
                guard let ms = p["t"].finite, let index = p["index"].finite else { continue }
                if let previous, ms - previous != 60_000 { segment += 1 }
                previous = ms
                out.append(IntradayPoint(id: "\(s)-\(i)", time: Date(timeIntervalSince1970: ms / 1000), index: index, symbol: s, segment: "\(s)#\(segment)"))
            }
        }
        return out
    }

    @ViewBuilder
    private func chart(_ syms: [String], height: CGFloat, axes: Bool) -> some View {
        let data = points(syms)
        if data.isEmpty {
            Text("No verified observations yet. Live never substitutes Demo prices.")
                .font(.system(size: 18)).foregroundStyle(Theme.muted).frame(height: height)
        } else {
            Chart {
                RuleMark(y: .value("Previous close", 100))
                    .foregroundStyle(Theme.unavailable)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                ForEach(data) { p in
                    LineMark(x: .value("Time", p.time), y: .value("Index", p.index), series: .value("Segment", p.segment))
                        .foregroundStyle(by: .value("ETF", p.symbol))
                        .lineStyle(StrokeStyle(lineWidth: axes ? 3 : 2))
                }
            }
            .chartForegroundStyleScale(domain: syms, range: syms.count == 1 ? [Theme.change(change(syms[0]))] : Array(Theme.lines.prefix(syms.count)))
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                if axes {
                    AxisMarks(values: .automatic(desiredCount: 6)) { v in
                        AxisGridLine()
                        AxisValueLabel { if let d = v.as(Date.self) { Text(Fmt.ny(d)) } }
                    }
                }
            }
            .chartYAxis(axes ? .automatic : .hidden)
            .chartLegend(axes ? .visible : .hidden)
            .frame(height: height)
        }
    }
}
