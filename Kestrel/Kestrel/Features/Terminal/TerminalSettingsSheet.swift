//
//  TerminalSettingsSheet.swift
//  Kestrel
//

import SwiftUI

// MARK: - Terminal Preferences

@Observable
final class TerminalPreferences {
    static let shared = TerminalPreferences()

    var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(fontSize), forKey: "terminal_font_size") }
    }
    var fontName: String {
        didSet { UserDefaults.standard.set(fontName, forKey: "terminal_font_name") }
    }
    var colorScheme: TerminalColorScheme {
        didSet { UserDefaults.standard.set(colorScheme.rawValue, forKey: "terminal_color_scheme") }
    }

    private init() {
        let storedSize = UserDefaults.standard.double(forKey: "terminal_font_size")
        self.fontSize = storedSize > 0 ? CGFloat(storedSize) : 12

        self.fontName = UserDefaults.standard.string(forKey: "terminal_font_name") ?? "SF Mono"

        let storedScheme = UserDefaults.standard.string(forKey: "terminal_color_scheme") ?? ""
        self.colorScheme = TerminalColorScheme(rawValue: storedScheme) ?? .kestrel
    }
}

enum TerminalColorScheme: String, CaseIterable {
    case kestrel = "Kestrel"
    case classic = "Classic Green"
    case amber = "Amber"
    case solarized = "Solarized Dark"
    case dracula = "Dracula"

    var foreground: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .kestrel: (0, 1, 0.255)
        case .classic: (0, 1, 0)
        case .amber: (1, 0.722, 0)
        case .solarized: (0.514, 0.580, 0.588)
        case .dracula: (0.973, 0.973, 0.949)
        }
    }

    var background: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .kestrel: (0, 0, 0)
        case .classic: (0, 0, 0)
        case .amber: (0.05, 0.03, 0)
        case .solarized: (0, 0.169, 0.212)
        case .dracula: (0.157, 0.165, 0.212)
        }
    }

    /// ANSI 16-color palette (normal 0-7, bright 8-15) tuned per theme
    var ansiPalette: [(UInt8, UInt8, UInt8)] {
        switch self {
        case .kestrel:
            [
                (0x1A, 0x1A, 0x1A), (0xFF, 0x3B, 0x5C), (0x00, 0xFF, 0x41), (0xFF, 0xB8, 0x00),
                (0x00, 0xC8, 0xFF), (0xCC, 0x66, 0xFF), (0x00, 0xE5, 0xCC), (0xCC, 0xCC, 0xCC),
                (0x55, 0x55, 0x55), (0xFF, 0x6B, 0x82), (0x66, 0xFF, 0x7F), (0xFF, 0xD7, 0x4D),
                (0x4D, 0xDA, 0xFF), (0xDD, 0x99, 0xFF), (0x4D, 0xF0, 0xDD), (0xFF, 0xFF, 0xFF),
            ]
        case .classic:
            [
                (0x00, 0x00, 0x00), (0xCC, 0x00, 0x00), (0x00, 0xCC, 0x00), (0xCC, 0xCC, 0x00),
                (0x00, 0x00, 0xCC), (0xCC, 0x00, 0xCC), (0x00, 0xCC, 0xCC), (0xCC, 0xCC, 0xCC),
                (0x55, 0x55, 0x55), (0xFF, 0x55, 0x55), (0x55, 0xFF, 0x55), (0xFF, 0xFF, 0x55),
                (0x55, 0x55, 0xFF), (0xFF, 0x55, 0xFF), (0x55, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF),
            ]
        case .amber:
            [
                (0x1A, 0x10, 0x00), (0xCC, 0x44, 0x00), (0xFF, 0xB8, 0x00), (0xFF, 0xDD, 0x55),
                (0xCC, 0x88, 0x00), (0xFF, 0x88, 0x44), (0xFF, 0xCC, 0x66), (0xCC, 0xAA, 0x66),
                (0x66, 0x44, 0x00), (0xFF, 0x66, 0x22), (0xFF, 0xCC, 0x33), (0xFF, 0xEE, 0x88),
                (0xFF, 0xAA, 0x33), (0xFF, 0xAA, 0x77), (0xFF, 0xDD, 0x99), (0xFF, 0xEE, 0xCC),
            ]
        case .solarized:
            [
                (0x07, 0x36, 0x42), (0xDC, 0x32, 0x2F), (0x85, 0x99, 0x00), (0xB5, 0x89, 0x00),
                (0x26, 0x8B, 0xD2), (0xD3, 0x36, 0x82), (0x2A, 0xA1, 0x98), (0xEE, 0xE8, 0xD5),
                (0x00, 0x2B, 0x36), (0xCB, 0x4B, 0x16), (0x58, 0x6E, 0x75), (0x65, 0x7B, 0x83),
                (0x83, 0x94, 0x96), (0x6C, 0x71, 0xC4), (0x93, 0xA1, 0xA1), (0xFD, 0xF6, 0xE3),
            ]
        case .dracula:
            [
                (0x28, 0x2A, 0x36), (0xFF, 0x55, 0x55), (0x50, 0xFA, 0x7B), (0xF1, 0xFA, 0x8C),
                (0xBD, 0x93, 0xF9), (0xFF, 0x79, 0xC6), (0x8B, 0xE9, 0xFD), (0xF8, 0xF8, 0xF2),
                (0x62, 0x72, 0xA4), (0xFF, 0x6E, 0x6E), (0x69, 0xFF, 0x94), (0xFF, 0xFB, 0xA6),
                (0xD6, 0xAC, 0xFF), (0xFF, 0x92, 0xDF), (0xA4, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF),
            ]
        }
    }
}

