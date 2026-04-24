//
//  HistoryView.swift
//  Kestrel
//
//  Session history list with filtering, detail view, replay, and export.
//

import SwiftUI
import SwiftData

// MARK: - History Filter

enum HistoryFilter: String, CaseIterable {
    case all       = "All"
    case recorded  = "Recorded"
}

// MARK: - History View

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SessionLog.startedAt, order: .reverse) private var sessions: [SessionLog]
    @Query(sort: \SSHServer.orderIndex) private var servers: [SSHServer]

    @State private var filter: HistoryFilter = .all
    @State private var searchText = ""
    @State private var serverFilter: UUID?
    @State private var selectedSession: SessionLog?
    @State private var sessionToDelete: SessionLog?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                ScrollView {
                    LazyVStack(spacing: 8) {
                        if filteredSessions.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredSessions) { session in
                                sessionRow(session)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 40)
                }
            }
            .background(KestrelColors.background)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AuditLogView()
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search sessions...")
            .tint(KestrelColors.phosphorGreen)
            .navigationDestination(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
            .confirmationDialog(
                "Delete Recording",
                isPresented: Binding(
                    get: { sessionToDelete != nil },
                    set: { if !$0 { sessionToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let session = sessionToDelete {
                        withAnimation(.snappy) {
                            modelContext.delete(session)
                            try? modelContext.save()
                        }
                        sessionToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    sessionToDelete = nil
                }
            } message: {
                Text("This will permanently delete this session and its recording.")
            }
        }
    }

    // MARK: - Filtering

    private var filteredSessions: [SessionLog] {
        var result = sessions

        if filter == .recorded {
            result = result.filter { $0.recording != nil }
        }

        if let serverID = serverFilter {
            result = result.filter { $0.serverID == serverID }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.serverName.lowercased().contains(query) }
        }

        return result
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Type filter
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases, id: \.self) { f in
                    Button {
                        withAnimation(.snappy(duration: 0.15)) { filter = f }
                    } label: {
                        Text(f.rawValue)
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(filter == f ? KestrelColors.background : KestrelColors.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(filter == f ? KestrelColors.phosphorGreen : KestrelColors.backgroundCard)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    filter == f ? KestrelColors.phosphorGreen : KestrelColors.cardBorder, lineWidth: 1
                                )
                            )
                    }
                }

                Spacer()

                // Server picker
                Menu {
                    Button("All Servers") { serverFilter = nil }
                    Divider()
                    ForEach(servers) { server in
                        Button {
                            serverFilter = server.id
                        } label: {
                            Label(server.name, systemImage: "server.rack")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 11))
                        Text(serverFilter == nil ? "All" : servers.first { $0.id == serverFilter }?.name ?? "Server")
                            .font(KestrelFonts.mono(10))
                    }
                    .foregroundStyle(KestrelColors.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(KestrelColors.backgroundCard)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle().fill(KestrelColors.cardBorder).frame(height: 1)
        }
    }

    // MARK: - Session Row

    private func sessionRow(_ session: SessionLog) -> some View {
        Button {
            selectedSession = session
        } label: {
            HStack(spacing: 10) {
                // Status icon
                VStack(spacing: 4) {
                    Circle()
                        .fill(session.endedAt != nil ? KestrelColors.textFaint : KestrelColors.phosphorGreen)
                        .frame(width: 8, height: 8)

                    if session.recording != nil {
                        Image(systemName: "record.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(KestrelColors.red)
                    }
                }
                .frame(width: 16)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(session.serverName)
                            .font(KestrelFonts.monoBold(13))
                            .foregroundStyle(KestrelColors.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)
                    }

                    HStack(spacing: 12) {
                        // Duration
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(formatDuration(session))
                                .font(KestrelFonts.mono(10))
                        }
                        .foregroundStyle(KestrelColors.textMuted)

                        // Command count
                        HStack(spacing: 3) {
                            Image(systemName: "terminal")
                                .font(.system(size: 9))
                            Text("\(session.commandCount) cmds")
                                .font(KestrelFonts.mono(10))
                        }
                        .foregroundStyle(KestrelColors.textMuted)

                        Spacer()
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
        }
        .buttonStyle(.plain)
        .contextMenu {
            if session.recording != nil {
                Button {
                    selectedSession = session
                } label: {
                    Label("Replay", systemImage: "play.circle")
                }
            }

            Button(role: .destructive) {
                sessionToDelete = session
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(KestrelColors.textFaint)

            Text("No sessions yet")
                .font(KestrelFonts.display(16, weight: .semibold))
                .foregroundStyle(KestrelColors.textMuted)

            Text("Terminal sessions will appear here")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func formatDuration(_ session: SessionLog) -> String {
        let end = session.endedAt ?? .now
        let seconds = Int(end.timeIntervalSince(session.startedAt))

        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    let session: SessionLog

    @Environment(\.modelContext) private var modelContext
    @Query private var allCommands: [CommandLogEntry]

    @State private var isReplaying = false
    @State private var replayLines: [String] = []
    @State private var showCursor = true
    @State private var replayTask: Task<Void, Never>?
    @State private var cursorTimer: Timer?
    @State private var replayProgress: Double = 0
    @State private var replayLineBuffer: String = ""
    @State private var showingExportSheet = false
    @State private var exportText = ""

    private var sessionCommands: [CommandLogEntry] {
        allCommands
            .filter { $0.sessionID == session.id }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Info card
                infoCard

                // Commands run
                if !sessionCommands.isEmpty {
                    commandsSection
                }

                // Replay
                if session.recording != nil {
                    replaySection
                }

                // Export
                exportSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(KestrelColors.background)
        .navigationTitle(session.serverName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(KestrelColors.background, for: .navigationBar)
        .sheet(isPresented: $showingExportSheet) {
            ShareSheet(items: [exportText])
        }
        .onDisappear {
            stopReplay()
        }
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Session Info")
                Spacer()
                if session.recording != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 10))
                        Text("Recorded")
                            .font(KestrelFonts.mono(10))
                    }
                    .foregroundStyle(KestrelColors.red)
                }
            }

            infoRow(label: "Server", value: session.serverName)
            infoRow(label: "Started", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
            if let ended = session.endedAt {
                infoRow(label: "Ended", value: ended.formatted(date: .abbreviated, time: .standard))
                let seconds = Int(ended.timeIntervalSince(session.startedAt))
                infoRow(label: "Duration", value: formatSeconds(seconds))
            }
            infoRow(label: "Commands", value: "\(session.commandCount)")
            if let recording = session.recording {
                infoRow(label: "Recording", value: formatBytes(UInt64(recording.count)))
            }
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textMuted)
            Spacer()
            Text(value)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textPrimary)
        }
    }

    // MARK: - Commands Section

    private var commandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Commands Run")

            ForEach(sessionCommands, id: \.id) { entry in
                HStack(spacing: 8) {
                    Text("$")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.phosphorGreen)

                    Text(entry.command)
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .lineLimit(2)

                    Spacer()

                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .padding(8)
                .background(KestrelColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Replay Section

    private var replaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Session Replay")
                Spacer()

                if isReplaying {
                    // Progress pill
                    Text("\(Int(replayProgress * 100))%")
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.textFaint)
                        .padding(.trailing, 4)
                }

                Button {
                    if isReplaying {
                        stopReplay()
                    } else {
                        startReplay()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isReplaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 10))
                        Text(isReplaying ? "Stop" : "Replay")
                            .font(KestrelFonts.mono(11))
                    }
                    .foregroundStyle(isReplaying ? KestrelColors.red : KestrelColors.phosphorGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background((isReplaying ? KestrelColors.red : KestrelColors.phosphorGreen).opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            // Terminal window
            VStack(spacing: 0) {
                // Title bar
                HStack(spacing: 6) {
                    Circle().fill(KestrelColors.red.opacity(0.8)).frame(width: 8, height: 8)
                    Circle().fill(KestrelColors.amber.opacity(0.8)).frame(width: 8, height: 8)
                    Circle().fill(KestrelColors.phosphorGreen.opacity(0.8)).frame(width: 8, height: 8)
                    Spacer()
                    Text(session.serverName)
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.textFaint)
                    Spacer()
                    // Balance the dots
                    Color.clear.frame(width: 30, height: 8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(white: 0.12))

                // Terminal content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if replayLines.isEmpty && !isReplaying {
                                Text("Press play to replay the session")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(KestrelColors.textFaint)
                                    .padding(.top, 4)
                            } else {
                                ForEach(Array(replayLines.enumerated()), id: \.offset) { index, line in
                                    terminalLine(line, isLast: index == replayLines.count - 1)
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("replay-anchor")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    .frame(height: 280)
                    .onChange(of: replayLines.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo("replay-anchor", anchor: .bottom)
                        }
                    }
                }
                .background(Color.black)

                // Progress bar
                if isReplaying {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(KestrelColors.phosphorGreen)
                            .frame(width: geo.size.width * replayProgress, height: 2)
                    }
                    .frame(height: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(white: 0.2), lineWidth: 1)
            )
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    /// Renders a single terminal line with optional blinking cursor on the last line.
    private func terminalLine(_ text: String, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.9))

            if isLast && isReplaying {
                Text("▊")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                    .opacity(showCursor ? 1 : 0)
            }
        }
    }

    /// Strips ANSI escape sequences and non-printable control characters from terminal output.
    private func stripANSI(_ string: String) -> String {
        // Match CSI sequences: ESC[ ... final_byte
        // OSC sequences: ESC] ... ST
        // Other ESC sequences
        guard let regex = try? NSRegularExpression(
            pattern: "\\x1B(?:\\[[0-9;?]*[A-Za-z]|\\][^\\x07]*(?:\\x07|\\x1B\\\\)|\\([B0]|[>=])",
            options: []
        ) else { return string }

        let range = NSRange(string.startIndex..., in: string)
        var result = regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: "")

        // Remove remaining control characters (except \n, \r, \t which are handled elsewhere)
        result = result.filter { char in
            let scalar = char.unicodeScalars.first!.value
            return scalar >= 0x20 || scalar == 0x0A || scalar == 0x0D || scalar == 0x09
        }

        return result
    }

    private func startReplay() {
        guard let data = session.recording else { return }
        let (_, events) = SessionRecordingManager.parseRecording(data)
        guard !events.isEmpty else { return }

        isReplaying = true
        replayLines = []
        replayProgress = 0
        replayLineBuffer = ""

        // Blinking cursor timer
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                showCursor.toggle()
            }
        }

        let totalDuration = events.last?.relativeTime ?? 1.0

        replayTask = Task {
            var lastTime: TimeInterval = 0

            for event in events {
                guard !Task.isCancelled else { break }

                let delay = event.relativeTime - lastTime
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(min(delay, 1.5)))
                }
                lastTime = event.relativeTime

                let eventData = event.data
                let eventTime = event.relativeTime

                await MainActor.run { [self] in
                    replayProgress = min(eventTime / totalDuration, 1.0)

                    let cleaned = stripANSI(eventData)
                    let normalized = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")

                    let parts = normalized.components(separatedBy: "\n")

                    for (i, part) in parts.enumerated() {
                        if i == 0 {
                            replayLineBuffer += part
                        } else {
                            replayLines.append(replayLineBuffer)
                            replayLineBuffer = part
                        }
                    }

                    // Always reflect the current buffer as the visible last line
                    if replayLines.isEmpty {
                        if !replayLineBuffer.isEmpty {
                            replayLines.append(replayLineBuffer)
                        }
                    } else if parts.count == 1 {
                        replayLines[replayLines.count - 1] = replayLineBuffer
                    }
                }
            }

            await MainActor.run { [self] in
                if !replayLineBuffer.isEmpty {
                    if let lastIndex = replayLines.indices.last {
                        replayLines[lastIndex] = replayLineBuffer
                    } else {
                        replayLines.append(replayLineBuffer)
                    }
                }
                replayProgress = 1.0
                stopReplay()
            }
        }
    }

    private func stopReplay() {
        replayTask?.cancel()
        replayTask = nil
        cursorTimer?.invalidate()
        cursorTimer = nil
        isReplaying = false
        showCursor = true
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Export")

            HStack(spacing: 8) {
                exportButton(icon: "doc.plaintext", label: "Text") {
                    exportAsText()
                }
                if session.recording != nil {
                    exportButton(icon: "film", label: ".cast") {
                        exportAsCast()
                    }
                }
                exportButton(icon: "doc.richtext", label: "Markdown") {
                    exportAsMarkdown()
                }
            }
        }
    }

    private func exportButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(KestrelFonts.mono(10))
            }
            .foregroundStyle(KestrelColors.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
            )
        }
    }

    private func exportAsText() {
        var text = "Kestrel Session Transcript\n"
        text += "Server: \(session.serverName)\n"
        text += "Date: \(session.startedAt.formatted())\n"
        text += String(repeating: "─", count: 40) + "\n\n"

        if let data = session.recording {
            let (_, events) = SessionRecordingManager.parseRecording(data)
            for event in events {
                text += event.data
            }
        } else {
            text += "(No recording data — transcript only)\n"
            for cmd in sessionCommands {
                text += "$ \(cmd.command)\n"
            }
        }

        exportText = text
        showingExportSheet = true
    }

    private func exportAsCast() {
        guard let data = session.recording,
              let string = String(data: data, encoding: .utf8) else { return }
        exportText = string
        showingExportSheet = true
    }

    private func exportAsMarkdown() {
        var md = "# Session: \(session.serverName)\n\n"
        md += "**Date:** \(session.startedAt.formatted())\n\n"
        md += "## Commands\n\n```bash\n"
        for cmd in sessionCommands {
            md += "$ \(cmd.command)\n"
        }
        md += "```\n"

        exportText = md
        showingExportSheet = true
    }

    // MARK: - Helpers

    private func formatSeconds(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }
}
