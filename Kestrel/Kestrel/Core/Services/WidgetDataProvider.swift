//
//  WidgetDataProvider.swift
//  Kestrel
//
//  Shared data layer between the main app and WidgetKit extension.
//  Data is exchanged via the App Group UserDefaults.
//

import Foundation
import WidgetKit

// MARK: - Widget Server Data

/// Lightweight server snapshot shared with widgets via App Group.
struct WidgetServerData: Codable, Identifiable {
    let id: UUID
    let name: String
    let host: String
    let environment: String
    let isOnline: Bool
    let cpuPercent: Double
    let uptime: String
    let lastUpdated: Date
}

// MARK: - Widget Data Provider

enum WidgetDataProvider {

    private static let key = "kestrel.widget.serverData"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: kestrelAppGroup)
    }

    /// Writes current server status data for widget consumption.
    /// Call this whenever server stats are refreshed.
    static func updateWidgetData(_ servers: [WidgetServerData]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        sharedDefaults?.set(data, forKey: key)

        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Reads server data from the shared App Group.
    /// Called by the widget extension.
    static func loadWidgetData() -> [WidgetServerData] {
        guard let data = sharedDefaults?.data(forKey: key),
              let servers = try? JSONDecoder().decode([WidgetServerData].self, from: data) else {
            return []
        }
        return servers
    }

    /// Convenience: build widget data from live state.
    @MainActor
    static func syncFromLiveState(servers: [SSHServer], sessionManager: SSHSessionManager) {
        let data = servers.map { server -> WidgetServerData in
            let session = sessionManager.activeSession(for: server.id)
            return WidgetServerData(
                id: server.id,
                name: server.name,
                host: server.host,
                environment: server.environment.badge,
                isOnline: session?.isConnected == true,
                cpuPercent: 0, // Would come from ServerStatsEngine
                uptime: "",
                lastUpdated: .now
            )
        }
        updateWidgetData(data)
    }
}
