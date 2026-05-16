//
//  KestrelFonts.swift
//  Kestrel
//

import SwiftUI
import UIKit

enum KestrelFonts {
    /// Monospaced font for technical text. Uses the active theme's
    /// `monoFontName` when it's set and the font is installed; otherwise
    /// falls back to the system monospaced design.
    static func mono(_ size: CGFloat) -> Font {
        if let name = ThemeManager.shared.current.monoFontName,
           UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, design: .monospaced)
    }

    /// Bold variant of the monospaced font.
    static func monoBold(_ size: CGFloat) -> Font {
        if let baseName = ThemeManager.shared.current.monoFontName {
            let boldName = baseName.replacingOccurrences(of: "-Regular", with: "-Bold")
            if UIFont(name: boldName, size: size) != nil {
                return .custom(boldName, size: size)
            }
            if UIFont(name: baseName, size: size) != nil {
                return .custom(baseName, size: size).weight(.semibold)
            }
        }
        return .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// Display font using system rounded design.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
