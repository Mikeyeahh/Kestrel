//
//  AuditLogView.swift
//  Kestrel
//
//  Chronological audit log of all commands run across all servers,
//  with search, filter, and CSV export.
//

import SwiftUI
import SwiftData

struct AuditLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CommandLogEntry.timestamp, order: .reverse) private var entries: [CommandLogEntry]
    @Query(sort: \SSHServer.orderIndex) private var servers: [SSHServer]

    @State private var searchText = ""
    @State private var serverFilter: UUID?
    @State private var showingExport = false

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            ScrollView {
                LazyVStack(spacing: 0) {
                    if filteredEntries.isEmpty {
                        emptyState
                    } else {
                        // Group by date
                        ForEach(groupedByDate, id: \.date) { group in
                            dateSection(group)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .background(KestrelColors.background)
        .navigationTitle("Audit Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(KestrelColors.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingExport = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                .disabled(filteredEntries.isEmpty)
            }
        }
        .searchable(text: $searchText, prompt: "Search commands...")
        .tint(KestrelColors.phosphorGreen)
        .sheet(isPresented: $showingExport) {
            ShareSheet(items: [exportCSV()])
        }
    }

    // MARK: - Filtering

    private var filteredEntries: [CommandLogEntry] {
        var result = entries

        if let serverID = serverFilter {
            result = result.filter { $0.serverID == serverID }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.command.lowercased().contains(query) ||
                $0.serverName.lowercased().contains(query)
            }
        }

        return result
    }

    // MARK: - Grouped by Date

    private struct DateGroup {
        let date: String
        let entries: [CommandLogEntry]
    }

    private var groupedByDate: [DateGroup] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let grouped = Dictionary(grouping: filteredEntries) { entry in
            formatter.string(from: entry.timestamp)
        }

        return grouped.map { DateGroup(date: $0.key, entries: $0.value) }
            .sorted { ($0.entries.first?.timestamp ?? .distantPast) > ($1.entries.first?.timestamp ?? .distantPast) }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Server filter
                Menu {
                    Button("All Servers") { serverFilter = nil }
                    Divider()
                    ForEach(servers) { server in
                        Button(server.name) { serverFilter = server.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 10))
                        Text(serverFilter == nil ? "All Servers" : servers.first { $0.id == serverFilter }?.name ?? "Server")
                            .font(KestrelFonts.mono(10))
                    }
                    .foregroundStyle(KestrelColors.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(KestrelColors.backgroundCard)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                    )
                }

                Spacer()

                Text("\(filteredEntries.count) commands")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle().fill(KestrelColors.cardBorder).frame(height: 1)
        }
    }

    // MARK: - Date Section

    private func dateSection(_ group: DateGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.date)
                .font(KestrelFonts.mono(10))
                .foregroundStyle(KestrelColors.textFaint)
                .padding(.top, 14)
                .padding(.bottom, 4)

            ForEach(group.entries, id: \.id) { entry in
                commandRow(entry)
            }
        }
    }

    private func commandRow(_ entry: CommandLogEntry) -> some View {
        HStack(spacing: 8) {
            // Time
            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
                .frame(width: 44, alignment: .leading)

            // Server
            Text(entry.serverName)
                .font(KestrelFonts.mono(10))
                .foregroundStyle(KestrelColors.textMuted)
                .lineLimit(1)
                .frame(width: 70, alignment: .leading)

            // Command
            HStack(spacing: 4) {
                Text("$")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                Text(entry.command)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.command
            } label: {
                Label("Copy Command", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                modelContext.delete(entry)
                try? modelContext.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 36))
                .foregroundStyle(KestrelColors.textFaint)

            Text("No commands logged")
                .font(KestrelFonts.display(16, weight: .semibold))
                .foregroundStyle(KestrelColors.textMuted)

            Text("Commands run in terminal sessions will appear here")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - CSV Export

    private func exportCSV() -> String {
        var csv = "Date,Time,Server,Command\n"

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"

        for entry in filteredEntries {
            let date = dateFmt.string(from: entry.timestamp)
            let time = timeFmt.string(from: entry.timestamp)
            // Escape quotes in CSV
            let cmd = entry.command.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(date),\(time),\(entry.serverName),\"\(cmd)\"\n"
        }

        return csv
    }
}
