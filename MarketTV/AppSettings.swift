import SwiftUI
import UIKit

enum Defaults {
    // Numeric Tailscale address: Market's listener is IPv4-only and accepts this Host header.
    static let market = "http://100.127.41.102:8085"
    static let hub = "http://100.127.41.102:8087"
}

@MainActor
final class AppSettings: ObservableObject {
    private let store = UserDefaults.standard

    @Published var marketBase: String { didSet { store.set(marketBase, forKey: "marketBase") } }
    @Published var hubBase: String { didSet { store.set(hubBase, forKey: "hubBase") } }
    @Published var demoMode: Bool { didSet { store.set(demoMode, forKey: "demoMode") } }
    @Published var keepAwake: Bool {
        didSet {
            store.set(keepAwake, forKey: "keepAwake")
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
    }
    /// Bumped to force an immediate refresh of every feed.
    @Published var refreshToken = 0

    init() {
        marketBase = store.string(forKey: "marketBase") ?? Defaults.market
        hubBase = store.string(forKey: "hubBase") ?? Defaults.hub
        demoMode = store.bool(forKey: "demoMode")
        keepAwake = store.object(forKey: "keepAwake") as? Bool ?? true
    }

    func resetAddresses() {
        marketBase = Defaults.market
        hubBase = Defaults.hub
    }
}
