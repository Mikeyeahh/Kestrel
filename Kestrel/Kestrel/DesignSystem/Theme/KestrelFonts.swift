//
//  KestrelFonts.swift
//  Kestrel
//

import SwiftUI
import UIKit

enum KestrelFonts {
    /// Monospaced font for technical text.
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }

    /// Bold variant of the monospaced font.
    static func monoBold(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// Display font using system rounded design.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
