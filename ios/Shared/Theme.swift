import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// A colour that switches with light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let v = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}

/// A colour scheme. Every screen reads its colours from the current theme, so switching is instant.
struct AppTheme: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// Main block colour (timer, buttons). Text on it uses `onBrand`.
    let brand: Color
    let onBrand: Color
    /// The "pop" colour: finished books, the current bar, the streak number.
    let highlight: Color
    let onHighlight: Color
    /// A readable version of the brand colour for text and lines on the page background.
    let brandText: Color
    /// The dark boards behind scores and charts.
    let board: Color
    let boardText: Color
    let boardMuted: Color
    let boardGrid: Color
    /// Card backgrounds on the page.
    let surface: Color
    /// Alternate app icon name in the asset catalog; nil means the main icon.
    let iconName: String?

    static func == (a: AppTheme, b: AppTheme) -> Bool { a.id == b.id }

    static let neon = AppTheme(
        id: "neon", name: "Neon",
        brand: Color(hex: 0xFF2E93), onBrand: Color(hex: 0x111113),
        highlight: Color(hex: 0x39FF14), onHighlight: Color(hex: 0x111113),
        brandText: Color(light: 0xC2185B, dark: 0xFF6FB1),
        board: Color(light: 0x111113, dark: 0x1C1C21), boardText: .white,
        boardMuted: Color(hex: 0xA3A3AD), boardGrid: Color(hex: 0x2C2C33),
        surface: Color(light: 0xF3F3F5, dark: 0x18181C), iconName: nil)

    static let ink = AppTheme(
        id: "ink", name: "Ink",
        brand: Color(light: 0x111113, dark: 0xF3F3F5), onBrand: Color(light: 0xFFFFFF, dark: 0x111113),
        highlight: Color(hex: 0xFFD60A), onHighlight: Color(hex: 0x111113),
        brandText: Color(light: 0x111113, dark: 0xF3F3F5),
        board: Color(light: 0x2A2A2E, dark: 0x1C1C21), boardText: .white,
        boardMuted: Color(hex: 0xA3A3AD), boardGrid: Color(hex: 0x3A3A40),
        surface: Color(light: 0xF2F2F2, dark: 0x18181C), iconName: "AppIcon-Ink")

    static let ocean = AppTheme(
        id: "ocean", name: "Ocean",
        brand: Color(hex: 0x1E88E5), onBrand: .white,
        highlight: Color(hex: 0x2EE6C9), onHighlight: Color(hex: 0x062A30),
        brandText: Color(light: 0x1565C0, dark: 0x64B5F6),
        board: Color(light: 0x0B2540, dark: 0x0F1E2E), boardText: .white,
        boardMuted: Color(hex: 0x9FB6CC), boardGrid: Color(hex: 0x1D3A57),
        surface: Color(light: 0xEEF4FA, dark: 0x111A24), iconName: "AppIcon-Ocean")

    static let forest = AppTheme(
        id: "forest", name: "Forest",
        brand: Color(hex: 0x2E7D32), onBrand: .white,
        highlight: Color(hex: 0xC6F432), onHighlight: Color(hex: 0x1B2A05),
        brandText: Color(light: 0x2E7D32, dark: 0x81C784),
        board: Color(light: 0x14261A, dark: 0x101C14), boardText: .white,
        boardMuted: Color(hex: 0xA5BFA8), boardGrid: Color(hex: 0x24402C),
        surface: Color(light: 0xF0F5EF, dark: 0x131A14), iconName: "AppIcon-Forest")

    static let sunset = AppTheme(
        id: "sunset", name: "Sunset",
        brand: Color(hex: 0xFF6B35), onBrand: Color(hex: 0x1F0E05),
        highlight: Color(hex: 0xFFD23F), onHighlight: Color(hex: 0x1F0E05),
        brandText: Color(light: 0xD84315, dark: 0xFF8A65),
        board: Color(light: 0x2B1720, dark: 0x1E1217), boardText: .white,
        boardMuted: Color(hex: 0xC9A9B4), boardGrid: Color(hex: 0x45283A),
        surface: Color(light: 0xFFF3EC, dark: 0x1C1412), iconName: "AppIcon-Sunset")

    static let lavender = AppTheme(
        id: "lavender", name: "Lavender",
        brand: Color(hex: 0x8E6CEF), onBrand: .white,
        highlight: Color(hex: 0xFFB3D9), onHighlight: Color(hex: 0x2A1240),
        brandText: Color(light: 0x6A4BC8, dark: 0xB9A2FF),
        board: Color(light: 0x221A3A, dark: 0x18132A), boardText: .white,
        boardMuted: Color(hex: 0xB3A8D1), boardGrid: Color(hex: 0x372C59),
        surface: Color(light: 0xF4F1FD, dark: 0x16131F), iconName: "AppIcon-Lavender")

    static let all: [AppTheme] = [.neon, .ink, .ocean, .forest, .sunset, .lavender]

    static func named(_ id: String) -> AppTheme { all.first { $0.id == id } ?? .neon }

    /// Shared with the widgets.
    static let storageKey = "themeID"
    static var current: AppTheme { named(AppGroup.defaults.string(forKey: storageKey) ?? "neon") }
}

extension EnvironmentValues {
    /// The current colour scheme.
    @Entry var theme: AppTheme = .neon
}
