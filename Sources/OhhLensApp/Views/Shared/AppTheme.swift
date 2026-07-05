import AppKit
import SwiftUI

enum AppTheme {
    enum Layout {
        static let sidebarWidth: CGFloat = 230
        static let cardCornerRadius: CGFloat = 16
        static let controlCornerRadius: CGFloat = 12
        static let titlebarHeight: CGFloat = 52
        static let contentPadding: CGFloat = 24
    }

    enum ColorToken {
        static let accent = Color(red: 0.859, green: 0.051, blue: 0.063)
        static let accentPressed = Color(red: 0.741, green: 0.047, blue: 0.059)
        static let textPrimary = dynamicColor(
            light: NSColor(calibratedRed: 0.067, green: 0.067, blue: 0.067, alpha: 1),
            dark: NSColor(calibratedWhite: 0.94, alpha: 1)
        )
        static let textMuted = dynamicColor(
            light: NSColor(calibratedRed: 0.420, green: 0.420, blue: 0.420, alpha: 1),
            dark: NSColor(calibratedWhite: 0.66, alpha: 1)
        )
        static let border = dynamicColor(
            light: NSColor.black.withAlphaComponent(0.08),
            dark: NSColor.white.withAlphaComponent(0.10)
        )
        static let borderStrong = dynamicColor(
            light: NSColor.black.withAlphaComponent(0.12),
            dark: NSColor.white.withAlphaComponent(0.16)
        )
        static let sidebarGlass = dynamicColor(
            light: NSColor(calibratedRed: 246 / 255, green: 246 / 255, blue: 246 / 255, alpha: 0.62),
            dark: NSColor(calibratedWhite: 0.14, alpha: 0.72)
        )
        static let cardGlass = dynamicColor(
            light: NSColor.white.withAlphaComponent(0.96),
            dark: NSColor.white.withAlphaComponent(0.08)
        )
        static let controlFill = dynamicColor(
            light: NSColor.white.withAlphaComponent(0.72),
            dark: NSColor.white.withAlphaComponent(0.12)
        )
        static let hoverFill = dynamicColor(
            light: NSColor.black.withAlphaComponent(0.045),
            dark: NSColor.white.withAlphaComponent(0.06)
        )
        static let canvasTop = dynamicColor(
            light: NSColor(calibratedRed: 0.972, green: 0.969, blue: 0.965, alpha: 1),
            dark: NSColor(calibratedWhite: 0.08, alpha: 1)
        )
        static let canvasBottom = dynamicColor(
            light: NSColor(calibratedRed: 0.933, green: 0.937, blue: 0.949, alpha: 1),
            dark: NSColor(calibratedWhite: 0.04, alpha: 1)
        )
        static let contentBackground = dynamicColor(
            light: .white,
            dark: .black
        )
    }

    static let subtleShadow = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.black.withAlphaComponent(0.32)
    )
    static let canvasBackground = LinearGradient(
        colors: [
            ColorToken.canvasTop,
            ColorToken.canvasBottom
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func accentColor(for theme: AccentTheme) -> Color {
        switch theme {
        case .blue:
            Color(red: 0.000, green: 0.478, blue: 1.000)
        case .purple:
            Color(red: 0.608, green: 0.318, blue: 0.878)
        case .pink:
            Color(red: 1.000, green: 0.176, blue: 0.333)
        case .red:
            ColorToken.accent
        case .orange:
            Color(red: 1.000, green: 0.584, blue: 0.000)
        case .green:
            Color(red: 0.204, green: 0.780, blue: 0.349)
        case .graphite:
            Color(red: 0.557, green: 0.557, blue: 0.576)
        }
    }

    static func accentPressedColor(for theme: AccentTheme) -> Color {
        switch theme {
        case .blue:
            Color(red: 0.000, green: 0.376, blue: 0.820)
        case .purple:
            Color(red: 0.482, green: 0.251, blue: 0.690)
        case .pink:
            Color(red: 0.839, green: 0.129, blue: 0.286)
        case .red:
            ColorToken.accentPressed
        case .orange:
            Color(red: 0.851, green: 0.463, blue: 0.000)
        case .green:
            Color(red: 0.149, green: 0.635, blue: 0.282)
        case .graphite:
            Color(red: 0.431, green: 0.431, blue: 0.451)
        }
    }

    static func avatarGradient(for theme: AccentTheme) -> LinearGradient {
        LinearGradient(
            colors: [
                accentColor(for: theme),
                accentColor(for: theme).opacity(0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
                case .darkAqua:
                    dark
                default:
                    light
                }
            }
        )
    }

}
