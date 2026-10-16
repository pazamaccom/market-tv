import SwiftUI
import Charts

// MARK: Polling and addresses

/// Runs `work` now and then every `seconds` until the surrounding task is cancelled
/// (SwiftUI cancels a `.task` when its screen disappears).
func poll(every seconds: Double, _ work: () async -> Void) async {
    while !Task.isCancelled {
        await work()
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

extension AppSettings {
    /// Same host as the Market address, different port (all dashboards run on trader-node).
    func dashboardBase(port: Int) -> String {
        let trimmed = marketBase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var c = URLComponents(string: trimmed), c.host != nil else { return "http://100.127.41.102:\(port)" }
        c.port = port
        c.path = ""
        c.query = nil
        c.fragment = nil
        return c.string ?? "http://100.127.41.102:\(port)"
    }
}

/// Read-only GETs for one dashboard. Each path is stored separately so a single failing
/// endpoint does not blank the whole screen.
@MainActor
final class FeedStore: ObservableObject {
    @Published private(set) var json: [String: J] = [:]
    @Published private(set) var text: [String: String] = [:]
    @Published private(set) var error: String?
    @Published private(set) var updated: Date?
    @Published private(set) var attempted = false

    subscript(path: String) -> J { json[path] ?? J(nil) }

    func load(base: String, json paths: [String], text textPaths: [String] = []) async {
        var failures: [String] = []
        var firstError: String?
        var newJSON = json
        var newText = text
        for p in paths {
            do {
                newJSON[p] = try API.parse(try await API.data(base, p))
            } catch let e {
                failures.append(p)
                if firstError == nil { firstError = API.describe(e) }
            }
        }
        for p in textPaths {
            do {
                newText[p] = String(decoding: try await API.data(base, p), as: UTF8.self)
            } catch let e {
                failures.append(p)
                if firstError == nil { firstError = API.describe(e) }
            }
        }
        json = newJSON
        text = newText
        let total = paths.count + textPaths.count
        if failures.isEmpty {
            error = nil
        } else if failures.count == total {
            error = firstError
        } else {
            error = "Some data could not be loaded (\(failures.joined(separator: ", "))): \(firstError ?? "")"
        }
        if failures.count < total { updated = Date() }
        attempted = true
    }
}

// MARK: Formatting

extension Fmt {
    /// 23_509_997 → "23.51M"; with prefix "$" → "$23.51M".
    static func compact(_ v: Double?, prefix: String = "", signed: Bool = false) -> String {
        guard let v, v.isFinite else { return "—" }
        let a = abs(v)
        let sign = v < 0 ? "−" : (signed && v > 0 ? "+" : "")
        let (n, unit): (Double, String) = a >= 1e9 ? (a / 1e9, "B") : a >= 1e6 ? (a / 1e6, "M") : a >= 1e3 ? (a / 1e3, "K") : (a, "")
        let digits = n >= 100 ? "%.0f" : n >= 10 ? "%.1f" : "%.2f"
        return sign + prefix + String(format: digits, n) + unit
    }

    static func grouped(_ v: Double?, _ digits: Int = 0) -> String {
        guard let v, v.isFinite else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// "2026-10-08" → "8 Oct 2026".
    static func dayLabel(_ s: String?) -> String {
        guard let s, let d = day(s) else { return s ?? "—" }
        return day(d)
    }
}

// MARK: Building blocks (white cards on navy, like the Market screens)

struct KPI: View {
    let title: String
    let value: String
    var sub: String? = nil
    var color: Color = Theme.ink
    var valueSize: CGFloat = 42

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 21, weight: .semibold)).foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(value).font(.system(size: valueSize, weight: .bold)).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let sub {
                    Text(sub).font(.system(size: 19)).foregroundStyle(Theme.muted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.accent
    var size: CGFloat = 19

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(color))
            .lineLimit(1)
            .fixedSize()
    }
}

struct SectionTitle: View {
    let text: String
    var note: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(text).font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.onNavy)
            if let note { Text(note).font(.system(size: 21)).foregroundStyle(Theme.onNavyMuted) }
        }
        .padding(.top, 6)
    }
}

/// One focusable table row, so the remote can scroll long lists.
struct FocusRow<Content: View>: View {
    @ViewBuilder var content: Content
    @FocusState private var focused: Bool

    var body: some View {
        content
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(focused ? Theme.accent : .clear, lineWidth: 4))
            .environment(\.colorScheme, .light)
            .scaleEffect(focused ? 1.01 : 1)
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 12, y: 6)
            .animation(.easeOut(duration: 0.12), value: focused)
            .focusable()
            .focused($focused)
    }
}

/// Column header text above a run of FocusRows.
struct HeaderCell: View {
    let text: String
    var width: CGFloat? = nil
    var alignment: Alignment = .leading

    var body: some View {
        Text(text).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.onNavyMuted)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

struct Cell: View {
    let text: String
    var width: CGFloat? = nil
    var alignment: Alignment = .trailing
    var color: Color = Theme.ink
    var weight: Font.Weight = .regular
    var size: CGFloat = 22

    var body: some View {
        Text(text).font(.system(size: size, weight: weight)).foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

struct SeriesPoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double
}

/// Builds dated points from parallel date / value arrays.
func seriesPoints(dates: J, values: J, last n: Int? = nil) -> [SeriesPoint] {
    let d = dates.array, v = values.array
    var out: [SeriesPoint] = []
    for i in 0..<min(d.count, v.count) {
        if let s = d[i].string, let date = Fmt.day(s), let x = v[i].finite {
            out.append(SeriesPoint(id: i, date: date, value: x))
        }
    }
    if let n, out.count > n { out = Array(out.suffix(n)) }
    return out
}

struct LineChartPanel: View {
    let title: String
    var subtitle: String? = nil
    let points: [SeriesPoint]
    var color: Color = Theme.accent
    var valueText: (Double) -> String = { Fmt.fixed($0, 2) }
    var yearAxis = false
    var logScale = false
    var zeroLine = false
    var height: CGFloat = 240

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let last = points.last {
                    Text(subtitle ?? "\(valueText(last.value)) · \(Fmt.day(last.date))")
                        .font(.system(size: 20)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
                    chart.frame(height: height)
                } else {
                    Text("No data.").font(.system(size: 20)).foregroundStyle(Theme.muted).frame(height: height)
                }
            }
        }
    }

    @ViewBuilder private var chart: some View {
        let base = Chart {
            if zeroLine {
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.muted.opacity(0.6))
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value(title, p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 3))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: yearAxis ? .dateTime.year() : .dateTime.month(.abbreviated).year(.twoDigits))
            }
        }
        if logScale {
            base.chartYScale(domain: .automatic(includesZero: false), type: .log)
        } else {
            base.chartYScale(domain: .automatic(includesZero: zeroLine))
        }
    }
}

/// Plain-text paragraph on the navy background.
struct Note: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 20)).foregroundStyle(Theme.onNavyMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct LoadingLine: View {
    let text: String

    var body: some View {
        ProgressView(text).font(.system(size: 28)).foregroundStyle(Theme.onNavy)
    }
}
