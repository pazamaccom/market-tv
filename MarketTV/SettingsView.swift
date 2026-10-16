import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var market: MarketStore

    var body: some View {
        Screen {
            ScreenHeader(title: "Settings", subtitle: "Read-only client · private Tailscale addresses")
            VStack(alignment: .leading, spacing: 22) {
                field("US Market Health address", text: $settings.marketBase)
                field("P | ANALYTICS hub address", text: $settings.hubBase)
                Toggle("Use the dashboard's synthetic demo data", isOn: $settings.demoMode)
                    .font(.system(size: 26))
                Toggle("Keep the screen awake while open", isOn: $settings.keepAwake)
                    .font(.system(size: 26))
                HStack(spacing: 24) {
                    Button("Refresh now") { settings.refreshToken += 1 }
                    Button("Reset addresses") { settings.resetAddresses() }
                }
                .font(.system(size: 26))
            }
            .frame(maxWidth: 1200, alignment: .leading)
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("About").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.ink)
                    info("Market server commit", market.commit ?? "—")
                    info("Record", market.snapshot["id"].string ?? "—")
                    info("Interpretation", market.model["version"].string ?? (market.interpretationError ?? "not loaded"))
                    info("Last Market refresh", market.updated.map(Fmt.localTime) ?? "—")
                    Text("Overview wording and downturn names are produced by the dashboard's own app.js, loaded from the server and re-loaded whenever its commit changes. This app only reads data; it never changes anything on trader-node. Tailscale must stay connected on this Apple TV.")
                        .font(.system(size: 20)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 1200)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.onNavyMuted)
            TextField(label, text: text)
                .font(.system(size: 26))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.system(size: 21, weight: .semibold)).foregroundStyle(Theme.muted).frame(width: 300, alignment: .leading)
            Text(v).font(.system(size: 21)).foregroundStyle(Theme.ink).lineLimit(2)
        }
    }
}
