import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// White cards on navy, matching the dashboard's white/navy grouping.
enum Theme {
    static let background = Color(hex: 0x0A1A33)
    static let card = Color.white
    static let ink = Color(hex: 0x0B2545)
    static let muted = Color(hex: 0x5B6B82)
    static let onNavy = Color.white
    static let onNavyMuted = Color(hex: 0xB7C4D8)
    static let accent = Color(hex: 0x075BCB)
    static let adverse = Color(hex: 0xC62835)
    static let supportive = Color(hex: 0x16824B)
    static let mixed = Color(hex: 0xB7791F)
    static let unavailable = Color(hex: 0x8994A5)
    static let lines: [Color] = [Color(hex: 0x075BCB), Color(hex: 0x783DB9), Color(hex: 0xEF3043), Color(hex: 0x8994A5)]

    static func tone(_ t: String?) -> Color {
        switch t {
        case "adverse": return adverse
        case "supportive": return supportive
        case "mixed": return mixed
        default: return unavailable
        }
    }

    static func change(_ v: Double?) -> Color {
        guard let v else { return unavailable }
        return v < 0 ? adverse : v > 0 ? supportive : muted
    }
}

/// White card. Focusable so the Siri Remote can move through (and scroll) every screen.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    @FocusState private var focused: Bool

    var body: some View {
        content
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(focused ? Theme.accent : Color.clear, lineWidth: 5))
            .environment(\.colorScheme, .light)
            .scaleEffect(focused ? 1.015 : 1)
            .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 18, y: 8)
            .animation(.easeOut(duration: 0.15), value: focused)
            .focusable()
            .focused($focused)
    }
}

struct ScreenHeader: View {
    let title: String
    let subtitle: String
    var badge: String? = nil
    var badgeColor: Color = Theme.accent
    var updated: Date? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 52, weight: .bold)).foregroundStyle(Theme.onNavy)
                Text(subtitle).font(.system(size: 24)).foregroundStyle(Theme.onNavyMuted)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(.system(size: 24, weight: .bold))
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Capsule().fill(badgeColor))
                    .foregroundStyle(.white)
            }
            if let updated {
                Text("Updated \(Fmt.localTime(updated))").font(.system(size: 22)).foregroundStyle(Theme.onNavyMuted)
            }
        }
    }
}

struct Banner: View {
    let text: String
    var color: Color = Theme.adverse

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(color))
    }
}

struct Screen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 28) { content }
                .padding(.horizontal, 64)
                .padding(.vertical, 30)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
