//
//  ServersView.swift
//  Kestrel
//

import SwiftUI
import SwiftData

struct ServersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SSHServer.orderIndex) private var servers: [SSHServer]
    @Query(sort: \ServerGroup.orderIndex) private var groups: [ServerGroup]

    @State private var sessionManager = SSHSessionManager.shared
    @State private var showingAddSheet = false
    @State private var serverToEdit: SSHServer?
    @State private var selectedServerID: UUID?
    @State private var showingDetail = false
    @State private var expandedGroups: Set<String> = []
    @State private var connectingServerID: UUID?
    @State private var showingMultiServer = false
    @State private var multiServerPreselected: Set<UUID> = []
    @State private var ospreyBridge = OspreyBridgeService.shared
    @State private var showingOspreyImport = false
    @State private var router = NavigationRouter.shared
    @State private var importPrefillHost: String?

    // Group management
    @State private var showingNewGroup = false
    @State private var newGroupName = ""
    @State private var groupToRename: ServerGroup?
    @State private var renameGroupName = ""
    @State private var groupToDelete: ServerGroup?
    @State private var showingDeleteGroup = false

    private var repository: ServerRepository {
        ServerRepository(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    summaryStrip
                    serverListSection
                    ospreyBridgeCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .refreshable {
                // Refresh OSPREY bridge data and prune stale sessions
                ospreyBridge.refresh()
                sessionManager.pruneDisconnectedSessions()
            }
            .background(KestrelColors.background)
            .navigationDestination(item: $selectedServerID) { serverID in
                if let server = servers.first(where: { $0.id == serverID }) {
                    switch server.connectionProtocol {
                    case .ssh:
                        ServerDetailView(server: server)
                    case .vnc:
                        VNCView(server: server)
                    case .rdp:
                        RDPView(server: server)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddServerSheet(editing: serverToEdit, prefillHost: importPrefillHost)
                    .onDisappear {
                        serverToEdit = nil
                        importPrefillHost = nil
                    }
            }
            .sheet(isPresented: $showingOspreyImport) {
                ImportFromOspreySheet(discoveredHosts: ospreyBridge.discoveredHosts)
            }
            .navigationDestination(isPresented: $showingMultiServer) {
                MultiServerView(preselectedServerIDs: multiServerPreselected)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        multiServerPreselected = []
                        showingMultiServer = true
                    } label: {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                }
            }
            .onAppear {
                // Auto-expand all groups on first load
                if expandedGroups.isEmpty {
                    for group in groups {
                        expandedGroups.insert(group.name)
                    }
                    expandedGroups.insert("__ungrouped__")
                }
            }
            .task(id: router.pendingImportHost) {
                print("[SERVERS] task fired, pendingImportHost: \(router.pendingImportHost ?? "nil")")
                guard let host = router.pendingImportHost else { return }
                try? await Task.sleep(for: .milliseconds(300))
                print("[SERVERS] Opening add sheet with host: \(host)")
                importPrefillHost = host
                router.pendingImportHost = nil
                showingAddSheet = true
            }
            .alert("New Group", isPresented: $showingNewGroup) {
                TextField("Group name", text: $newGroupName)
                Button("Create") {
                    createGroup(name: newGroupName)
                    newGroupName = ""
                }
                Button("Cancel", role: .cancel) {
                    newGroupName = ""
                }
            }
            .alert("Rename Group", isPresented: .init(
                get: { groupToRename != nil },
                set: { if !$0 { groupToRename = nil } }
            )) {
                TextField("Group name", text: $renameGroupName)
                Button("Rename") {
                    if let group = groupToRename {
                        renameGroup(group, to: renameGroupName)
                    }
                    groupToRename = nil
                    renameGroupName = ""
                }
                Button("Cancel", role: .cancel) {
                    groupToRename = nil
                    renameGroupName = ""
                }
            }
            .confirmationDialog(
                "Delete Group",
                isPresented: $showingDeleteGroup,
                titleVisibility: .visible
            ) {
                Button("Delete Group Only", role: .destructive) {
                    if let group = groupToDelete {
                        deleteGroup(group, includeServers: false)
                    }
                    groupToDelete = nil
                }
                if let group = groupToDelete,
                   servers.contains(where: { $0.group == group.name }) {
                    Button("Delete Group & Servers", role: .destructive) {
                        deleteGroup(group, includeServers: true)
                        groupToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    groupToDelete = nil
                }
            } message: {
                if let group = groupToDelete {
                    let count = servers.filter { $0.group == group.name }.count
                    Text("Delete \"\(group.name)\"? This group has \(count) server\(count == 1 ? "" : "s").")
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("◈ KESTREL")
                        .font(KestrelFonts.mono(11))
                        .tracking(2)
                        .foregroundStyle(KestrelColors.phosphorGreen)

                    Text("Servers")
                        .font(KestrelFonts.display(32, weight: .bold))
                        .foregroundStyle(KestrelColors.textPrimary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        showingNewGroup = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.textMuted)
                            .frame(width: 40, height: 40)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                            )
                    }

                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                            .frame(width: 40, height: 40)
                            .background(KestrelColors.phosphorGreenDim)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Summary Strip

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryItem(
                label: "TOTAL",
                value: "\(servers.count)",
                icon: "server.rack",
                color: KestrelColors.phosphorGreen
            )

            Rectangle()
                .fill(KestrelColors.cardBorder)
                .frame(width: 1)
                .padding(.vertical, 12)

            summaryItem(
                label: "ONLINE",
                value: "\(onlineCount)",
                icon: "circle.fill",
                color: KestrelColors.phosphorGreen
            )

            Rectangle()
                .fill(KestrelColors.cardBorder)
                .frame(width: 1)
                .padding(.vertical, 12)

            summaryItem(
                label: "WARNINGS",
                value: "\(warningCount)",
                icon: "exclamationmark.triangle.fill",
                color: warningCount > 0 ? KestrelColors.amber : KestrelColors.textFaint
            )
        }
        .padding(.vertical, 4)
        .background(KestrelColors.backgroundCardGreen)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
        )
    }

    private func summaryItem(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)

            Text(value)
                .font(KestrelFonts.display(22, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)

            Text(label)
                .font(KestrelFonts.mono(9))
                .tracking(1)
                .foregroundStyle(KestrelColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Server List

    private var serverListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Grouped servers
            ForEach(groups) { group in
                serverGroupSection(group: group)
            }

            // Ungrouped servers
            let ungrouped = servers.filter { $0.group == nil || $0.group?.isEmpty == true }
            if !ungrouped.isEmpty {
                ungroupedSection(servers: ungrouped)
            }

            // Empty state
            if servers.isEmpty {
                emptyState
            }
        }
    }

    private func serverGroupSection(group: ServerGroup) -> some View {
        let groupServers = servers.filter { $0.group == group.name }
        let isExpanded = expandedGroups.contains(group.name)

        return VStack(alignment: .leading, spacing: 8) {
            // Group header
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    if isExpanded {
                        expandedGroups.remove(group.name)
                    } else {
                        expandedGroups.insert(group.name)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(KestrelColors.textMuted)
                        .frame(width: 16)

                    Text(group.name.uppercased())
                        .font(KestrelFonts.mono(11))
                        .tracking(1.5)
                        .foregroundStyle(KestrelColors.textMuted)

                    Capsule()
                        .fill(KestrelColors.textFaint)
                        .frame(width: 22, height: 16)
                        .overlay(
                            Text("\(groupServers.count)")
                                .font(KestrelFonts.mono(9))
                                .foregroundStyle(KestrelColors.textMuted)
                        )

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    renameGroupName = group.name
                    groupToRename = group
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    groupToDelete = group
                    showingDeleteGroup = true
                } label: {
                    Label("Delete Group", systemImage: "trash")
                }
            }

            if isExpanded {
                if groupServers.isEmpty {
                    emptyGroupCard(groupName: group.name)
                } else {
                    ForEach(groupServers) { server in
                        serverRow(server)
                    }
                }
            }
        }
    }

    private func ungroupedSection(servers: [SSHServer]) -> some View {
        let isExpanded = expandedGroups.contains("__ungrouped__")

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    if isExpanded {
                        expandedGroups.remove("__ungrouped__")
                    } else {
                        expandedGroups.insert("__ungrouped__")
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(KestrelColors.textMuted)
                        .frame(width: 16)

                    Text("UNGROUPED")
                        .font(KestrelFonts.mono(11))
                        .tracking(1.5)
                        .foregroundStyle(KestrelColors.textMuted)

                    Capsule()
                        .fill(KestrelColors.textFaint)
                        .frame(width: 22, height: 16)
                        .overlay(
                            Text("\(servers.count)")
                                .font(KestrelFonts.mono(9))
                                .foregroundStyle(KestrelColors.textMuted)
                        )

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(servers) { server in
                    serverRow(server)
                }
            }
        }
    }

    // MARK: - Server Row

    @ViewBuilder
    private func serverRow(_ server: SSHServer) -> some View {
        let session = sessionManager.activeSession(for: server.id)
        let status = serverStatus(for: server)
        let cpuUsage = cpuUsage(for: server)

        Button {
            selectedServerID = server.id
        } label: {
            ServerRowCard(
                server: server,
                status: status,
                cpuUsage: cpuUsage,
                isConnecting: connectingServerID == server.id
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            contextMenuItems(for: server, session: session)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteServer(server)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                connectToServer(server)
            } label: {
                Label("Connect", systemImage: "bolt.fill")
            }
            .tint(Color(red: 0, green: 0.7, blue: 0.2))
        }
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }

    @ViewBuilder
    private func contextMenuItems(for server: SSHServer, session: SSHSession?) -> some View {
        if session?.isConnected == true {
            Button {
                sessionManager.closeSession(serverID: server.id)
            } label: {
                Label("Disconnect", systemImage: "bolt.slash")
            }
        } else {
            Button {
                connectToServer(server)
            } label: {
                Label("Connect", systemImage: "bolt.fill")
            }
        }

        Button {
            multiServerPreselected = [server.id]
            showingMultiServer = true
        } label: {
            Label("Multi-Server", systemImage: "rectangle.stack")
        }

        Divider()

        // Move to Group submenu
        Menu {
            if server.group != nil {
                Button {
                    moveServer(server, toGroup: nil)
                } label: {
                    Label("Ungrouped", systemImage: "minus.circle")
                }
            }

            ForEach(groups) { group in
                if server.group != group.name {
                    Button {
                        moveServer(server, toGroup: group.name)
                    } label: {
                        Label(group.name, systemImage: "folder")
                    }
                }
            }
        } label: {
            Label("Move to Group", systemImage: "folder.badge.gearshape")
        }

        Button {
            serverToEdit = server
            showingAddSheet = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button {
            duplicateServer(server)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            deleteServer(server)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundStyle(KestrelColors.textFaint)

            Text("No servers yet")
                .font(KestrelFonts.display(18, weight: .semibold))
                .foregroundStyle(KestrelColors.textMuted)

            Text("Add your first server to get started")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textFaint)

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Server", systemImage: "plus")
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func emptyGroupCard(groupName: String) -> some View {
        HStack {
            Text("No servers in this group")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textFaint)

            Spacer()

            Button {
                showingAddSheet = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(KestrelColors.textMuted)
            }
        }
        .padding(12)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(KestrelColors.cardBorder.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Osprey Bridge Card

    @ViewBuilder
    private var ospreyBridgeCard: some View {
        let hosts = ospreyBridge.visibleDiscoveredHosts
        let hasData = ospreyBridge.hasOspreyInstalled && !hosts.isEmpty

        if hasData {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("OSPREY")
                        .font(KestrelFonts.mono(11))
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(KestrelColors.blue)

                    Spacer()

                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            ospreyBridge.dismissDiscoveredHosts()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(KestrelColors.textFaint)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14))
                        .foregroundStyle(KestrelColors.blue)
                }

                Text("\(hosts.count) hosts discovered\(ospreyBridge.lastScanSubnet.map { " on \($0)" } ?? "")")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textMuted)

                HStack(spacing: 10) {
                    Button {
                        showingOspreyImport = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Import hosts")
                                .font(KestrelFonts.mono(12))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(KestrelColors.blue)
                    }

                    Spacer()

                    NavigationLink {
                        OspreyBridgeView()
                    } label: {
                        Text("Bridge →")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                }
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [
                        KestrelColors.blue.opacity(0.05),
                        KestrelColors.phosphorGreen.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                KestrelColors.blue.opacity(0.3),
                                KestrelColors.phosphorGreen.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    // MARK: - Computed Properties

    private var onlineCount: Int {
        servers.filter { server in
            sessionManager.activeSession(for: server.id)?.isConnected == true
        }.count
    }

    private var warningCount: Int {
        // Count servers with high resource usage
        // This will be populated when ServerStatsEngine is polled
        0
    }

    private func serverStatus(for server: SSHServer) -> ServerStatus {
        if let session = sessionManager.activeSession(for: server.id) {
            switch session.state {
            case .connected: return .online
            case .error: return .warning
            default: return .offline
            }
        }
        return .offline
    }

    private func cpuUsage(for server: SSHServer) -> Double {
        guard let engine = sessionManager.statsEngine(for: server.id) else { return 0 }
        return (engine.stats?.cpuPercent ?? 0) / 100.0
    }

    // MARK: - Actions

    private func connectToServer(_ server: SSHServer) {
        connectingServerID = server.id

        Task {
            do {
                _ = try await sessionManager.openSession(for: server)
                // Signal terminal and SFTP tabs to auto-connect
                NavigationRouter.shared.serverDidConnect(server)
            } catch {
                // Error is shown via session state
            }
            connectingServerID = nil
        }
    }

    private func deleteServer(_ server: SSHServer) {
        sessionManager.closeSession(serverID: server.id)
        withAnimation(.snappy) {
            modelContext.delete(server)
            try? modelContext.save()
        }
    }

    private func createGroup(name: String) {
        guard !name.isEmpty else { return }
        let group = ServerGroup(
            name: name,
            orderIndex: groups.count
        )
        withAnimation(.snappy) {
            modelContext.insert(group)
            try? modelContext.save()
            expandedGroups.insert(name)
        }
    }

    private func renameGroup(_ group: ServerGroup, to newName: String) {
        guard !newName.isEmpty else { return }
        let oldName = group.name
        // Update all servers referencing this group
        for server in servers where server.group == oldName {
            server.group = newName
        }
        // Update expanded groups tracking
        if expandedGroups.contains(oldName) {
            expandedGroups.remove(oldName)
            expandedGroups.insert(newName)
        }
        group.name = newName
        try? modelContext.save()
    }

    private func deleteGroup(_ group: ServerGroup, includeServers: Bool) {
        let supabase = SupabaseService.shared
        withAnimation(.snappy) {
            if includeServers {
                for server in servers where server.group == group.name {
                    sessionManager.closeSession(serverID: server.id)
                    let syncable = SyncableServer(from: server)
                    modelContext.delete(server)
                    Task { try? await supabase.deleteServer(syncable) }
                }
            } else {
                for server in servers where server.group == group.name {
                    server.group = nil
                    server.updatedAt = .now
                    Task { try? await supabase.upsertServer(SyncableServer(from: server)) }
                }
            }
            expandedGroups.remove(group.name)
            let syncableGroup = SyncableServerGroup(from: group)
            modelContext.delete(group)
            try? modelContext.save()
            Task { try? await supabase.deleteGroup(syncableGroup) }
        }
    }

    private func moveServer(_ server: SSHServer, toGroup groupName: String?) {
        withAnimation(.snappy) {
            server.group = groupName
            try? modelContext.save()
        }
    }

    private func duplicateServer(_ server: SSHServer) {
        let duplicate = SSHServer(
            name: "\(server.name) (copy)",
            host: server.host,
            port: server.port,
            username: server.username,
            authMethod: server.authMethod,
            privateKeyID: server.privateKeyID,
            group: server.group,
            environment: server.environment,
            colour: server.colour,
            tags: server.tags,
            orderIndex: server.orderIndex + 1
        )

        withAnimation(.snappy) {
            modelContext.insert(duplicate)
            try? modelContext.save()
        }
    }
}

// MARK: - Server Row Card

struct ServerRowCard: View {
    let server: SSHServer
    let status: ServerStatus
    let cpuUsage: Double
    let isConnecting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: status, name, env badge
            HStack(spacing: 8) {
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 8, height: 8)
                } else {
                    StatusDot(status: status)
                }

                Text(server.name)
                    .font(KestrelFonts.monoBold(14))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .lineLimit(1)

                Image(systemName: server.port == 23 ? "terminal" : "lock.shield")
                    .font(.system(size: 10))
                    .foregroundStyle(server.port == 23 ? KestrelColors.amber : KestrelColors.textFaint)

                Spacer()

                EnvBadge(env: server.environment)
            }

            // Middle row: host and stats
            HStack {
                ServerConnectionLabel(
                    username: server.username,
                    host: server.host,
                    port: server.port
                )

                Spacer()

                if status == .online {
                    Text("\(Int(cpuUsage * 100))%")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(cpuBarColor)
                }
            }

            // Bot row: CPU bar
            HStack(spacing: 6) {
                Text("CPU")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)

                MiniBar(
                    progress: cpuUsage,
                    color: cpuBarColor
                )
            }
        }
        .padding(12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardBorderColor, lineWidth: 1)
        )
    }

    private var cpuBarColor: Color {
        if cpuUsage > 0.85 { return KestrelColors.red }
        if cpuUsage > 0.70 { return KestrelColors.amber }
        return KestrelColors.phosphorGreen
    }

    private var cardBackground: Color {
        switch status {
        case .online: KestrelColors.backgroundCardGreen
        default: KestrelColors.backgroundCard
        }
    }

    private var cardBorderColor: Color {
        switch status {
        case .online: KestrelColors.cardBorderGreen
        case .warning: KestrelColors.amber.opacity(0.2)
        case .offline: KestrelColors.cardBorder
        }
    }
}

