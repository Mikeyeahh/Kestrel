//
//  ServicesView.swift
//  Kestrel
//
//  Service monitor: lists systemd services, allows start/stop/restart,
//  shows journalctl logs, and manages watched-service alerts.
//

import SwiftUI
import SwiftData

// MARK: - Service Info Model

struct ServiceInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let loadState: String      // loaded / not-found / masked
    let activeState: String    // active / inactive / failed / activating
    let subState: String       // running / dead / failed / exited
    let description: String

    var isRunning: Bool { subState == "running" }
    var isFailed: Bool { activeState == "failed" }
    var isInactive: Bool { activeState == "inactive" }

    var statusColor: Color {
        if isFailed { return KestrelColors.red }
        if isRunning { return KestrelColors.phosphorGreen }
        return Color.gray
    }
}

// MARK: - Filter

enum ServiceFilter: String, CaseIterable {
    case all = "All"
    case running = "Running"
    case failed = "Failed"
    case inactive = "Inactive"
}

// MARK: - Services View

struct ServicesView: View {
    let server: SSHServer
    let session: SSHSession

    @Environment(\.modelContext) private var modelContext

    @State private var services: [ServiceInfo] = []
    @State private var filter: ServiceFilter = .all
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var loadError: String?

    // Action states
    @State private var actionInProgress: String?
    @State private var actionResult: (service: String, message: String, isError: Bool)?

    // Log sheet
    @State private var logService: ServiceInfo?
    @State private var showingLogSheet = false

    // Confirmation
    @State private var confirmAction: ServiceAction?
    @State private var showingConfirmation = false

    // Watch management
    @State private var showingWatchManager = false

    // Process monitor
    @State private var showingProcessMonitor = false

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            // Content
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Action result banner
                    actionBanner

