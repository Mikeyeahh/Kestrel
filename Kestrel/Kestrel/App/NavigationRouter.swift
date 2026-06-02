//
//  NavigationRouter.swift
//  Kestrel
//
//  Centralised navigation state for deep link routing and tab selection.
//

import SwiftUI

// MARK: - Tab Identifiers

enum KestrelTab: Int, Hashable {
    case servers   = 0
    case terminal  = 1
    case files     = 2
    case commands  = 3
    case settings  = 4
}

// MARK: - Navigation Router

@Observable
@MainActor
final class NavigationRouter {
    static let shared = NavigationRouter()

    private static let selectedTabKey = "nav.selectedTab"

    /// Persisted so a cold relaunch reopens the tab the user left on.
    var selectedTab: KestrelTab = .servers {
        didSet { UserDefaults.standard.set(selectedTab.rawValue, forKey: Self.selectedTabKey) }
    }

    // Servers tab
    var selectedServerID: UUID?
    var showingAddServer = false

    // Terminal tab
    var terminalServerID: UUID?

    // SFTP tab
    var sftpServerID: UUID?

    // Shared connection — set when a server connects from ServersView
    var pendingTerminalServer: SSHServer?
    var pendingSFTPServer: SSHServer?
    var pendingAIOverlay = false

    // Import from Osprey
    var pendingImportHost: String?

    // Settings sub-navigation
    var showingHistory = false
    var showingKeyManager = false
    var showingPaywall = false

    private init() {
        // Restore the last-used tab. (Property observers don't fire during
        // init, so this read-back doesn't re-persist.)
        if let raw = UserDefaults.standard.object(forKey: Self.selectedTabKey) as? Int,
           let tab = KestrelTab(rawValue: raw) {
            selectedTab = tab
        }
    }

    /// Called when a server is connected from the Servers tab.
    /// Signals terminal and SFTP to auto-connect.
    func serverDidConnect(_ server: SSHServer) {
        pendingTerminalServer = server
        pendingSFTPServer = server
    }

    /// Routes a deep link action to the appropriate tab and state.
    func handle(_ action: KestrelDeepLinkAction) {
        switch action {
        case .connect:
            selectedTab = .servers
            showingAddServer = true

        case .importHost(let host):
            pendingImportHost = host
            selectedTab = .servers

        case .terminal(let serverID):
            terminalServerID = serverID
            selectedTab = .terminal

        case .files(let serverID, _):
            // Files tab — will be wired when SFTP is built
            _ = serverID
            selectedTab = .files
        }
    }
}
