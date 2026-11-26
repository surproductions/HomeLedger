import SwiftUI
import UIKit

/// HomeLedger design tokens. Colors adapt to light and dark appearance and were chosen to keep
/// text at WCAG AA contrast or better against their intended surfaces.
enum Theme {
    // MARK: Brand
    /// Deep "ledger blue" — primary actions and hero surfaces.
    static let brand = Color(light: 0x1E3FA0, dark: 0x6F8CFF)
    static let brandDeep = Color(light: 0x152F7E, dark: 0x2A3F99)
    static let brandSoft = Color(light: 0xE8EDFC, dark: 0x1D2547)
    static let heroTop = Color(light: 0x2347B5, dark: 0x1B2A6B)
    static let heroBottom = Color(light: 0x1A3893, dark: 0x141F52)

    // MARK: Surfaces
    static let canvas = Color(light: 0xF3F4F8, dark: 0x0C0E14)
    static let card = Color(light: 0xFFFFFF, dark: 0x171A23)
    static let cardRaised = Color(light: 0xF7F8FB, dark: 0x1F2330)
    static let hairline = Color(light: 0xE4E6EE, dark: 0x2A2E3B)

    // MARK: Text
    static let ink = Color(light: 0x11142B, dark: 0xF2F3F8)
    static let inkSecondary = Color(light: 0x5D6275, dark: 0xA3A8BA)
    static let inkTertiary = Color(light: 0x8A8FA3, dark: 0x7A7F92)

    // MARK: Status (used only to communicate meaning)
    static let success = Color(light: 0x18804F, dark: 0x4CD08A)
    static let warning = Color(light: 0xB86A00, dark: 0xF2B14C)
    static let danger = Color(light: 0xC23434, dark: 0xFF7A7A)
    static let info = Color(light: 0x4B4BC8, dark: 0x9C9CFF)

    // MARK: Accent tints for icon badges
    static let tintBlue = Color(light: 0x2F5BE0, dark: 0x7D9BFF)
    static let tintGreen = Color(light: 0x16855A, dark: 0x5ED39B)
    static let tintOrange = Color(light: 0xD0661B, dark: 0xFFA463)
    static let tintPurple = Color(light: 0x6B47D6, dark: 0xB39CFF)
    static let tintTeal = Color(light: 0x0F7C86, dark: 0x5CCCD6)
    static let tintPink = Color(light: 0xC23D7A, dark: 0xFF8DBF)

    // MARK: Gradients (used sparingly — hero and premium surfaces)
    static let heroGradient = LinearGradient(colors: [heroTop, heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let indigoGradient = LinearGradient(colors: [Color(light: 0x4A63E8, dark: 0x3A4FC4), Color(light: 0x6E56DB, dark: 0x5B45B8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let warmGradient = LinearGradient(colors: [Color(light: 0xF0825A, dark: 0xC9623F), Color(light: 0xD65C8F, dark: 0xA94473)], startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: Metrics
    static let radiusL: CGFloat = 24
    static let radiusM: CGFloat = 18
    static let radiusS: CGFloat = 12
    static let gutter: CGFloat = 16
    static let spacing: CGFloat = 12
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - Typography

extension Font {
    static let hlLargeNumber = Font.system(.largeTitle, design: .rounded).weight(.semibold)
    static let hlMetric = Font.system(.title2, design: .rounded).weight(.semibold)
    static let hlTitle = Font.system(.title2).weight(.semibold)
    static let hlHeadline = Font.system(.headline)
    static let hlBody = Font.system(.body)
    static let hlCaption = Font.system(.caption).weight(.medium)
}

// MARK: - Surfaces

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = Theme.radiusM
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline.opacity(scheme == .dark ? 1 : 0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.045), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = Theme.radiusM) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }

    /// Standard screen background.
    func canvasBackground() -> some View {
        background(Theme.canvas.ignoresSafeArea())
    }
}

/// Animation that respects Reduce Motion.
struct MotionSafe {
    static func animation(_ reduceMotion: Bool, _ animation: Animation = .spring(response: 0.35, dampingFraction: 0.85)) -> Animation? {
        reduceMotion ? nil : animation
    }
}
