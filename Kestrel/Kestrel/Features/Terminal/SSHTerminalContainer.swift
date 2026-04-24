//
//  SSHTerminalContainer.swift
//  Kestrel
//
//  UIViewRepresentable wrapper that bridges SwiftTerm's TerminalView into SwiftUI
//  and wires it to our SSHSession for real-time I/O.
//

import SwiftUI
import SwiftData
import SwiftTerm

// MARK: - SSH Terminal Container (SwiftUI → UIKit Bridge)

struct SSHTerminalContainer: View {
    let tab: TerminalTab
    @Binding var showingAIOverlay: Bool
    @Binding var showingSettings: Bool
    @Binding var isRecording: Bool
    var onDisconnect: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var sessionManager = SSHSessionManager.shared
    @State private var recordingManager = SessionRecordingManager.shared
    @State private var prefs = TerminalPreferences.shared
    @State private var revenueCat = KestrelRevenueCatService.shared
    @State private var showingShareSheet = false
    @State private var showingQuickCommands = false
    @State private var showingPaywall = false
    @State private var currentFontSize: CGFloat = TerminalPreferences.shared.fontSize
    @State private var sessionLog: SessionLog?

    // Keyboard dismiss
    @State private var keyboardDismissID = UUID()

    // Pinch-to-zoom
    @State private var pinchScale: CGFloat = 1.0
    @State private var lastPinchFontSize: CGFloat = TerminalPreferences.shared.fontSize

    private var session: SSHSession? {
        sessionManager.activeSession(for: tab.server.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Inline action bar (always visible)
            terminalActionBar

            // Terminal
            TerminalUIViewWrapper(
                tab: tab,
                session: session,
                fontSize: currentFontSize,
                colorScheme: prefs.colorScheme,
                dismissKeyboardID: keyboardDismissID,
                onTranscriptUpdate: { text in
                    tab.transcript.append(text)
                    if recordingManager.isRecording {
                        recordingManager.appendOutput(text)
                    }
                },
                onCommandSent: { command in
                    logCommand(command)
                }
            )
            .gesture(pinchToZoomGesture)

            // Custom keyboard toolbar (only visible when keyboard is up)
            TerminalKeyboardToolbar(
                session: session,
                onCtrlToggle: { /* handled inside toolbar */ },
                onDismissKeyboard: {
                    keyboardDismissID = UUID()
                }
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [tab.transcript])
        }
        .sheet(isPresented: $showingQuickCommands) {
            QuickCommandPickerSheet { command in
                session?.send(command + "\n")
                logCommand(command)
                if recordingManager.isRecording {
                    recordingManager.appendOutput(command + "\n")
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            KestrelPaywallView()
        }
        .onAppear {
            currentFontSize = prefs.fontSize
            connectIfNeeded()
            createSessionLog()
        }
        .onChange(of: prefs.fontSize) { _, newSize in
            currentFontSize = newSize
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                recordingManager.startRecording(sessionID: sessionLog?.id ?? tab.id)
            } else {
                if let data = recordingManager.stopRecording() {
                    sessionLog?.recording = data
                    try? modelContext.save()
                }
            }
        }
        .onDisappear {
            finaliseSessionLog()
        }
    }

    // MARK: - Action Bar

    private var terminalActionBar: some View {
        HStack(spacing: 0) {
            // Server name + status
            HStack(spacing: 6) {
                Circle()
                    .fill(session?.isConnected == true ? KestrelColors.phosphorGreen : KestrelColors.red)
                    .frame(width: 6, height: 6)
                Text(tab.server.name)
                    .font(KestrelFonts.mono(13))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                Button {
                    showingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                        .foregroundStyle(KestrelColors.textMuted)
                        .frame(width: 34, height: 34)
                }

                Button {
                    showingQuickCommands = true
                } label: {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 13))
                        .foregroundStyle(KestrelColors.textMuted)
                        .frame(width: 34, height: 34)
                }

                Button {
                    if revenueCat.canAccess(.sessionRecording) {
                        isRecording.toggle()
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(isRecording ? KestrelColors.red : KestrelColors.textMuted)
                            .frame(width: 34, height: 34)
                        if !revenueCat.isProOrBundle {
                            ProBadge()
                                .scaleEffect(0.7)
                                .offset(x: 4, y: -2)
                        }
                    }
                }

                Button {
                    if revenueCat.canAccess(.aiAssistant) {
                        showingAIOverlay = true
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13))
                            .foregroundStyle(.purple)
                            .frame(width: 34, height: 34)
                        if !revenueCat.isProOrBundle {
                            ProBadge()
                                .scaleEffect(0.7)
                                .offset(x: 4, y: -2)
                        }
                    }
                }

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(KestrelColors.textMuted)
                        .frame(width: 34, height: 34)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(KestrelColors.backgroundCard)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KestrelColors.cardBorder)
                .frame(height: 1)
        }
    }

    // MARK: - Pinch to Zoom

    private var pinchToZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newSize = lastPinchFontSize * value.magnification
                currentFontSize = min(max(newSize, 8), 24)
            }
            .onEnded { value in
                let finalSize = lastPinchFontSize * value.magnification
                currentFontSize = min(max(finalSize, 8), 24).rounded()
                lastPinchFontSize = currentFontSize
                prefs.fontSize = currentFontSize
            }
    }

    private func connectIfNeeded() {
        Task {
            do {
                let activeSession: SSHSession
                if let existing = session, existing.isConnected {
                    activeSession = existing
                } else {
                    activeSession = try await sessionManager.openSession(for: tab.server)
                }
                if !activeSession.isShellActive {
                    try activeSession.startShell()
                }
            } catch {
                tab.reconnectFailed = true
            }
        }
    }

    private func createSessionLog() {
        let log = SessionLog(
            serverID: tab.server.id,
            serverName: tab.server.name
        )
        modelContext.insert(log)
        try? modelContext.save()
        sessionLog = log
    }

    private func logCommand(_ command: String) {
        let entry = CommandLogEntry(
            sessionID: sessionLog?.id ?? tab.id,
            serverID: tab.server.id,
            serverName: tab.server.name,
            command: command
        )
        modelContext.insert(entry)
        sessionLog?.commandCount += 1
        try? modelContext.save()
        Analytics.capture("command_executed")
    }

    private func finaliseSessionLog() {
        // Stop recording if active
        if isRecording {
            if let data = recordingManager.stopRecording() {
                sessionLog?.recording = data
            }
            isRecording = false
        }

        sessionLog?.endedAt = .now
        try? modelContext.save()
    }
}

