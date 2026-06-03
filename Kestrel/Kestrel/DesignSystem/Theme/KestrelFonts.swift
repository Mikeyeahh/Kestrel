//
//  KestrelFonts.swift
//  Kestrel
//

import SwiftUI
import UIKit

/// Every UI font in the app routes through here, so the user's chosen
/// `FontManager` typeface applies app-wide. The SSH terminal uses its own
/// font and does NOT go through this. When the chosen font's bundled .ttf
/// isn't installed yet, each helper falls back to the system font.
enum KestrelFonts {
    /// Resolves a Font for the active app font at the given size/weight,
    /// preferring the bundled custom face and falling back to the system font.
    private static func resolved(_ size: CGFloat, weight: Font.Weight) -> Font {
        fontForID(FontManager.shared.currentFontID, size: size, weight: weight)
    }

    /// Builds a Font for a SPECIFIC app font id — used by the Settings picker so
    /// each tile previews in its own typeface regardless of the current choice.
    static func fontForID(_ font: AppFontID, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let base = font.baseFontName {
            let weighted = weightedName(base: base, weight: weight)
            if UIFont(name: weighted, size: size) != nil {
                return .custom(weighted, size: size)
            }
            if UIFont(name: base, size: size) != nil {
                // Have the regular cut but not the weighted one — synthesize.
                return .custom(base, size: size).weight(weight)
            }
        }
        return .system(size: size, weight: weight, design: font.systemDesign)
    }

    /// Maps a SwiftUI weight to the conventional PostScript suffix.
    private static func weightedName(base: String, weight: Font.Weight) -> String {
        let suffix: String
        switch weight {
        case .bold, .heavy, .black: suffix = "-Bold"
        case .semibold, .medium:    suffix = "-Medium"
        default:                    suffix = "-Regular"
        }
        return base.replacingOccurrences(of: "-Regular", with: suffix)
    }

    /// Monospaced/technical text in the original design — now follows the chosen
    /// app font (still the system monospaced design when "System" is selected).
    static func mono(_ size: CGFloat) -> Font { resolved(size, weight: .regular) }

    /// Bold variant of the app font.
    static func monoBold(_ size: CGFloat) -> Font { resolved(size, weight: .bold) }

    /// Display/heading font. Follows the chosen app font so the whole UI matches.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        resolved(size, weight: weight)
    }
}
