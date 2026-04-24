//
//  MultiServerView.swift
//  Kestrel
//
//  Multi-server command execution: select servers, run commands concurrently,
//  broadcast mode, preset actions, and export results.
//

import SwiftUI
import SwiftData

// MARK: - Execution Result

@Observable
@MainActor
class ServerExecResult: Identifiable {
    let id = UUID()
    let server: SSHServer
    var status: ExecStatus = .pending
    var output: String = ""
    var startedAt: Date?
    var completedAt: Date?

    init(server: SSHServer) {
        self.server = server
    }

    var duration: TimeInterval? {
        guard let start = startedAt, let end = completedAt else { return nil }
        return end.timeIntervalSince(start)
    }
}

enum ExecStatus: String {
    case pending = "Pending"
    case running = "Running"
    case success = "Success"
    case failed = "Failed"
    case connectionError = "Connection Error"

    var color: Color {
        switch self {
        case .pending:         Color.gray
        case .running:         KestrelColors.blue
        case .success:         KestrelColors.phosphorGreen
        case .failed:          KestrelColors.red
        case .connectionError: KestrelColors.amber
        }
    }

    var icon: String {
        switch self {
        case .pending:         "clock"
        case .running:         "arrow.triangle.2.circlepath"
        case .success:         "checkmark.circle.fill"
        case .failed:          "xmark.circle.fill"
        case .connectionError: "wifi.slash"
        }
    }
}

// MARK: - Preset Action

struct PresetAction: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let command: String
}

private let presetActions: [PresetAction] = [
    .init(name: "Uptime", icon: "clock", command: "uptime"),
    .init(name: "Disk", icon: "internaldrive", command: "df -h"),
    .init(name: "Memory", icon: "memorychip", command: "free -h"),
    .init(name: "Failed Svcs", icon: "exclamationmark.triangle", command: "systemctl --failed --no-pager"),
    .init(name: "Web Status", icon: "globe", command: "systemctl is-active nginx apache2 httpd 2>/dev/null || echo 'no web server'"),
]

// MARK: - Multi-Server View