// MARK: - Terminal UIView Wrapper (UIViewRepresentable)

struct TerminalUIViewWrapper: UIViewRepresentable {
    let tab: TerminalTab
    let session: SSHSession?
    let fontSize: CGFloat
    let colorScheme: TerminalColorScheme
    var dismissKeyboardID: UUID
    let onTranscriptUpdate: (String) -> Void
    var onCommandSent: ((String) -> Void)?

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let terminalView = SwiftTerm.TerminalView(frame: .zero, font: font)

        // Apply color scheme
        let bg = colorScheme.background
        let fg = colorScheme.foreground
        terminalView.nativeBackgroundColor = UIColor(red: bg.0, green: bg.1, blue: bg.2, alpha: 1.0)
        terminalView.nativeForegroundColor = UIColor(red: fg.0, green: fg.1, blue: fg.2, alpha: 0.9)

        // Set delegate
        terminalView.terminalDelegate = context.coordinator

        // Configure terminal colors on the emulator
        let terminal = terminalView.getTerminal()
        terminal.foregroundColor = SwiftTerm.Color(
            red: UInt16(fg.0 * 65535),
            green: UInt16(fg.1 * 65535),
            blue: UInt16(fg.2 * 65535)
        )
        terminal.backgroundColor = SwiftTerm.Color(
            red: UInt16(bg.0 * 65535),
            green: UInt16(bg.1 * 65535),
            blue: UInt16(bg.2 * 65535)
        )

        // Scrollback buffer: 10,000 lines
        terminalView.getTerminal().changeScrollback(10_000)

        // Install Kestrel color palette (ANSI 16 colors)
        installKestrelColors(terminalView)

        // Let user tap the terminal to bring up keyboard (preserves tab bar access)
        let tap = UITapGestureRecognizer(target: terminalView, action: #selector(UIView.becomeFirstResponder))
        terminalView.addGestureRecognizer(tap)

        return terminalView
    }

