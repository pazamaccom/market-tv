import SwiftUI
import UIKit

@main
struct MarketTVApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var market = MarketStore()
    @StateObject private var today = TodayStore()
    @StateObject private var hub = HubStore()
    @StateObject private var art = ArtStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(market)
                .environmentObject(today)
                .environmentObject(hub)
                .environmentObject(art)
                .preferredColorScheme(.dark)
        }
    }
}

/// Opens on the P | ANALYTICS command center. Choosing a card pushes its screen;
/// the remote's Back/Menu button returns to the command center.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var market: MarketStore
    @EnvironmentObject private var today: TodayStore
    @EnvironmentObject private var hub: HubStore
    @EnvironmentObject private var art: ArtStore
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .market:
                        MarketSection()
                    case .settings:
                        SettingsView()
                    case .section(let id):
                        switch id {
                        case "turkey": TurkeySection()
                        case "stocks": StocksSection()
                        case "drawdown": DrawdownSection()
                        case "yield": YieldSection()
                        case "alpha": AlphaSection()
                        default: if let card = HubCatalog.card(id) { DashboardInfoView(card: card) }
                        }
                    case .dashboard(let id):
                        if let card = HubCatalog.card(id) { DashboardInfoView(card: card) }
                    }
                }
        }
        .background(HubPalette.background.ignoresSafeArea())
        // Daily record: every 5 minutes. Today: every minute. Hub status: every 30 seconds (hub caches 15 s).
        .task(id: "m|\(settings.marketBase)|\(settings.demoMode)|\(settings.refreshToken)") {
            await repeating(300) { await market.refresh(base: settings.marketBase, demo: settings.demoMode) }
        }
        .task(id: "t|\(settings.marketBase)|\(settings.demoMode)|\(settings.refreshToken)") {
            await repeating(60) { await today.refresh(base: settings.marketBase, demo: settings.demoMode) }
        }
        .task(id: "h|\(settings.hubBase)|\(settings.refreshToken)") {
            await repeating(30) { await hub.refresh(base: settings.hubBase) }
        }
        // Hub artwork: loaded once; retried every 2 minutes until it succeeds.
        .task(id: "a|\(settings.hubBase)") {
            await repeating(120) { await art.load(base: settings.hubBase) }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = settings.keepAwake }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active { settings.refreshToken += 1 }
            UIApplication.shared.isIdleTimerDisabled = newPhase == .active && settings.keepAwake
        }
    }

    private func repeating(_ seconds: Double, _ work: () async -> Void) async {
        while !Task.isCancelled {
            await work()
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }
}

/// US Market Health on the TV: three tabs fed by port 8085.
struct MarketSection: View {
    var body: some View {
        TabView {
            HealthView().tabItem { Text("Market Health") }
            DownturnView().tabItem { Text("Downturn") }
            TodayView().tabItem { Text("Today") }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
