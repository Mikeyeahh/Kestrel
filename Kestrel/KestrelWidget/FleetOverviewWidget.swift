//
//  FleetOverviewWidget.swift
//  KestrelWidget
//
//  Medium widget showing up to 4 servers with status overview.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Fleet Entry

struct FleetOverviewEntry: TimelineEntry {
    let date: Date
    let servers: [WidgetServerData]
}

// MARK: - Fleet Provider

struct FleetOverviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> FleetOverviewEntry {
        FleetOverviewEntry(date: .now, servers: [
            .init(id: UUID(), name: "web-01", host: "10.0.0.1", environment: "PROD", isOnline: true, cpuPercent: 32, uptime: "", lastUpdated: .now),
            .init(id: UUID(), name: "api-01", host: "10.0.0.2", environment: "PROD", isOnline: true, cpuPercent: 58, uptime: "", lastUpdated: .now),
            .init(id: UUID(), name: "db-01", host: "10.0.0.3", environment: "PROD", isOnline: false, cpuPercent: 0, uptime: "", lastUpdated: .now),
            .init(id: UUID(), name: "staging", host: "10.0.1.1", environment: "STAGE", isOnline: true, cpuPercent: 12, uptime: "", lastUpdated: .now),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (FleetOverviewEntry) -> Void) {
        completion(FleetOverviewEntry(date: .now, servers: loadServers()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FleetOverviewEntry>) -> Void) {
        let entry = FleetOverviewEntry(date: .now, servers: loadServers())
        let next = Calendar.current.date(byAdding: .minute, value: 10, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadServers() -> [WidgetServerData] {
        guard let data = UserDefaults(suiteName: "group.suite.osprey-kestrel")?.data(forKey: "kestrel.widget.serverData"),
              let servers = try? JSONDecoder().decode([WidgetServerData].self, from: data) else {
            return []
        }
        return servers
    }
}

// MARK: - Fleet Widget View

struct FleetOverviewWidgetView: View {
    let entry: FleetOverviewEntry

    private var onlineCount: Int { entry.servers.filter(\.isOnline).count }
    private var offlineCount: Int { entry.servers.filter { !$0.isOnline }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text("◈ FLEET")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0, green: 1, blue: 0.255))

                Spacer()

                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Circle().fill(.green).frame(width: 5, height: 5)
                        Text("\(onlineCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    if offlineCount > 0 {
                        HStack(spacing: 3) {
                            Circle().fill(.red).frame(width: 5, height: 5)
                            Text("\(offlineCount)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            // Server rows (up to 4)
            ForEach(Array(entry.servers.prefix(4))) { server in
                Link(destination: URL(string: "kestrel://terminal?serverID=\(server.id.uuidString)")!) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(server.isOnline ? Color.green : Color.red)
                            .frame(width: 5, height: 5)

                        Text(server.name)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Text(server.environment)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.08))
                            .clipShape(Capsule())

                        if server.cpuPercent > 0 {
                            Text("\(Int(server.cpuPercent))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(cpuColor(server.cpuPercent))
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                }
            }

            if entry.servers.isEmpty {
                HStack {
                    Spacer()
                    Text("No servers configured")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding(12)
    }

    private func cpuColor(_ value: Double) -> Color {
        if value > 80 { return .red }
        if value > 50 { return .yellow }
        return .green
    }
}

// MARK: - Widget Definition

struct FleetOverviewWidget: Widget {
    let kind = "FleetOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: FleetOverviewProvider()
        ) { entry in
            FleetOverviewWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Fleet Overview")
        .description("Shows status of up to 4 servers at a glance.")
        .supportedFamilies([.systemMedium])
    }
}