                    if isLoading {
                        loadingState
                    } else if let error = loadError {
                        errorState(error)
                    } else if filteredServices.isEmpty {
                        emptyState
                    } else {
                        // Count header
                        HStack {
                            Text("\(filteredServices.count) services")
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(KestrelColors.textFaint)
                            Spacer()
                        }
                        .padding(.top, 4)

                        ForEach(filteredServices) { service in
                            serviceCard(service)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 40)
            }
        }
        .proGated(feature: .serviceMonitor)
        .background(KestrelColors.background)
        .navigationTitle("Services")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(KestrelColors.background, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingProcessMonitor = true
                } label: {
                    Image(systemName: "cpu")
                        .font(.system(size: 14))
                        .foregroundStyle(KestrelColors.textMuted)
                }

                Button {
                    showingWatchManager = true
                } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 14))
                        .foregroundStyle(KestrelColors.textMuted)
                }

                Button {
                    Task { await loadServices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(KestrelColors.textMuted)
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Filter services..."
        )
        .tint(KestrelColors.phosphorGreen)
        .task { await loadServices() }
        .sheet(isPresented: $showingLogSheet) {
            if let service = logService {
                ServiceLogSheet(service: service, session: session)
            }
        }
        .sheet(isPresented: $showingWatchManager) {
            WatchManagerSheet(
                server: server,
                services: services
            )
        }
        .sheet(isPresented: $showingProcessMonitor) {
            ProcessMonitorView(session: session)
        }
        .confirmationDialog(
            confirmAction?.confirmTitle ?? "Confirm",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            if let action = confirmAction {
                Button(action.buttonLabel, role: action.isDestructive ? .destructive : nil) {
                    Task { await executeAction(action) }
                }
                Button("Cancel", role: .cancel) {
                    confirmAction = nil
                }
            }
        } message: {
            if let action = confirmAction {
                Text(action.confirmMessage)
            }
        }
    }

    // MARK: - Filtering

    private var filteredServices: [ServiceInfo] {
        var result = services

        switch filter {
        case .all: break
        case .running: result = result.filter(\.isRunning)
        case .failed: result = result.filter(\.isFailed)
        case .inactive: result = result.filter(\.isInactive)
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.description.lowercased().contains(query)
            }
        }

        return result
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(ServiceFilter.allCases, id: \.self) { f in
                Button {
                    withAnimation(.snappy(duration: 0.15)) {
                        filter = f
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            if f == .failed {
                                let count = services.filter(\.isFailed).count
                                if count > 0 {
                                    Text("\(count)")
                                        .font(KestrelFonts.mono(9))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(KestrelColors.red)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(f.rawValue)
                                .font(KestrelFonts.mono(12))
                        }
                        .foregroundStyle(filter == f ? KestrelColors.textPrimary : KestrelColors.textMuted)

                        Rectangle()
                            .fill(filter == f ? KestrelColors.phosphorGreen : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KestrelColors.cardBorder)
                .frame(height: 1)
        }
    }

    // MARK: - Service Card

    private func serviceCard(_ service: ServiceInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button {
                // Expand to show actions inline
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        // Status dot
                        Circle()
                            .fill(service.statusColor)
                            .frame(width: 8, height: 8)

                        Text(service.name)
                            .font(KestrelFonts.monoBold(13))
                            .foregroundStyle(KestrelColors.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        // Sub-state label
                        Text(service.subState)
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(service.statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(service.statusColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if !service.description.isEmpty {
                        Text(service.description)
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textFaint)
                            .lineLimit(1)
                    }

                    // Action buttons row
                    serviceActions(service)
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            // Loading indicator for this service
            if actionInProgress == service.name {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(KestrelColors.phosphorGreen)
                    Text("Processing…")
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
                    service.isFailed ? KestrelColors.red.opacity(0.3) : KestrelColors.cardBorder,
                    lineWidth: 1
                )
        )
        .contextMenu {
            serviceContextMenu(service)
        }
    }

    // MARK: - Service Actions

    private func serviceActions(_ service: ServiceInfo) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if service.isRunning {
                    actionPill("Stop", icon: "stop.fill", color: KestrelColors.red) {
                        confirmAction = .stop(service.name)
                        showingConfirmation = true
                    }
                    actionPill("Restart", icon: "arrow.clockwise", color: KestrelColors.amber) {
                        confirmAction = .restart(service.name)
                        showingConfirmation = true
                    }
                } else {
                    actionPill("Start", icon: "play.fill", color: KestrelColors.phosphorGreen) {
                        Task { await executeAction(.start(service.name)) }
                    }
                }

                if service.loadState == "loaded" {
                    actionPill("Enable", icon: "checkmark.circle", color: KestrelColors.blue) {
                        Task { await executeAction(.enable(service.name)) }
                    }
                    actionPill("Disable", icon: "minus.circle", color: KestrelColors.textMuted) {
                        Task { await executeAction(.disable(service.name)) }
                    }
                }

                actionPill("Logs", icon: "doc.text", color: .purple) {
                    logService = service
                    showingLogSheet = true
                }
            }
        }
    }

    private func actionPill(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(KestrelFonts.mono(10))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(actionInProgress != nil)
    }

    @ViewBuilder
    private func serviceContextMenu(_ service: ServiceInfo) -> some View {
        if service.isRunning {
            Button {
                confirmAction = .stop(service.name)
                showingConfirmation = true
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            Button {
                confirmAction = .restart(service.name)
                showingConfirmation = true
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
        } else {
            Button {
                Task { await executeAction(.start(service.name)) }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
        }

        Divider()

        Button {
            Task { await executeAction(.enable(service.name)) }
        } label: {
            Label("Enable", systemImage: "checkmark.circle")
        }
        Button {
            Task { await executeAction(.disable(service.name)) }
        } label: {
            Label("Disable", systemImage: "minus.circle")
        }

        Divider()

        Button {
            logService = service
            showingLogSheet = true
        } label: {
            Label("View Logs", systemImage: "doc.text")
        }

        Button {
            addToWatchList(service)
        } label: {
            Label("Watch Service", systemImage: "bell")
        }
    }

    // MARK: - Action Banner

    @ViewBuilder
    private var actionBanner: some View {
        if let result = actionResult {
            HStack(spacing: 8) {
                Image(systemName: result.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.service)
                        .font(KestrelFonts.monoBold(11))
                    Text(result.message)
                        .font(KestrelFonts.mono(10))
                }
                Spacer()
                Button {
                    actionResult = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(KestrelColors.textMuted)
                }
            }
            .foregroundStyle(result.isError ? KestrelColors.red : KestrelColors.phosphorGreen)
            .padding(10)
            .background((result.isError ? KestrelColors.red : KestrelColors.phosphorGreen).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(KestrelColors.phosphorGreen)
            Text("Loading services…")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(KestrelColors.red)

            Text("Failed to load services")
                .font(KestrelFonts.display(16, weight: .semibold))
                .foregroundStyle(KestrelColors.textMuted)

            Text(error)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textFaint)
                .multilineTextAlignment(.center)

            Button {
                Task { await loadServices() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(KestrelColors.phosphorGreenDim)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 32))
                .foregroundStyle(KestrelColors.textFaint)
            Text("No \(filter == .all ? "" : filter.rawValue.lowercased() + " ")services found")
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Data Loading

    private func loadServices() async {
        isLoading = true
        loadError = nil

        do {
            let output = try await session.execute(
                "systemctl list-units --type=service --all --no-pager --plain"
            )
            services = parseSystemctlOutput(output)
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    private func parseSystemctlOutput(_ output: String) -> [ServiceInfo] {
        // Format:
        // UNIT                    LOAD      ACTIVE   SUB     DESCRIPTION
        // sshd.service            loaded    active   running OpenBSD Secure Shell server
        var results: [ServiceInfo] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 4 else { continue }

            let unit = parts[0]
            guard unit.hasSuffix(".service") else { continue }

            let name = String(unit.dropLast(8)) // remove .service
            let loadState = parts[1]
            let activeState = parts[2]
            let subState = parts[3]
            let description = parts.count > 4
                ? parts[4...].joined(separator: " ")
                : ""

            results.append(ServiceInfo(
                name: name,
                loadState: loadState,
                activeState: activeState,
                subState: subState,
                description: description
            ))
        }

        // Sort: failed first, then running, then inactive
        return results.sorted { a, b in
            let order: (ServiceInfo) -> Int = {
                if $0.isFailed { return 0 }
                if $0.isRunning { return 1 }
                return 2
            }
            return order(a) < order(b)
        }
    }

    // MARK: - Service Actions

    private func executeAction(_ action: ServiceAction) async {
        actionInProgress = action.serviceName
        actionResult = nil

        do {
            let output = try await session.execute(action.command)
            actionResult = (
                service: action.serviceName,
                message: output.isEmpty ? action.successMessage : output,
                isError: false
            )
            // Reload services list after action
            await loadServices()
        } catch {
            actionResult = (
                service: action.serviceName,
                message: error.localizedDescription,
                isError: true
            )
        }

        actionInProgress = nil
        confirmAction = nil
    }

    private func addToWatchList(_ service: ServiceInfo) {
        let watched = WatchedService(
            serverID: server.id,
            serverName: server.name,
            serviceName: service.name
        )
        modelContext.insert(watched)
        try? modelContext.save()

        Analytics.capture("service_monitor_added")

        actionResult = (
            service: service.name,
            message: "Added to watch list",
            isError: false
        )
    }
}

// MARK: - Service Action

enum ServiceAction {
    case start(String)
    case stop(String)
    case restart(String)
    case enable(String)
    case disable(String)

    var serviceName: String {
        switch self {
        case .start(let n), .stop(let n), .restart(let n),
             .enable(let n), .disable(let n):
            return n
        }
    }

    var command: String {
        switch self {
        case .start(let n):    "sudo systemctl start \(n)"
        case .stop(let n):     "sudo systemctl stop \(n)"
        case .restart(let n):  "sudo systemctl restart \(n)"
        case .enable(let n):   "sudo systemctl enable \(n)"
        case .disable(let n):  "sudo systemctl disable \(n)"
        }
    }

    var confirmTitle: String {
        switch self {
        case .stop(let n):    "Stop \(n)?"
        case .restart(let n): "Restart \(n)?"
        default:              "Confirm"
        }
    }

    var confirmMessage: String {
        switch self {
        case .stop:    "This will stop the service. It may affect availability."
        case .restart: "This will restart the service. There may be brief downtime."
        default:       ""
        }
    }

    var buttonLabel: String {
        switch self {
        case .stop:    "Stop"
        case .restart: "Restart"
        default:       "Confirm"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .stop: true
        default:    false
        }
    }

    var successMessage: String {
        switch self {
        case .start:   "Service started"
        case .stop:    "Service stopped"
        case .restart: "Service restarted"
        case .enable:  "Service enabled"
        case .disable: "Service disabled"
        }
    }
}

// MARK: - Service Log Sheet

struct ServiceLogSheet: View {
    let service: ServiceInfo
    let session: SSHSession

    @Environment(\.dismiss) private var dismiss

    @State private var logText = ""
    @State private var isLoading = true
    @State private var isFollowing = false
    @State private var followTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Controls
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(service.statusColor)
                            .frame(width: 6, height: 6)
                        Text(service.name)
                            .font(KestrelFonts.monoBold(12))
                            .foregroundStyle(KestrelColors.textPrimary)
                    }

                    Spacer()

                    Toggle(isOn: $isFollowing) {
                        Text("Follow live")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                    .toggleStyle(.switch)
                    .tint(KestrelColors.phosphorGreen)
                    .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(KestrelColors.cardBorder)
                        .frame(height: 1)
                }

                // Log content
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(logText.isEmpty ? (isLoading ? "Loading logs…" : "No log output") : logText)
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(
                                logText.isEmpty
                                    ? KestrelColors.textFaint
                                    : KestrelColors.phosphorGreen.opacity(0.8)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .textSelection(.enabled)
                            .id("log-bottom")
                    }
                    .onChange(of: logText) { _, _ in
                        if isFollowing {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("log-bottom", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .background(KestrelColors.background)
            .navigationTitle("Service Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        followTask?.cancel()
                        dismiss()
                    }
                    .foregroundStyle(KestrelColors.textMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadLogs() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KestrelColors.background)
        .task { await loadLogs() }
        .onChange(of: isFollowing) { _, following in
            if following {
                startFollowing()
            } else {
                followTask?.cancel()
                followTask = nil
            }
        }
        .onDisappear {
            followTask?.cancel()
        }
    }

    private func loadLogs() async {
        isLoading = true
        do {
            let output = try await session.execute(
                "journalctl -u \(service.name) -n 100 --no-pager 2>/dev/null || " +
                "tail -100 /var/log/syslog 2>/dev/null | grep -i \(service.name) || " +
                "echo 'No logs available for \(service.name)'"
            )
            logText = output
        } catch {
            logText = "Error loading logs: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func startFollowing() {
        followTask?.cancel()
        followTask = Task {
            // Poll for new log lines every 2 seconds since we can't stream
            // via execute() (it waits for completion)
            var lastLineCount = logText.components(separatedBy: "\n").count

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }

                do {
                    let output = try await session.execute(
                        "journalctl -u \(service.name) -n 100 --no-pager 2>/dev/null || echo ''"
                    )
                    let newLineCount = output.components(separatedBy: "\n").count
                    if newLineCount != lastLineCount {
                        await MainActor.run {
                            logText = output
                        }
                        lastLineCount = newLineCount
                    }
                } catch {
                    break
                }
            }
        }
    }
}

// MARK: - Watch Manager Sheet

struct WatchManagerSheet: View {
    let server: SSHServer
    let services: [ServiceInfo]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allWatched: [WatchedService]

    private var watchedForServer: [WatchedService] {
        allWatched.filter { $0.serverID == server.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Info
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.amber)
                        Text("Get notified when watched services fail")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KestrelColors.amber.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Currently watched
                    if !watchedForServer.isEmpty {
                        SectionLabel(text: "Watched Services")

                        ForEach(watchedForServer) { watched in
                            HStack(spacing: 10) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(KestrelColors.amber)

                                Text(watched.serviceName)
                                    .font(KestrelFonts.mono(13))
                                    .foregroundStyle(KestrelColors.textPrimary)

                                Spacer()

                                if let state = watched.lastKnownState {
                                    Text(state)
                                        .font(KestrelFonts.mono(10))
                                        .foregroundStyle(KestrelColors.textFaint)
                                }

                                Button {
                                    modelContext.delete(watched)
                                    try? modelContext.save()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(KestrelColors.textFaint)
                                }
                            }
                            .padding(10)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                            )
                        }
                    }

                    // Available to add
                    let unwatched = services.filter { svc in
                        !watchedForServer.contains { $0.serviceName == svc.name }
                    }.filter(\.isRunning)

                    if !unwatched.isEmpty {
                        SectionLabel(text: "Running Services")

                        ForEach(unwatched) { service in
                            Button {
                                let watched = WatchedService(
                                    serverID: server.id,
                                    serverName: server.name,
                                    serviceName: service.name,
                                    lastKnownState: service.subState
                                )
                                modelContext.insert(watched)
                                try? modelContext.save()
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(KestrelColors.phosphorGreen)
                                        .frame(width: 6, height: 6)

                                    Text(service.name)
                                        .font(KestrelFonts.mono(12))
                                        .foregroundStyle(KestrelColors.textPrimary)

                                    Spacer()

                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(KestrelColors.textFaint)
                                }
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
                }
                .padding(16)
            }
            .background(KestrelColors.background)
            .navigationTitle("Service Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KestrelColors.background)
    }
}