// MARK: - Settings Sheet

struct TerminalSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var prefs = TerminalPreferences.shared

    @State private var apiKey: String = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    fontSection
                    colorSection
                    aiSection
                }
                .padding(16)
            }
            .background(KestrelColors.background)
            .navigationTitle("Terminal Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(KestrelColors.background)
    }

    // MARK: - Font Section

    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Font")

            // Font size
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Size")
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.textPrimary)
                    Spacer()
                    Text("\(Int(prefs.fontSize)) pt")
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }

                HStack(spacing: 12) {
                    Button {
                        if prefs.fontSize > 8 {
                            prefs.fontSize -= 1
                        }
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.textMuted)
                            .frame(width: 36, height: 36)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Slider(
                        value: $prefs.fontSize,
                        in: 8...24,
                        step: 1
                    )
                    .tint(KestrelColors.phosphorGreen)

                    Button {
                        if prefs.fontSize < 24 {
                            prefs.fontSize += 1
                        }
                    } label: {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.textMuted)
                            .frame(width: 36, height: 36)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(12)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
            )

            // Font preview — reflects the active color scheme
            let previewFg = prefs.colorScheme.foreground
            let previewBg = prefs.colorScheme.background
            Text("user@server:~$ ls -la /var/log")
                .font(.system(size: prefs.fontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(red: previewFg.0, green: previewFg.1, blue: previewFg.2))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: previewBg.0, green: previewBg.1, blue: previewBg.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                )
        }
    }

    // MARK: - Color Section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Colour Scheme")

            ForEach(TerminalColorScheme.allCases, id: \.self) { scheme in
                colorSchemeRow(scheme)
            }
        }
    }

    // MARK: - AI Section

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "AI Assistant")

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textPrimary)

                SecureField("sk-ant-...", text: $apiKey)
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(KestrelColors.backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                    )
                    .tint(KestrelColors.phosphorGreen)
                    .onChange(of: apiKey) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "claude_api_key")
                    }

                Text("Required for AI terminal analysis. Key is stored locally on device.")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .padding(12)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
            )
        }
    }

    private func colorSchemeRow(_ scheme: TerminalColorScheme) -> some View {
        let isSelected = prefs.colorScheme == scheme
        let bg = scheme.background
        let fg = scheme.foreground

        return Button {
            prefs.colorScheme = scheme
        } label: {
            HStack(spacing: 12) {
                // Preview swatch
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: bg.0, green: bg.1, blue: bg.2))
                    .frame(width: 44, height: 30)
                    .overlay {
                        Text("$_")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(Color(red: fg.0, green: fg.1, blue: fg.2))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                    )

                Text(scheme.rawValue)
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
            }
            .padding(10)
            .background(isSelected ? KestrelColors.phosphorGreenDim : KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? KestrelColors.cardBorderGreen : KestrelColors.cardBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Server Picker Sheet

struct ServerPickerSheet: View {
    let servers: [SSHServer]
    let onSelect: (SSHServer) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    if servers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 32))
                                .foregroundStyle(KestrelColors.textFaint)
                            Text("No servers configured")
                                .font(KestrelFonts.mono(13))
                                .foregroundStyle(KestrelColors.textMuted)
                            Text("Add a server from the Servers tab first")
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(KestrelColors.textFaint)
                        }
                        .padding(.vertical, 40)
                    } else {
                        ForEach(servers) { server in
                            Button {
                                onSelect(server)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(server.environment.colour)
                                        .frame(width: 8, height: 8)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(KestrelFonts.monoBold(13))
                                            .foregroundStyle(KestrelColors.textPrimary)
                                        ServerConnectionLabel(
                                            username: server.username,
                                            host: server.host
                                        )
                                    }

                                    Spacer()

                                    EnvBadge(env: server.environment)

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11))
                                        .foregroundStyle(KestrelColors.textFaint)
                                }
                                .padding(12)
                                .background(KestrelColors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(KestrelColors.background)
            .navigationTitle("Select Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(KestrelColors.textMuted)
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KestrelColors.background)
    }
}
