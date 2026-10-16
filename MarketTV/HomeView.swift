import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// One card of the P | ANALYTICS command center. Artwork rectangles are the same crops of
/// /assets/reference.png that the 8087 hub page uses, so the TV shows identical artwork.
struct HubCard: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let port: Int
    let accent: UInt32
    let art: CGRect

    var color: Color { Color(hex: accent) }
    /// Every dashboard has a TV screen except the BTC bot, which is not live yet.
    var onTV: Bool { id != "btc" }
}

enum HubCatalog {
    static let referenceWidth: CGFloat = 1536
    static let world = CGRect(x: 770, y: 90, width: 520, height: 185)
    static let cards: [HubCard] = [
        .init(id: "turkey", name: "Turkey Fund Tracker", blurb: "Track Turkish funds, performance and market trends.", port: 8081, accent: 0xFF365E, art: CGRect(x: 49, y: 277, width: 338, height: 143)),
        .init(id: "market", name: "US Market Health", blurb: "Market conditions, risk indicators and broader macro signals.", port: 8085, accent: 0x00BAFF, art: CGRect(x: 418, y: 277, width: 337, height: 143)),
        .init(id: "stocks", name: "Stock Attractiveness", blurb: "Find value and opportunities across global markets.", port: 8083, accent: 0x00D796, art: CGRect(x: 787, y: 277, width: 336, height: 143)),
        .init(id: "drawdown", name: "US Drawdown and Downturn", blurb: "Analyse historical declines, downturns and recovery patterns.", port: 8080, accent: 0xFF970B, art: CGRect(x: 1154, y: 277, width: 335, height: 143)),
        .init(id: "yield", name: "Yield Curve", blurb: "Explore interest rates, yield curves and fixed income spreads.", port: 8084, accent: 0xA269FF, art: CGRect(x: 49, y: 622, width: 412, height: 143)),
        .init(id: "alpha", name: "Alpha Signal Scout", blurb: "Identify high-conviction signals across markets.", port: 8082, accent: 0x00E5F0, art: CGRect(x: 491, y: 622, width: 382, height: 143)),
        .init(id: "btc", name: "BTC Trading Bot", blurb: "Automated trading, signals and performance tracking.", port: 8086, accent: 0xFFB32E, art: CGRect(x: 905, y: 622, width: 388, height: 143)),
    ]

    static func card(_ id: String) -> HubCard? { cards.first { $0.id == id } }
}

enum Route: Hashable {
    case market
    case settings
    case section(String)
    case dashboard(String)
}

/// Downloads the hub's own artwork once and cuts out the hero map and the seven card images.
@MainActor
final class ArtStore: ObservableObject {
    @Published private(set) var crops: [String: UIImage] = [:]
    @Published private(set) var world: UIImage?
    private var loadedBase: String?

    func load(base: String) async {
        if loadedBase == base, !crops.isEmpty { return }
        guard let data = try? await API.data(base, "/assets/reference.png"),
              let image = UIImage(data: data)?.cgImage else { return }
        let s = CGFloat(image.width) / HubCatalog.referenceWidth
        func crop(_ r: CGRect) -> UIImage? {
            let rect = CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s).integral
            return image.cropping(to: rect).map { UIImage(cgImage: $0) }
        }
        var out: [String: UIImage] = [:]
        for card in HubCatalog.cards { out[card.id] = crop(card.art) }
        crops = out
        world = crop(HubCatalog.world)
        loadedBase = base
    }
}

enum HubPalette {
    static let background = Color(hex: 0x06111B)
    static let card = Color(hex: 0x091520)
    static let text = Color(hex: 0xF0F1F7)
    static let muted = Color(hex: 0xBDCADB)
    static let secondary = Color(hex: 0x8EA7C8)
    static let faint = Color(hex: 0xB5C9E4)
}

