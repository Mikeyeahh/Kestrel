//
//  AppFont.swift
//  Kestrel
//
//  User-selectable UI typeface for the WHOLE app (everything except the SSH
//  terminal, which keeps its own font). The raw values match the font ids used
//  by Kestrel on Windows/macOS so the choice syncs across platforms via the
//  `user_settings.ui_font` column.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Font Identifier

enum AppFontID: String, CaseIterable, Identifiable {
    case jetbrainsMono = "jetbrains-mono"
    case ibmPlexMono   = "ibm-plex-mono"
    case spaceMono     = "space-mono"
    case inter         = "inter"
    case outfit        = "outfit"
    case system        = "system"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jetbrainsMono: "JetBrains Mono"
        case .ibmPlexMono:   "IBM Plex Mono"
        case .spaceMono:     "Space Mono"
        case .inter:         "Inter"
        case .outfit:        "Outfit"
        case .system:        "System"
        }
    }

    var isMono: Bool {
        switch self {
        case .jetbrainsMono, .ibmPlexMono, .spaceMono: true
        case .inter, .outfit, .system: false
        }
    }

    /// Bundled font family base name (the "-Regular" PostScript stem). `nil`
    /// uses the system font. Bold/Medium are derived by swapping the suffix.
    /// NOTE: the matching .ttf files must be added to Resources/Fonts and listed
    /// in Info.plist (UIAppFonts); until then this falls back to the system font.
    var baseFontName: String? {
        switch self {
        case .jetbrainsMono: "JetBrainsMono-Regular"
        case .ibmPlexMono:   "IBMPlexMono-Regular"
        case .spaceMono:     "SpaceMono-Regular"
        case .inter:         "Inter18pt-Regular"
        case .outfit:        "Outfit-Regular"
        case .system:        nil
        }
    }

    /// System fallback design — monospaced for the mono options — used when the
    /// bundled font isn't installed yet.
    var systemDesign: Font.Design { isMono ? .monospaced : .default }
}

// MARK: - Font Manager

/// Singleton that persists and provides the active UI font. Mirrors
/// `ThemeManager`. `KestrelFonts` reads `current` to build every UI font.
final class FontManager {
    static let shared = FontManager()

    var currentFontID: AppFontID {
        didSet {
            UserDefaults.standard.set(currentFontID.rawValue, forKey: "app.font")
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "app.font") ?? ""
        self.currentFontID = AppFontID(rawValue: stored) ?? .jetbrainsMono
    }
}
