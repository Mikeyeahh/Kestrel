//
//  KestrelColors.swift
//  Kestrel
//
//  Theme-aware color palette. All properties delegate to the active AppTheme
//  so existing call sites work without changes.
//

import SwiftUI

enum KestrelColors {
    private static var theme: AppTheme { ThemeManager.shared.current }

    // MARK: - Backgrounds

    static var background: Color { theme.background }
    static var backgroundCard: Color { theme.backgroundCard }
    static var backgroundCardGreen: Color { theme.backgroundCardAccent }

    // MARK: - Borders

    static var cardBorder: Color { theme.cardBorder }
    static var cardBorderGreen: Color { theme.cardBorderAccent }

    // MARK: - Accents

    static var phosphorGreen: Color { theme.accent }
    static var phosphorGreenDim: Color { theme.accentDim }
    static var amber: Color { theme.amber }
    static var red: Color { theme.red }
    static var blue: Color { theme.blue }

    // MARK: - Text

    static var textPrimary: Color { theme.textPrimary }
    static var textMuted: Color { theme.textMuted }
    static var textFaint: Color { theme.textFaint }
}

// MARK: - Hex Color

extension Color {
    /// Initialise a Color from a `#RRGGBB` or `#RRGGBBAA` hex string.
    /// Returns nil for malformed input (e.g. legacy `var(--…)` values).
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8,
              let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        } else {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