struct HomeBackground: View {
    var body: some View {
        ZStack {
            HubPalette.background
            RadialGradient(colors: [Color(hex: 0x143249), .clear], center: UnitPoint(x: 0.55, y: -0.2), startRadius: 0, endRadius: 1000)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var hub: HubStore
    @EnvironmentObject private var art: ArtStore
    @FocusState private var focused: String?

    private var firstRow: [HubCard] { Array(HubCatalog.cards.prefix(4)) }
    private var secondRow: [HubCard] { Array(HubCatalog.cards.dropFirst(4)) }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 28) {
                header
                hero
                HStack(alignment: .top, spacing: 32) {
                    ForEach(firstRow) { tile($0) }
                }
                HStack(alignment: .top, spacing: 32) {
                    ForEach(secondRow) { tile($0) }
                    quote
                }
                footer
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 28)
        }
        .background(HomeBackground().ignoresSafeArea())
        .defaultFocus($focused, "market")
    }

    // MARK: Header and hero (same wording as the 8087 page)

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return "Good \(hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"), Paolo"
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE, d MMM yyyy"
        return f.string(from: Date()).uppercased()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 26) {
            Text("P").font(.system(size: 68, design: .serif))
            Rectangle().fill(Color(hex: 0xCBD4DF)).frame(width: 1.5, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("ANALYTICS").font(.system(size: 42, design: .serif)).tracking(4)
                Text("MARKETS · DATA · OPPORTUNITIES").font(.system(size: 14)).tracking(3).foregroundStyle(Color(hex: 0xA7B9CF))
            }
            Spacer()
            Text(greeting).font(.system(size: 24))
            Text("P")
                .font(.system(size: 28, design: .serif))
                .frame(width: 54, height: 54)
                .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x798BB8), Color(hex: 0x3E538A)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            NavigationLink(value: Route.settings) {
                Image(systemName: "gearshape").font(.system(size: 26))
            }
            .focused($focused, equals: "settings")
        }
        .foregroundStyle(HubPalette.text)
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            if let world = art.world {
                HStack {
                    Spacer()
                    Image(uiImage: world)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 210)
                        .opacity(0.85)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .padding(.trailing, 280)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(dateLine).font(.system(size: 17)).tracking(5).foregroundStyle(HubPalette.faint)
                Text("Your Financial Command Center").font(.system(size: 64, weight: .bold, design: .serif)).foregroundStyle(HubPalette.text)
                Text("Seven dashboards. A broader perspective.").font(.system(size: 32)).foregroundStyle(HubPalette.secondary)
            }
            .padding(.top, 20)
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Text("BETTER DATA")
                    Text("BRIGHTER DECISIONS")
                    Rectangle().fill(Color(hex: 0x98B1CC)).frame(width: 56, height: 1)
                }
                .font(.system(size: 16)).tracking(4).foregroundStyle(Color(hex: 0xB4C9E6))
                .padding(.top, 50)
            }
        }
        .frame(height: 210)
    }

    // MARK: Cards

    private func tile(_ card: HubCard) -> some View {
        NavigationLink(value: card.id == "market" ? Route.market : card.onTV ? Route.section(card.id) : Route.dashboard(card.id)) {
            HubTile(card: card, art: art.crops[card.id], online: hub.online[card.id], hubError: hub.error != nil)
        }
        .buttonStyle(.card)
        .focused($focused, equals: card.id)
        .frame(maxWidth: .infinity)
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Discipline\ntoday,\nopportunities\ntomorrow.")
                .font(.system(size: 34, design: .serif).italic())
                .foregroundStyle(Color(hex: 0xBDCCE0))
            Rectangle().fill(Color(hex: 0x98B1CC)).frame(width: 48, height: 1)
        }
        .padding(.leading, 30)
        .frame(maxWidth: .infinity, minHeight: HubTile.height, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Text("PRIVATE ANALYTICS WORKSPACE").font(.system(size: 15)).tracking(4)
            Spacer()
            if let e = hub.error {
                Text(e).font(.system(size: 17)).foregroundStyle(Color(hex: 0xEFB65C)).lineLimit(1)
            } else {
                Text("Data drives perspective. Perspective drives opportunity.").font(.system(size: 17))
            }
        }
        .foregroundStyle(Color(hex: 0x758CA7))
        .padding(.top, 6)
    }
}

