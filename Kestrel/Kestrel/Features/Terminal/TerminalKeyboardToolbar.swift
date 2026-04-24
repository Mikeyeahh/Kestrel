//
//  TerminalKeyboardToolbar.swift
//  Kestrel
//
//  Custom keyboard accessory toolbar with terminal-specific keys.
//

import SwiftUI

struct TerminalKeyboardToolbar: View {
    let session: SSHSession?
    let onCtrlToggle: () -> Void
    var onDismissKeyboard: (() -> Void)?

    @State private var isCtrlActive = false
    @State private var isKeyboardVisible = false

    // Key definitions: (label, data to send)
    private let keys: [(String, TerminalKeyAction)] = [
        ("Tab", .escape("\t")),
        ("Esc", .escape("\u{1B}")),
        ("Ctrl", .modifier),
        ("Alt", .escape("\u{1B}")),
        ("↑", .escape("\u{1B}[A")),
        ("↓", .escape("\u{1B}[B")),
        ("→", .escape("\u{1B}[C")),
        ("←", .escape("\u{1B}[D")),
        ("|", .character("|")),
        ("~", .character("~")),
        ("/", .character("/")),
        ("-", .character("-")),
        ("_", .character("_")),
        ("Home", .escape("\u{1B}[H")),
        ("End", .escape("\u{1B}[F")),
        ("PgUp", .escape("\u{1B}[5~")),
        ("PgDn", .escape("\u{1B}[6~")),
    ]

    var body: some View {
        Group {
            if isKeyboardVisible {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Dismiss keyboard button
                        Button {
                            onDismissKeyboard?()
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 13))
                                .foregroundStyle(KestrelColors.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(KestrelColors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                                )
                        }

                        Rectangle()
                            .fill(KestrelColors.cardBorder)
                            .frame(width: 1, height: 20)

                        ForEach(keys, id: \.0) { key in
                            keyButton(label: key.0, action: key.1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .background(Color(uiColor: UIColor.systemBackground).opacity(0.05))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(KestrelColors.cardBorder)
                        .frame(height: 1)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    private func keyButton(label: String, action: TerminalKeyAction) -> some View {
        let isSpecial = label == "Ctrl"
        let isActive = isSpecial && isCtrlActive

        return Button {
            handleKeyPress(label: label, action: action)
        } label: {
            Text(label)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(
                    isActive ? KestrelColors.phosphorGreen :
                    isSpecial ? KestrelColors.amber :
                    KestrelColors.textMuted
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    isActive ? KestrelColors.phosphorGreenDim :
                    KestrelColors.backgroundCard
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isActive ? KestrelColors.cardBorderGreen : KestrelColors.cardBorder,
                            lineWidth: 1
                        )
                )
        }
    }

    private func handleKeyPress(label: String, action: TerminalKeyAction) {
        switch action {
        case .character(let char):
            if isCtrlActive {
                // Send as Ctrl+key
                sendCtrlKey(char)
                isCtrlActive = false
            } else {
                session?.send(char)
            }

        case .escape(let seq):
            session?.send(seq)

        case .modifier:
            isCtrlActive.toggle()
            onCtrlToggle()
        }

        // Haptic
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    private func sendCtrlKey(_ key: String) {
        // Ctrl+key sends the character with value (key - 64) for uppercase letters
        guard let ascii = key.uppercased().first?.asciiValue else { return }
        let ctrlValue = ascii - 64
        if ctrlValue > 0 && ctrlValue < 32 {
            let ctrlChar = String(UnicodeScalar(ctrlValue))
            session?.send(ctrlChar)
        }
    }
}

// MARK: - Key Action Type

enum TerminalKeyAction {
    case character(String)
    case escape(String)
    case modifier
}
