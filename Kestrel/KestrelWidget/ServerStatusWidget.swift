//
//  ServerStatusWidget.swift
//  KestrelWidget
//
//  Small widget showing a single server's status.
//  Tap → deep links to kestrel://terminal?serverID=X
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration Intent

struct SelectServerIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Server"
    static var description = IntentDescription("Choose which server to display.")

    @Parameter(title: "Server")
    var serverName: String?
}

// MARK: - Timeline Entry

struct ServerStatusEntry: TimelineEntry {
    let date: Date
    let server: WidgetServerData?
    let configuration: SelectServerIntent
}

// MARK: - Timeline Provider

struct ServerStatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ServerStatusEntry {
        ServerStatusEntry(
            date: .now,
            server: WidgetServerData(
                id: UUID(),
                name: "prod-web-01",
                host: "192.168.1.10",
                environment: "PROD",
                isOnline: true,
                cpuPercent: 42,
                uptime: "14d 3h",
                lastUpdated: .now
            ),
            configuration: SelectServerIntent()
        )
    }

    func snapshot(for configuration: SelectServerIntent, in context: Context) async -> ServerStatusEntry {
        let servers = loadServers()
        let server = matchServer(servers, name: configuration.serverName)
        return ServerStatusEntry(date: .now, server: server ?? servers.first, configuration: configuration)
    }

    func timeline(for configuration: SelectServerIntent, in context: Context) async -> Timeline<ServerStatusEntry> {
        let servers = loadServers()
        let server = matchServer(servers, name: configuration.serverName)
        let entry = ServerStatusEntry(date: .now, server: server ?? servers.first, configuration: configuration)

        // Refresh every 10 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 10, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func loadServers() -> [WidgetServerData] {
        guard let data = UserDefaults(suiteName: "group.suite.osprey-kestrel")?.data(forKey: "kestrel.widget.serverData"),
              let servers = try? JSONDecoder().decode([WidgetServerData].self, from: data) else {
            return []
        }
        return servers
    }

    private func matchServer(_ servers: [WidgetServerData], name: String?) -> WidgetServerData? {
        guard let name else { return nil }
        return servers.first { $0.name == name }
    }
}

// MARK: - Widget View

struct ServerStatusWidgetView: View {
    let entry: ServerStatusEntry

    var body: some View {
        if let server = entry.server {
            VStack(alignment: .leading, spacing: 6) {
                // Status + name
                HStack(spacing: 5) {
                    Circle()
                        .fill(server.isOnline ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(server.name)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                // Environment badge
                Text(server.environment)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.1))
                    .clipShape(Capsule())

                Spacer()

                // CPU
                if server.cpuPercent > 0 {
                    HStack(spacing: 4) {
                        Text("CPU")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("\(Int(server.cpuPercent))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(cpuColor(server.cpuPercent))
                    }
                }

                // Uptime
                if !server.uptime.isEmpty {
                    Text(server.uptime)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(12)
            .widgetURL(URL(string: "kestrel://terminal?serverID=\(server.id.uuidString)"))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.3))
                Text("No Server")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(12)
        }
    }

    private func cpuColor(_ value: Double) -> Color {
        if value > 80 { return .red }
        if value > 50 { return .yellow }
        return .green
    }
}

// MARK: - Widget Definition

struct ServerStatusWidget: Widget {
    let kind = "ServerStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectServerIntent.self,
            provider: ServerStatusProvider()
        ) { entry in
            ServerStatusWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Server Status")
        .description("Shows the status of a single server.")
        .supportedFamilies([.systemSmall])
    }
}
