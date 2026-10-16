import SwiftUI

/// Alpha Signal Scout (port 8082) serves HTML pages (plus /api/status), so the TV reads the
/// Overview ("/") and Signal Cards ("/signals") pages and extracts the same figures.
enum HTMLText {
    static func matches(_ pattern: String, in s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    static func first(_ pattern: String, in s: String) -> String? {
        guard let m = matches(pattern, in: s).first, m.count > 1 else { return nil }
        let t = clean(m[1])
        return t.isEmpty ? nil : t
    }

    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (a, b) in [("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&#x27;", "'"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AlphaBadge: Hashable {
    let text: String
    let color: Color

    static func color(for cls: String) -> Color {
        if cls.contains("bg-success") { return Theme.supportive }
        if cls.contains("bg-primary") { return Theme.accent }
        if cls.contains("bg-warning") { return Theme.mixed }
        if cls.contains("bg-danger") { return Theme.adverse }
        if cls.contains("bg-dark") { return Theme.ink }
        return Theme.unavailable
    }
}

struct AlphaCard: Identifiable {
    let id: Int
    let strong: Bool
    let title: String
    let authors: String?
    let score: String?
    let scoreNote: String?
    let badges: [AlphaBadge]
    let type: String?
    let horizon: String?
    let actionability: String?
    let sample: String?
    let implied: String?
    let findings: String?
    let limitations: String?

    static func parse(_ html: String) -> [AlphaCard] {
        let blocks = html.components(separatedBy: "<div class=\"card mb-3").dropFirst()
        return blocks.enumerated().compactMap { i, block in
            let header = block.components(separatedBy: "<div class=\"card-body\">").first ?? block
            let badgePart = header.components(separatedBy: "<a href").first ?? header
            let badges = HTMLText.matches("<span class=\"badge ([^\"]*)\"[^>]*>(.*?)</span>", in: badgePart).compactMap { m -> AlphaBadge? in
                let t = HTMLText.clean(m[2])
                return t.isEmpty ? nil : AlphaBadge(text: t, color: AlphaBadge.color(for: m[1]))
            }
            guard let title = HTMLText.first("fw-bold\">(.*?)(?:<i |</a>)", in: header) else { return nil }
            func field(_ label: String) -> String? {
                HTMLText.first("<div class=\"text-muted small\">\(label)</div>\\s*<(?:span|div)[^>]*>(.*?)</(?:span|div)>", in: block)
            }
            return AlphaCard(
                id: i,
                strong: block.hasPrefix(" border-success"),
                title: title,
                authors: HTMLText.first("</a>\\s*<div class=\"text-muted small\">(.*?)<a ", in: header),
                score: HTMLText.first("fs-6\" title=\"Value[^\"]*\">(.*?)</span>", in: header),
                scoreNote: HTMLText.first("<div class=\"text-end\">.*?<div class=\"text-muted small\">(.*?)</div>", in: header),
                badges: badges,
                type: field("Signal Type"),
                horizon: field("Time Horizon"),
                actionability: field("Actionability"),
                sample: field("Sample Period"),
                implied: field("Implied Signal"),
                findings: field("Key Findings"),
                limitations: field("Limitations"))
        }
    }
}

struct AlphaSection: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var feed = FeedStore()

    var body: some View {
        AlphaScreen(feed: feed)
            .task(id: settings.refreshToken) {
                await poll(every: 900) {
                    await feed.load(base: settings.dashboardBase(port: 8082), json: ["/api/status"], text: ["/", "/signals"])
                }
            }
    }
}

struct AlphaScreen: View {
    @ObservedObject var feed: FeedStore

    var body: some View {
        let home = feed.text["/"] ?? ""
        let signals = feed.text["/signals"] ?? ""
        let stats = HTMLText.matches("<div class=\"text-muted small\">([^<]+)</div>\\s*<div class=\"fs-3 fw-bold\">([^<]+)</div>", in: home)
            .map { (HTMLText.clean($0[1]), HTMLText.clean($0[2])) }
        let cards = AlphaCard.parse(signals)
        let strong = HTMLText.first("(\\d+) strong evidence", in: signals)
        let botReady = HTMLText.first("(\\d+) bot-ready", in: signals)
        let status = feed["/api/status"]
        return Screen {
            ScreenHeader(title: "Alpha Signal Scout", subtitle: "Academic research pipeline · signal cards sorted by value score",
                         badge: status["running"].bool == true ? "PIPELINE RUNNING" : nil, badgeColor: Theme.mixed,
                         updated: feed.updated)
            if let e = feed.error { Banner(text: e) }
            if let err = status["last_error"].string { Banner(text: "Last pipeline error: \(err)") }
            if !stats.isEmpty {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(Array(stats.prefix(6).enumerated()), id: \.offset) { _, s in
                        KPI(title: s.0, value: s.1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if !cards.isEmpty {
                SectionTitle(text: "Signal cards",
                             note: "\(cards.count) cards · \(strong ?? "—") strong evidence · \(botReady ?? "—") bot-ready")
                ForEach(cards) { c in AlphaCardView(card: c) }
            } else if feed.attempted && feed.text["/signals"] != nil {
                Banner(text: "The Signal Cards page loaded but no cards could be read from it. Its layout may have changed.", color: Theme.mixed)
            } else if !feed.attempted {
                LoadingLine(text: "Loading Alpha Signal Scout…")
            }
        }
    }
}

private struct AlphaCardView: View {
    let card: AlphaCard

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(card.badges, id: \.self) { b in Pill(text: b.text, color: b.color, size: 17) }
                        }
                        Text(card.title).font(.system(size: 27, weight: .bold)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let a = card.authors { Text(a).font(.system(size: 18)).foregroundStyle(Theme.muted).lineLimit(1) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(card.score ?? "—").font(.system(size: 46, weight: .heavy))
                            .foregroundStyle(card.strong ? Theme.supportive : Theme.accent)
                        if let n = card.scoreNote { Text(n).font(.system(size: 16)).foregroundStyle(Theme.muted) }
                    }
                    .fixedSize()
                }
                HStack(spacing: 34) {
                    fact("Signal type", card.type)
                    fact("Horizon", card.horizon)
                    fact("Actionability", card.actionability)
                    fact("Sample", card.sample)
                }
                if let s = card.implied { block("Implied signal", s, lines: 4) }
                if let s = card.findings { block("Key findings", s, lines: 4) }
                if let s = card.limitations { block("Limitations", s, lines: 3) }
            }
        }
        .overlay(alignment: .leading) {
            if card.strong {
                RoundedRectangle(cornerRadius: 3).fill(Theme.supportive).frame(width: 8).padding(.vertical, 18)
            }
        }
    }

    private func fact(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.muted)
            Text(value ?? "—").font(.system(size: 21, weight: .semibold)).foregroundStyle(Theme.ink)
        }
    }

    private func block(_ label: String, _ text: String, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(text).font(.system(size: 20)).foregroundStyle(Theme.ink).lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