struct StatusLine: View {
    let online: Bool?
    let hubError: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 16, height: 16)
            Text(label).font(.system(size: 21)).foregroundStyle(color)
        }
    }

    private var label: String { online == true ? "Online" : online == false ? "Offline" : hubError ? "Status unavailable" : "Checking…" }
    private var color: Color { online == true ? Color(hex: 0x61E3AD) : online == false ? Color(hex: 0xEFB65C) : Color(hex: 0x8FA5BC) }
    private var dot: Color { online == true ? Color(hex: 0x0ED452) : online == false ? Color(hex: 0xDF9C3E) : Color(hex: 0x7D8FA5) }
}

struct HubTile: View {
    static let height: CGFloat = 410
    let card: HubCard
    let art: UIImage?
    let online: Bool?
    let hubError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let art {
                    Image(uiImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [card.color.opacity(0.55), HubPalette.card], startPoint: .topTrailing, endPoint: .bottomLeading)
                }
            }
            .frame(height: 176)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.72), .init(color: HubPalette.card, location: 1)],
                                    startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 8) {
                Text(card.name)
                    .font(.system(size: 29, weight: .semibold)).foregroundStyle(HubPalette.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(card.blurb)
                    .font(.system(size: 21)).foregroundStyle(HubPalette.muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                StatusLine(online: online, hubError: hubError)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Text(card.onTV ? "Open Dashboard" : "Coming soon")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(card.color)
                .padding(.horizontal, 20)
                .frame(height: 50)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(card.color, lineWidth: 2))
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .top)
        .background(HubPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(card.color.opacity(0.45), lineWidth: 1.5))
    }
}

// MARK: Dashboards that do not have a TV version yet

enum QR {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 14, y: 14)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct DashboardInfoView: View {
    let card: HubCard
    @EnvironmentObject private var hub: HubStore
    @EnvironmentObject private var art: ArtStore
    @Environment(\.dismiss) private var dismiss

    private var url: String { hub.urls[card.id] ?? "http://100.127.41.102:\(card.port)/" }

    var body: some View {
        HStack(alignment: .center, spacing: 90) {
            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    if let image = art.crops[card.id] {
                        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        LinearGradient(colors: [card.color.opacity(0.6), HubPalette.card], startPoint: .topTrailing, endPoint: .bottomLeading)
                    }
                }
                .frame(width: 820, height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(card.color.opacity(0.5), lineWidth: 2))
                Text(card.name).font(.system(size: 58, weight: .bold, design: .serif)).foregroundStyle(HubPalette.text)
                Text(card.blurb).font(.system(size: 28)).foregroundStyle(HubPalette.muted)
                StatusLine(online: hub.online[card.id], hubError: hub.error != nil)
                Text(card.id == "btc" ? "The BTC Trading Bot dashboard is not fully active yet. Its TV screen will be added when it goes live. Meanwhile you can scan the code with your iPhone camera to open the web page (Tailscale must be connected on the phone)." : "Scan the code with your iPhone camera to open this dashboard in Safari; Tailscale must be connected on the phone.")
                    .font(.system(size: 24)).foregroundStyle(HubPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 820, alignment: .leading)
                Text(url).font(.system(size: 24, design: .monospaced)).foregroundStyle(card.color)
                Button("Back to dashboards") { dismiss() }
                    .font(.system(size: 24))
                    .padding(.top, 8)
            }
            VStack(spacing: 18) {
                if let qr = QR.image(url) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 440, height: 440)
                        .padding(28)
                        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
                }
                Text("Scan to open").font(.system(size: 26, weight: .semibold)).foregroundStyle(HubPalette.text)
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HomeBackground().ignoresSafeArea())
    }
}
