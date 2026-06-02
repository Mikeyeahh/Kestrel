//
//  TerminalView.swift
//  Kestrel
//

import SwiftUI
import SwiftData

// MARK: - Terminal View (Root)

struct TerminalView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SSHServer.orderIndex) private var servers: [SSHServer]

    @State private var sessionManager = SSHSessionManager.shared
    @State private var router = NavigationRouter.shared
    @State private var tabs: [TerminalTab] = []
    @State private var activeTabID: UUID?
    @State private var showingServerPicker = false
    @State private var showingAIOverlay = false
    @State private var showingSettings = false
    @State private var isRecording = false

    // Close confirmation
    @State private var tabToClose: TerminalTab?
    @State private var showingCloseConfirmation = false

    // Swipe gesture
    @State private var dragOffset: CGFloat = 0

    // Restore the last terminal session once per launch (auto-reconnect).
    @State private var didAttemptRestore = false
    private static let lastServerKey = "terminal.lastServerID"

    private var activeTab: TerminalTab? {
        tabs.first { $0.id == activeTabID }
    }

    private var activeTabIndex: Int? {
        tabs.firstIndex { $0.id == activeTabID }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Session tabs
            tabBar

            // Terminal content
            ZStack {
                if let tab = activeTab {
                    SSHTerminalContainer(
                        tab: tab,
                        showingAIOverlay: $showingAIOverlay,
                        showingSettings: $showingSettings,
                        isRecording: $isRecording,
                        onDisconnect: {
                            tabToClose = tab
                            showingCloseConfirmation = true
                        }
                    )
                    .id(tab.id)
                    .offset(x: dragOffset)
                    .gesture(swipeBetweenTabsGesture)
                } else {
                    emptyTerminalState
                }

                // Reconnecting overlay
                if let tab = activeTab, tab.isReconnecting {
                    reconnectingOverlay(tab: tab)
                }
            }
        }
        .background(KestrelColors.background)
        .sheet(isPresented: $showingServerPicker) {
            ServerPickerSheet(servers: servers) { server in
                openTab(for: server)
            }
        }
        .sheet(isPresented: $showingAIOverlay) {
            if let tab = activeTab {
                AIOverlaySheet(tab: tab)
            }
        }
        .sheet(isPresented: $showingSettings) {
            TerminalSettingsSheet()
        }
        .confirmationDialog(
            "Close Session",
            isPresented: $showingCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close", role: .destructive) {
                if let tab = tabToClose {
                    closeTab(tab)
                }
                tabToClose = nil
            }
            Button("Cancel", role: .cancel) {
                tabToClose = nil
            }
        } message: {
            if let tab = tabToClose {
                Text("Disconnect from \(tab.server.name)?")
            }
        }
        .onAppear {
            consumePendingTerminal()
            restoreLastTerminalIfNeeded()
        }
        .onChange(of: router.pendingTerminalServer?.id) { _, _ in consumePendingTerminal() }
        .onChange(of: router.pendingAIOverlay) { _, pending in
            if pending {
                router.pendingAIOverlay = false
                // Small delay to allow the terminal tab to appear first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingAIOverlay = true
                }
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs) { tab in
                        tabButton(tab)
                            .id(tab.id)
                    }

                    // Add tab button
                    Button {
                        showingServerPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(KestrelColors.textMuted)
                            .frame(width: 34, height: 34)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color.black)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(KestrelColors.cardBorder)
                    .frame(height: 1)
            }
            .onChange(of: activeTabID) { _, newID in
                if let newID {
                    withAnimation(.snappy(duration: 0.2)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
                persistLastTerminal()
            }
        }
    }

    private func tabButton(_ tab: TerminalTab) -> some View {
        let isActive = tab.id == activeTabID

        return HStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    activeTabID = tab.id
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tab.server.environment.colour)
                        .frame(width: 6, height: 6)

                    Text(tab.server.name)
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(isActive ? KestrelColors.textPrimary : KestrelColors.textMuted)
                        .lineLimit(1)
                }
            }

            // Close button
            Button {
                tabToClose = tab
                showingCloseConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isActive ? KestrelColors.textMuted : KestrelColors.textFaint)
                    .frame(width: 18, height: 18)
                    .background(
                        isActive ? KestrelColors.textFaint.opacity(0.3) : Color.clear
                    )
                    .clipShape(Circle())
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(isActive ? KestrelColors.backgroundCard : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .bottom) {
            if isActive {
                Capsule()
                    .fill(KestrelColors.phosphorGreen)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
                    .offset(y: 1)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                tabToClose = tab
                showingCloseConfirmation = true
            } label: {
                Label("Close Session", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Swipe Between Tabs

    private var swipeBetweenTabsGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onChanged { value in
                // Only respond to predominantly horizontal swipes
                if abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                    dragOffset = value.translation.width * 0.3
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 80
                withAnimation(.snappy(duration: 0.2)) {
                    dragOffset = 0

                    guard let currentIndex = activeTabIndex else { return }

                    if value.translation.width < -threshold {
                        // Swipe left → next tab
                        let nextIndex = min(currentIndex + 1, tabs.count - 1)
                        activeTabID = tabs[nextIndex].id
                    } else if value.translation.width > threshold {
                        // Swipe right → previous tab
                        let prevIndex = max(currentIndex - 1, 0)
                        activeTabID = tabs[prevIndex].id
                    }
                }
            }
    }

    // MARK: - Empty State

    private var emptyTerminalState: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(KestrelColors.textFaint)

            Text("No active sessions")
                .font(KestrelFonts.display(18, weight: .semibold))
                .foregroundStyle(KestrelColors.textMuted)

            Text("Open a terminal session to a server")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textFaint)

            Button {
                showingServerPicker = true
            } label: {
                Label("New Session", systemImage: "plus")
                    .font(KestrelFonts.mono(13))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(KestrelColors.phosphorGreenDim)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Reconnecting Overlay

    private func reconnectingOverlay(tab: TerminalTab) -> some View {
        VStack(spacing: 12) {
            if tab.reconnectFailed {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(KestrelColors.red)

                Text("Connection Lost")
                    .font(KestrelFonts.monoBold(14))
                    .foregroundStyle(KestrelColors.textPrimary)

                Text("Failed after \(tab.maxReconnectAttempts) attempts")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textMuted)

                Button {
                    reconnectTab(tab)
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(KestrelColors.phosphorGreenDim)
                        .clipShape(Capsule())
                }
            } else {
                ProgressView()
                    .tint(KestrelColors.phosphorGreen)

                Text("Reconnecting… (attempt \(tab.reconnectAttempts)/\(tab.maxReconnectAttempts))")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textMuted)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Actions

    private func consumePendingTerminal() {
        guard let server = router.pendingTerminalServer else { return }
        if !tabs.contains(where: { $0.server.id == server.id }) {
            openTab(for: server)
        } else if let existing = tabs.first(where: { $0.server.id == server.id }) {
            activeTabID = existing.id
        }
        router.pendingTerminalServer = nil
    }

    private func openTab(for server: SSHServer) {
        let tab = TerminalTab(server: server)
        tabs.append(tab)
        activeTabID = tab.id
    }

    /// Remember the active terminal's server so we can reopen it on the next
    /// launch; clear it once no tabs remain.
    private func persistLastTerminal() {
        if let server = activeTab?.server {
            UserDefaults.standard.set(server.id.uuidString, forKey: Self.lastServerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.lastServerKey)
        }
    }

    /// On the first appearance after a cold launch, reopen the last terminal
    /// server (which reconnects via `SSHTerminalContainer`) so a relaunch
    /// feels continuous. Runs at most once and only when no tabs are open.
    private func restoreLastTerminalIfNeeded() {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        guard tabs.isEmpty,
              let idString = UserDefaults.standard.string(forKey: Self.lastServerKey),
              let id = UUID(uuidString: idString),
              let server = servers.first(where: { $0.id == id }) else { return }
        openTab(for: server)
    }

    private func closeTab(_ tab: TerminalTab) {
        // Disconnect the session
        sessionManager.closeSession(serverID: tab.server.id)

        withAnimation(.snappy) {
            tabs.removeAll { $0.id == tab.id }
            if activeTabID == tab.id {
                activeTabID = tabs.last?.id
            }
        }
    }

    private func reconnectTab(_ tab: TerminalTab) {
        tab.isReconnecting = true
        tab.reconnectFailed = false
        tab.reconnectAttempts = 0

        Task {
            await autoReconnect(tab: tab)
        }
    }

    /// Auto-reconnect with exponential backoff: 1s, 2s, 4s (up to 3 attempts)
    private func autoReconnect(tab: TerminalTab) async {
        for attempt in 1...tab.maxReconnectAttempts {
            guard tab.isReconnecting, !tab.reconnectFailed else { break }

            tab.reconnectAttempts = attempt

            do {
                let session = try await sessionManager.openSession(for: tab.server)
                try session.startShell()
                tab.isReconnecting = false
                tab.reconnectFailed = false
                return
            } catch {
                // Exponential backoff: 1s, 2s, 4s
                let delay = pow(2.0, Double(attempt - 1))
                try? await Task.sleep(for: .seconds(delay))
            }
        }

        // All attempts exhausted
        tab.reconnectFailed = true
        tab.isReconnecting = false
    }
}

// MARK: - Terminal Tab Model

@Observable
class TerminalTab: Identifiable {
    let id = UUID()
    let server: SSHServer
    var transcript: String = ""
    var isReconnecting = false
    var reconnectFailed = false
    var reconnectAttempts = 0
    let maxReconnectAttempts = 3

    init(server: SSHServer) {
        self.server = server
    }
}
