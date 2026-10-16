import SwiftUI

struct HubView: View {
    @EnvironmentObject private var hub: HubStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Screen {
            ScreenHeader(title: "P | ANALYTICS", subtitle: "Dashboard reachability from \(settings.hubBase)", updated: hub.updated)
            if let e = hub.error { Banner(text: e) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 4), spacing: 18) {
                ForEach(HubStore.dashboards) { d in tile(d) }
            }
            Text("Online means the dashboard answers HTTP, not that its data is fresh. Dashboards other than US Market Health open on iPhone, iPad or Mac.")
                .font(.system(size: 21)).foregroundStyle(Theme.onNavyMuted)
        }
    }

    private func tile(_ d: DashboardInfo) -> some View {
        let state = hub.online[d.id]
        let color = state == true ? Theme.supportive : state == false ? Theme.adverse : Theme.unavailable
        return Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle().fill(color).frame(width: 20, height: 20)
                    Text(state == true ? "Online" : state == false ? "Offline" : "Unknown")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(color)
                }
                Text(d.name).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(2).minimumScaleFactor(0.8)
                Text("Port \(d.port)").font(.system(size: 20)).foregroundStyle(Theme.muted)
                if let onTV = d.onTV { Text(onTV).font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.accent) }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 190, alignment: .topLeading)
        }
    }
}