struct MultiServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SSHServer.orderIndex) private var servers: [SSHServer]

    let preselectedServerIDs: Set<UUID>

    init(preselectedServerIDs: Set<UUID> = []) {
        self.preselectedServerIDs = preselectedServerIDs
    }

    @State private var sessionManager = SSHSessionManager.shared
    @State private var selectedServerIDs: Set<UUID> = []
    @State private var command = ""
    @State private var results: [ServerExecResult] = []
    @State private var isExecuting = false
    @State private var envFilter: ServerEnvironment?

    // Broadcast
    @State private var isBroadcastMode = false
    @State private var broadcastInput = ""

    // Sheets
    @State private var showingCommandPicker = false
    @State private var showingExport = false
    @State private var expandedResultID: UUID?

    private var selectedServers: [SSHServer] {
        servers.filter { selectedServerIDs.contains($0.id) }
    }

    private var filteredServers: [SSHServer] {
        guard let env = envFilter else { return servers }
        return servers.filter { $0.environment == env }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Server selector
                serverSelector

                // Command input OR broadcast
                if isBroadcastMode {
                    broadcastSection
                } else {
                    commandSection
                }

                // Preset actions
                if !isBroadcastMode && results.isEmpty {
                    presetsSection
                }

                // Results
                if !results.isEmpty {
                    resultsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .proGated(feature: .multiServer)
        .background(KestrelColors.background)
        .navigationTitle("Multi-Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(KestrelColors.background, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !results.isEmpty {
                    Button {
                        showingExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                }

                Toggle(isOn: $isBroadcastMode) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14))
                }
                .toggleStyle(.button)
                .tint(isBroadcastMode ? KestrelColors.red : KestrelColors.textMuted)
            }
        }
        .onAppear {
            if selectedServerIDs.isEmpty && !preselectedServerIDs.isEmpty {
                selectedServerIDs = preselectedServerIDs
            }
        }
        .sheet(isPresented: $showingCommandPicker) {
            CommandPickerSheet { picked in
                command = picked
            }
        }
        .sheet(isPresented: $showingExport) {
            ShareSheet(items: [exportReport()])
        }
    }

    // MARK: - Server Selector

    private var serverSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Servers")
                Spacer()

                Button {
                    if selectedServerIDs.count == filteredServers.count {
                        selectedServerIDs.removeAll()
                    } else {
                        selectedServerIDs = Set(filteredServers.map(\.id))
                    }
                } label: {
                    Text(selectedServerIDs.count == filteredServers.count ? "Deselect All" : "Select All")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
            }

            // Environment filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    envPill(label: "All", env: nil)
                    ForEach(ServerEnvironment.allCases, id: \.self) { env in
                        envPill(label: env.badge, env: env)
                    }
                }
            }

            // Server checklist
            VStack(spacing: 4) {
                ForEach(filteredServers) { server in
                    serverCheckRow(server)
                }
            }

            if !selectedServerIDs.isEmpty {
                Text("\(selectedServerIDs.count) server\(selectedServerIDs.count == 1 ? "" : "s") selected")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }
        }
    }

    private func envPill(label: String, env: ServerEnvironment?) -> some View {
        let isSelected = envFilter == env

        return Button {
            withAnimation(.snappy(duration: 0.15)) {
                envFilter = env
            }
        } label: {
            Text(label)
                .font(KestrelFonts.mono(10))
                .foregroundStyle(isSelected ? KestrelColors.background : KestrelColors.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? KestrelColors.phosphorGreen : KestrelColors.backgroundCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? KestrelColors.phosphorGreen : KestrelColors.cardBorder,
                            lineWidth: 1
                        )
                )
        }
    }

    private func serverCheckRow(_ server: SSHServer) -> some View {
        let isSelected = selectedServerIDs.contains(server.id)
        let session = sessionManager.activeSession(for: server.id)
        let isOnline = session?.isConnected == true

        return Button {
            if isSelected {
                selectedServerIDs.remove(server.id)
            } else {
                selectedServerIDs.insert(server.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? KestrelColors.phosphorGreen : KestrelColors.textFaint)

                Circle()
                    .fill(server.environment.colour)
                    .frame(width: 6, height: 6)

                Text(server.name)
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                if isOnline {
                    Text("connected")
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }

                EnvBadge(env: server.environment)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? KestrelColors.phosphorGreenDim.opacity(0.5) : KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? KestrelColors.cardBorderGreen : KestrelColors.cardBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Command Section

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Command")
                Spacer()
                Button {
                    showingCommandPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "book")
                            .font(.system(size: 10))
                        Text("Library")
                            .font(KestrelFonts.mono(10))
                    }
                    .foregroundStyle(KestrelColors.textMuted)
                }
            }

            TextField("Enter command...", text: $command, axis: .vertical)
                .font(KestrelFonts.mono(14))
                .foregroundStyle(KestrelColors.phosphorGreen)
                .lineLimit(2...5)
                .padding(12)
                .background(KestrelColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .tint(KestrelColors.phosphorGreen)

            // Run button
            Button {
                Task { await executeOnAll() }
            } label: {
                HStack(spacing: 8) {
                    if isExecuting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(KestrelColors.background)
                    }
                    Image(systemName: "play.fill")
                    Text(isExecuting
                         ? "Running…"
                         : "Run on \(selectedServerIDs.count) Server\(selectedServerIDs.count == 1 ? "" : "s")")
                }
                .font(KestrelFonts.monoBold(13))
                .foregroundStyle(canExecute ? KestrelColors.background : KestrelColors.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canExecute ? KestrelColors.phosphorGreen : KestrelColors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!canExecute)
        }
    }

    private var canExecute: Bool {
        !command.trimmingCharacters(in: .whitespaces).isEmpty &&
        !selectedServerIDs.isEmpty &&
        !isExecuting
    }

    // MARK: - Broadcast Section

    private var broadcastSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Pulsing red indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(KestrelColors.red)
                    .frame(width: 8, height: 8)
                    .modifier(PulsingModifier())

                Text("BROADCAST MODE")
                    .font(KestrelFonts.mono(11))
                    .fontWeight(.bold)
                    .tracking(1.5)
                    .foregroundStyle(KestrelColors.red)

                Spacer()

                Text("\(activeBroadcastSessions.count) sessions")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .padding(10)
            .background(KestrelColors.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                TextField("Type to broadcast...", text: $broadcastInput)
                    .font(KestrelFonts.mono(14))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(KestrelColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(KestrelColors.red.opacity(0.3), lineWidth: 1)
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .tint(KestrelColors.red)
                    .onSubmit {
                        sendBroadcast()
                    }

                Button {
                    sendBroadcast()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(broadcastInput.isEmpty ? KestrelColors.textFaint : KestrelColors.red)
                        .frame(width: 40, height: 40)
                        .background(KestrelColors.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(broadcastInput.isEmpty)
            }

            if activeBroadcastSessions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text("No active sessions for selected servers. Connect first.")
                        .font(KestrelFonts.mono(10))
                }
                .foregroundStyle(KestrelColors.amber)
            }
        }
    }

    private var activeBroadcastSessions: [(server: SSHServer, session: SSHSession)] {
        selectedServers.compactMap { server in
            guard let session = sessionManager.activeSession(for: server.id),
                  session.isConnected else { return nil }
            return (server, session)
        }
    }

    private func sendBroadcast() {
        guard !broadcastInput.isEmpty else { return }
        let text = broadcastInput + "\n"

        for item in activeBroadcastSessions {
            item.session.send(text)
        }

        broadcastInput = ""

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Quick Actions")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presetActions) { preset in
                        Button {
                            command = preset.command
                            Task { await executeOnAll() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: preset.icon)
                                    .font(.system(size: 10))
                                Text(preset.name)
                                    .font(KestrelFonts.mono(11))
                            }
                            .foregroundStyle(KestrelColors.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                            )
                        }
                        .disabled(selectedServerIDs.isEmpty || isExecuting)
                    }
                }
            }
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Results")
                Spacer()

                let successCount = results.filter { $0.status == .success }.count
                let failCount = results.filter { $0.status == .failed || $0.status == .connectionError }.count

                if successCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("\(successCount)")
                            .font(KestrelFonts.mono(10))
                    }
                    .foregroundStyle(KestrelColors.phosphorGreen)
                }

                if failCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                        Text("\(failCount)")
                            .font(KestrelFonts.mono(10))
                    }
                    .foregroundStyle(KestrelColors.red)
                }

                Button {
                    results.removeAll()
                } label: {
                    Text("Clear")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textFaint)
                }
            }

            ForEach(results) { result in
                resultCard(result)
            }
        }
    }

    private func resultCard(_ result: ServerExecResult) -> some View {
        let isExpanded = expandedResultID == result.id

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    expandedResultID = isExpanded ? nil : result.id
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: result.status.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(result.status.color)

                    Circle()
                        .fill(result.server.environment.colour)
                        .frame(width: 6, height: 6)

                    Text(result.server.name)
                        .font(KestrelFonts.monoBold(12))
                        .foregroundStyle(KestrelColors.textPrimary)

                    Spacer()

                    // Status badge
                    Text(result.status.rawValue)
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(result.status.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(result.status.color.opacity(0.12))
                        .clipShape(Capsule())

                    if let dur = result.duration {
                        Text(String(format: "%.1fs", dur))
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textFaint)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Output (expanded)
            if isExpanded && !result.output.isEmpty {
                ScrollView {
                    Text(result.output)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            // Loading spinner
            if result.status == .running {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(KestrelColors.blue)
                    Text("Executing…")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    result.status == .failed || result.status == .connectionError
                        ? result.status.color.opacity(0.3)
                        : KestrelColors.cardBorder,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Execution

    private func executeOnAll() async {
        guard canExecute else { return }

        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)
        isExecuting = true
        results = selectedServers.map { ServerExecResult(server: $0) }
        expandedResultID = nil

        await withTaskGroup(of: (UUID, String, Bool).self) { group in
            for result in results {
                result.status = .running
                result.startedAt = .now

                group.addTask {
                    do {
                        let session = try await self.sessionManager.openSession(for: result.server)
                        let output = try await session.execute(trimmedCommand)
                        return (result.id, output, true)
                    } catch {
                        return (result.id, error.localizedDescription, false)
                    }
                }
            }

            for await (id, output, success) in group {
                if let result = results.first(where: { $0.id == id }) {
                    result.output = output
                    result.completedAt = .now
                    result.status = success ? .success : (output.contains("Connection") ? .connectionError : .failed)
                }
            }
        }

        isExecuting = false

        // Auto-expand first failed result
        if let firstFailed = results.first(where: { $0.status != .success }) {
            expandedResultID = firstFailed.id
        } else {
            expandedResultID = results.first?.id
        }
    }

    // MARK: - Export

    private func exportReport() -> String {
        let dateStr = Date.now.formatted(date: .abbreviated, time: .shortened)
        var report = """
        Kestrel Multi-Server Report — \(dateStr)
        Command: \(command)
        Servers: \(results.count)

        """

        for result in results {
            let statusSymbol = result.status == .success ? "✓" : "✗"
            report += """

            [\(result.server.name)] \(statusSymbol) \(result.status.rawValue)
            \(result.output.isEmpty ? "(no output)" : result.output)

            """
        }

        return report
    }
}

// MARK: - Pulsing Modifier

struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Command Picker Sheet

struct CommandPickerSheet: View {
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedCommand.useCount, order: .reverse) private var commands: [SavedCommand]

    @State private var searchText = ""

    private var filtered: [SavedCommand] {
        if searchText.isEmpty { return Array(commands.prefix(50)) }
        let query = searchText.lowercased()
        return commands.filter {
            $0.name.lowercased().contains(query) ||
            $0.command.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filtered) { cmd in
                        Button {
                            onSelect(cmd.command)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cmd.name)
                                    .font(KestrelFonts.monoBold(12))
                                    .foregroundStyle(KestrelColors.textPrimary)
                                Text(cmd.command)
                                    .font(KestrelFonts.mono(10))
                                    .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.6))
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(KestrelColors.background)
            .navigationTitle("Pick Command")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search commands...")
            .tint(KestrelColors.phosphorGreen)
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