    func updateUIView(_ terminalView: SwiftTerm.TerminalView, context: Context) {
        // Dismiss keyboard when requested
        if dismissKeyboardID != context.coordinator.lastDismissID {
            context.coordinator.lastDismissID = dismissKeyboardID
            _ = terminalView.resignFirstResponder()
        }

        // Update font size if changed
        if terminalView.font.pointSize != fontSize {
            let newFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            terminalView.font = newFont
        }

        // Update color scheme if changed
        if context.coordinator.currentColorScheme != colorScheme {
            context.coordinator.currentColorScheme = colorScheme
            let bg = colorScheme.background
            let fg = colorScheme.foreground
            terminalView.nativeBackgroundColor = UIColor(red: bg.0, green: bg.1, blue: bg.2, alpha: 1.0)
            terminalView.nativeForegroundColor = UIColor(red: fg.0, green: fg.1, blue: fg.2, alpha: 0.9)
            terminalView.getTerminal().foregroundColor = SwiftTerm.Color(
                red: UInt16(fg.0 * 65535), green: UInt16(fg.1 * 65535), blue: UInt16(fg.2 * 65535)
            )
            terminalView.getTerminal().backgroundColor = SwiftTerm.Color(
                red: UInt16(bg.0 * 65535), green: UInt16(bg.1 * 65535), blue: UInt16(bg.2 * 65535)
            )
            installKestrelColors(terminalView)
            terminalView.setNeedsDisplay()
        }

        // Update session reference in coordinator
        context.coordinator.session = session
        context.coordinator.onTranscriptUpdate = onTranscriptUpdate
        context.coordinator.onCommandSent = onCommandSent

        // Feed data from session output if connected
        if let session, session.isConnected {
            context.coordinator.startOutputObservation(session: session, terminalView: terminalView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, colorScheme: colorScheme, onTranscriptUpdate: onTranscriptUpdate)
    }

    // MARK: - Kestrel Terminal Colors

    private func installKestrelColors(_ terminalView: SwiftTerm.TerminalView) {
        let palette = colorScheme.ansiPalette
        let colors = palette.map { r, g, b in
            SwiftTerm.Color(red: UInt16(r) << 8, green: UInt16(g) << 8, blue: UInt16(b) << 8)
        }
        terminalView.installColors(colors)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, TerminalViewDelegate {
        var session: SSHSession?
        var currentColorScheme: TerminalColorScheme
        var onTranscriptUpdate: (String) -> Void
        var onCommandSent: ((String) -> Void)?
        var lastDismissID = UUID()
        private var observedSessionID: UUID?
        private var lastOutputLength = 0
        private var outputObserverTask: Task<Void, Never>?
        private var inputBuffer = ""
        private var hasScrolledToTop = false

        init(session: SSHSession?, colorScheme: TerminalColorScheme, onTranscriptUpdate: @escaping (String) -> Void) {
            self.session = session
            self.currentColorScheme = colorScheme
            self.onTranscriptUpdate = onTranscriptUpdate
        }

        deinit {
            outputObserverTask?.cancel()
        }

        func startOutputObservation(session: SSHSession, terminalView: SwiftTerm.TerminalView) {
            // Restart observation if session changed (e.g. reconnection)
            if observedSessionID != session.serverID {
                outputObserverTask?.cancel()
                observedSessionID = session.serverID
                lastOutputLength = 0
                hasScrolledToTop = false
            } else if outputObserverTask != nil && !(outputObserverTask?.isCancelled ?? true) {
                return
            }

            outputObserverTask = Task { @MainActor [weak self] in
                var lastLength = 0

                while !Task.isCancelled {
                    let currentOutput = session.output
                    if currentOutput.count > lastLength {
                        let newContent = String(currentOutput.dropFirst(lastLength))
                        lastLength = currentOutput.count

                        // Feed new data to terminal
                        terminalView.feed(text: newContent)
                        self?.onTranscriptUpdate(newContent)

                        // On first output, send 'clear' so prompt redraws at top of visible area
                        if self?.hasScrolledToTop == false {
                            self?.hasScrolledToTop = true
                            // Small delay to let the shell fully initialize
                            try? await Task.sleep(for: .milliseconds(300))
                            session.send("clear\n")
                        }
                    }

                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }

        // MARK: - TerminalViewDelegate

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            Task { @MainActor in
                session?.resizeTerminal(cols: newCols, rows: newRows)
            }
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            let string = String(bytes: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                session?.send(string)
            }

            // Track commands: buffer input, flush on newline
            if string.contains("\r") || string.contains("\n") {
                let command = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !command.isEmpty {
                    onCommandSent?(command)
                }
                inputBuffer = ""
            } else {
                inputBuffer.append(string)
            }
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}

        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }

        func bell(source: SwiftTerm.TerminalView) {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        }

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = string
            }
        }

        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }
}
