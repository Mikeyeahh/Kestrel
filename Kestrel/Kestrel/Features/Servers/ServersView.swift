//
//  ServersView.swift
//  Kestrel
//

import SwiftUI
import SwiftData

/// Fixed hex palette for group-name colours — matches the Windows app so a
/// colour set on any platform renders identically everywhere.
private struct GroupColourOption: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }
}

private let groupColourOptions: [GroupColourOption] = [
    GroupColourOption(name: "Green", hex: "#00FF41"),
    GroupColourOption(name: "Blue", hex: "#00C8FF"),
    GroupColourOption(name: "Purple", hex: "#A78BFA"),
    GroupColourOption(name: "Amber", hex: "#FFB800"),
    GroupColourOption(name: "Red", hex: "#FF3B5C"),
    GroupColourOption(name: "Orange", hex: "#FF8A3D"),
    GroupColourOption(name: "Teal", hex: "#00E5CC"),
    GroupColourOption(name: "Grey", hex: "#9AA7B4"),
]

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
    @State private var didSeedExpansion = false
    @State private var connectingServerID: UUID?
    @State private var showingMultiServer = false
    @State private var multiServerPreselected: Set<UUID> = []
    @State private var ospreyBridge = OspreyBridgeService.shared
    @State private var showingOspreyImport = false
    @State private var router = NavigationRouter.shared
    @State private var importPrefillHost: String?
    @State private var revenueCat = KestrelRevenueCatService.shared
    @State private var showingPaywall = false

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

    /// Resolve a server's group id. Prefers the canonical `groupId`; falls
    /// back to matching the legacy `group` *name* so pre-id data still groups.
    private func effectiveGroupId(_ server: SSHServer) -> UUID? {
        if let gid = server.groupId { return gid }
        guard let name = server.group, !name.isEmpty else { return nil }
        return groups.first(where: { $0.name == name })?.id
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
                AddServerSheet(prefillHost: importPrefillHost)
                    .onDisappear {
                        importPrefillHost = nil
                    }
            }
            // Edit uses item-based presentation so the selected server is
            // guaranteed to be set when the sheet first builds. Presenting edit
            // through the `showingAddSheet` bool let SwiftUI build the sheet
            // before `serverToEdit` had propagated, so the form opened empty the
            // first time and only filled in on a second open.
            .sheet(item: $serverToEdit) { server in
                AddServerSheet(editing: server)
            }
            .sheet(isPresented: $showingPaywall) {
                KestrelPaywallView()
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
                // On launch, top-level (root) folders are expanded so their
                // contents are visible, while nested folders start collapsed.
                // Ungrouped stays expanded so loose servers stay visible.
                // Seeded once per launch; manual toggles are kept afterwards.
                guard !didSeedExpansion else { return }
                didSeedExpansion = true
                expandedGroups.insert("__ungrouped__")
                for group in rootGroups {
                    expandedGroups.insert(group.id.uuidString)
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
                   servers.contains(where: { effectiveGroupId($0) == group.id }) {
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
                    let count = servers.filter { effectiveGroupId($0) == group.id }.count
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

    // Groups form a tree (via `parentId`). The list is rendered from a
    // flattened, depth-tagged walk of that tree so nesting + collapse work
    // with plain stacks. A collapsed group omits its descendants.

    private enum SidebarRow: Identifiable {
        case group(ServerGroup, depth: Int)
        case server(SSHServer, depth: Int)
        case ungroupedHeader(Int)
        case ungroupedServer(SSHServer)

        var id: String {
            switch self {
            case .group(let g, _): return "group-\(g.id.uuidString)"
            case .server(let s, _): return "server-\(s.id.uuidString)"
            case .ungroupedHeader: return "ungrouped-header"
            case .ungroupedServer(let s): return "ungrouped-\(s.id.uuidString)"
            }
        }
    }

    private func childGroups(of parentId: UUID?) -> [ServerGroup] {
        groups
            .filter { $0.parentId == parentId }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Top-level groups — those with no parent, plus any whose `parentId`
    /// points at a group that no longer exists (so orphans still render).
    private var rootGroups: [ServerGroup] {
        let knownIds = Set(groups.map(\.id))
        return groups
            .filter { group in
                guard let parent = group.parentId else { return true }
                return !knownIds.contains(parent)
            }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func isGroupExpanded(_ group: ServerGroup) -> Bool {
        expandedGroups.contains(group.id.uuidString)
    }

    private var sidebarRows: [SidebarRow] {
        var rows: [SidebarRow] = []
        func walk(_ group: ServerGroup, depth: Int) {
            rows.append(.group(group, depth: depth))
            guard isGroupExpanded(group) else { return }
            let groupServers = servers
                .filter { effectiveGroupId($0) == group.id }
                .sorted { $0.orderIndex < $1.orderIndex }
            for server in groupServers {
                rows.append(.server(server, depth: depth + 1))
            }
            for child in childGroups(of: group.id) {
                walk(child, depth: depth + 1)
            }
        }
        for root in rootGroups {
            walk(root, depth: 0)
        }
        let ungrouped = servers
            .filter { effectiveGroupId($0) == nil }
            .sorted { $0.orderIndex < $1.orderIndex }
        if !ungrouped.isEmpty {
            rows.append(.ungroupedHeader(ungrouped.count))
            if expandedGroups.contains("__ungrouped__") {
                for server in ungrouped {
                    rows.append(.ungroupedServer(server))
                }
            }
        }
        return rows
    }

    private var serverListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sidebarRows) { row in
                sidebarRowView(row)
            }
            if servers.isEmpty {
                emptyState
            }
        }
    }

    @ViewBuilder
    private func sidebarRowView(_ row: SidebarRow) -> some View {
        switch row {
        case .group(let group, let depth):
            groupHeaderRow(group, depth: depth)
        case .server(let server, let depth):
            serverRow(server)
                .padding(.leading, CGFloat(depth) * 14)
                .draggable("server:\(server.id.uuidString)")
        case .ungroupedHeader(let count):
            ungroupedHeaderRow(count: count)
        case .ungroupedServer(let server):
            serverRow(server)
                .padding(.leading, 14)
                .draggable("server:\(server.id.uuidString)")
        }
    }

    private func groupHeaderRow(_ group: ServerGroup, depth: Int) -> some View {
        let isExpanded = isGroupExpanded(group)
        let count = servers.filter { effectiveGroupId($0) == group.id }.count

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                if isExpanded {
                    expandedGroups.remove(group.id.uuidString)
                } else {
                    expandedGroups.insert(group.id.uuidString)
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
                    .foregroundStyle(Color(hex: group.colour) ?? KestrelColors.textMuted)

                Capsule()
                    .fill(KestrelColors.textFaint)
                    .frame(width: 22, height: 16)
                    .overlay(
                        Text("\(count)")
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textMuted)
                    )

                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 14)
            .padding(.top, 10)
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
            // Nesting via menu — reliable regardless of how iOS arbitrates
            // the long-press between the context menu and the drag gesture.
            Menu {
                if group.parentId != nil {
                    Button {
                        reparentGroup(group.id, toParentId: nil)
                    } label: {
                        Label("Top Level", systemImage: "arrow.up.left")
                    }
                }
                ForEach(candidateParents(for: group)) { other in
                    Button {
                        reparentGroup(group.id, toParentId: other.id)
                    } label: {
                        Label(other.name, systemImage: "folder")
                    }
                }
            } label: {
                Label("Move Into…", systemImage: "folder.badge.gearshape")
            }
            // Group-name colour.
            Menu {
                ForEach(groupColourOptions) { opt in
                    Button {
                        setGroupColour(group, hex: opt.hex)
                    } label: {
                        Label {
                            Text(opt.name)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(Color(hex: opt.hex) ?? .gray)
                        }
                    }
                }
            } label: {
                Label("Colour", systemImage: "paintpalette")
            }
            Button(role: .destructive) {
                groupToDelete = group
                showingDeleteGroup = true
            } label: {
                Label("Delete Group", systemImage: "trash")
            }
        }
        .draggable("group:\(group.id.uuidString)")
        .dropDestination(for: String.self) { items, _ in
            handleSidebarDrop(items, ontoGroupId: group.id)
        }
    }

    private func ungroupedHeaderRow(count: Int) -> some View {
        let isExpanded = expandedGroups.contains("__ungrouped__")
        return Button {
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
                        Text("\(count)")
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textMuted)
                    )

                Spacer()
            }
            .padding(.top, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Dropping a group here moves it to the root; a server here ungroups it.
        .dropDestination(for: String.self) { items, _ in
            handleSidebarDrop(items, ontoGroupId: nil)
        }
    }

    // MARK: - Drag & Drop
    //
    // A dragged payload is `server:<uuid>` or `group:<uuid>`. Dropping a
    // server onto a group joins it; dropping a group onto a group nests it;
    // dropping either on the Ungrouped header moves it back to the root.

    private func handleSidebarDrop(_ items: [String], ontoGroupId targetGroupId: UUID?) -> Bool {
        guard let payload = items.first else { return false }
        if payload.hasPrefix("group:") {
            guard let gid = UUID(uuidString: String(payload.dropFirst(6))) else { return false }
            reparentGroup(gid, toParentId: targetGroupId)
            return true
        } else if payload.hasPrefix("server:") {
            guard let sid = UUID(uuidString: String(payload.dropFirst(7))),
                  let server = servers.first(where: { $0.id == sid }) else { return false }
            moveServer(server, toGroupId: targetGroupId)
            return true
        }
        return false
    }

    /// Re-parent a group. Ignores self-drops, no-op moves, and any move that
    /// would create a cycle (dropping a group onto one of its descendants).
    private func reparentGroup(_ id: UUID, toParentId newParent: UUID?) {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        if id == newParent || group.parentId == newParent { return }
        if let newParent, isDescendant(newParent, of: id) { return }
        withAnimation(.snappy) {
            group.parentId = newParent
            try? modelContext.save()
        }
        Task {
            try? await SupabaseService.shared.upsertGroup(SyncableServerGroup(from: group))
        }
    }

    private func isDescendant(_ candidate: UUID, of ancestor: UUID) -> Bool {
        var current = groups.first(where: { $0.id == candidate })
        while let parent = current?.parentId {
            if parent == ancestor { return true }
            current = groups.first(where: { $0.id == parent })
        }
        return false
    }

    /// Groups that `group` may be moved into — excludes itself, its current
    /// parent, and any descendant (which would form a cycle).
    private func candidateParents(for group: ServerGroup) -> [ServerGroup] {
        groups
            .filter { $0.id != group.id }
            .filter { $0.id != group.parentId }
            .filter { !isDescendant($0.id, of: group.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Server Row

    /// Returns the global index (0-based) of a server in the sorted list.
    private func globalIndex(of server: SSHServer) -> Int {
        servers.firstIndex(where: { $0.id == server.id }) ?? 0
    }

    @ViewBuilder
    private func serverRow(_ server: SSHServer) -> some View {
        let session = sessionManager.activeSession(for: server.id)
        let status = serverStatus(for: server)
        let cpuUsage = cpuUsage(for: server)
        let locked = revenueCat.isServerLocked(at: globalIndex(of: server))

        Button {
            if locked {
                showingPaywall = true
            } else {
                selectedServerID = server.id
            }
        } label: {
            ServerRowCard(
                server: server,
                status: status,
                cpuUsage: cpuUsage,
                isConnecting: connectingServerID == server.id,
                isLocked: locked
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !locked {
                contextMenuItems(for: server, session: session)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteServer(server)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !locked {
                Button {
                    connectToServer(server)
                } label: {
                    Label("Connect", systemImage: "bolt.fill")
                }
                .tint(Color(red: 0, green: 0.7, blue: 0.2))
            }
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
            if effectiveGroupId(server) != nil {
                Button {
                    moveServer(server, toGroupId: nil)
                } label: {
                    Label("Ungrouped", systemImage: "minus.circle")
                }
            }

            ForEach(groups) { group in
                if effectiveGroupId(server) != group.id {
                    Button {
                        moveServer(server, toGroupId: group.id)
                    } label: {
                        Label(group.name, systemImage: "folder")
                    }
                }
            }
        } label: {
            Label("Move to Group", systemImage: "folder.badge.gearshape")
        }

        Button {
            // Setting the item presents the edit sheet; no bool needed.
            serverToEdit = server
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
            // Expand the freshly created group so the user sees it open.
            expandedGroups.insert(group.id.uuidString)
        }
    }

    private func renameGroup(_ group: ServerGroup, to newName: String) {
        guard !newName.isEmpty else { return }
        let oldName = group.name
        // Membership is by id, so the rename touches no servers — except
        // legacy ones still referencing the old *name*, which are migrated
        // onto the stable id here so the rename can't orphan them.
        let supabase = SupabaseService.shared
        for server in servers where server.groupId == nil && server.group == oldName {
            server.groupId = group.id
            server.group = nil
            server.updatedAt = .now
            Task { try? await supabase.upsertServer(SyncableServer(from: server)) }
        }
        // `expandedGroups` is keyed by group id, so a rename leaves it alone.
        group.name = newName
        try? modelContext.save()
        Task { try? await supabase.upsertGroup(SyncableServerGroup(from: group)) }
    }

    /// Set a group's name colour and sync it.
    private func setGroupColour(_ group: ServerGroup, hex: String) {
        guard group.colour != hex else { return }
        group.colour = hex
        try? modelContext.save()
        Task {
            try? await SupabaseService.shared.upsertGroup(SyncableServerGroup(from: group))
        }
    }

    private func deleteGroup(_ group: ServerGroup, includeServers: Bool) {
        let supabase = SupabaseService.shared
        withAnimation(.snappy) {
            let members = servers.filter { effectiveGroupId($0) == group.id }
            if includeServers {
                for server in members {
                    sessionManager.closeSession(serverID: server.id)
                    let syncable = SyncableServer(from: server)
                    modelContext.delete(server)
                    Task { try? await supabase.deleteServer(syncable) }
                }
            } else {
                for server in members {
                    server.groupId = nil
                    server.group = nil
                    server.updatedAt = .now
                    Task { try? await supabase.upsertServer(SyncableServer(from: server)) }
                }
            }
            expandedGroups.remove(group.id.uuidString)
            // Lift any child groups up to the root so they aren't orphaned.
            for child in groups where child.parentId == group.id {
                child.parentId = nil
                Task { try? await supabase.upsertGroup(SyncableServerGroup(from: child)) }
            }
            let syncableGroup = SyncableServerGroup(from: group)
            modelContext.delete(group)
            try? modelContext.save()
            Task { try? await supabase.deleteGroup(syncableGroup) }
        }
    }

    private func moveServer(_ server: SSHServer, toGroupId groupId: UUID?) {
        withAnimation(.snappy) {
            server.groupId = groupId
            server.group = nil
            server.updatedAt = .now
            try? modelContext.save()
            Task {
                try? await SupabaseService.shared.upsertServer(SyncableServer(from: server))
            }
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
            groupId: server.groupId,
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
    var isLocked: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: status, name, env badge
            HStack(spacing: 8) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(KestrelColors.amber)
                } else if isConnecting {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 8, height: 8)
                } else {
                    StatusDot(status: status)
                }

                Text(server.name)
                    .font(KestrelFonts.monoBold(14))
                    .foregroundStyle(isLocked ? KestrelColors.textMuted : KestrelColors.textPrimary)
                    .lineLimit(1)

                if !isLocked {
                    Image(systemName: server.port == 23 ? "terminal" : "lock.shield")
                        .font(.system(size: 10))
                        .foregroundStyle(server.port == 23 ? KestrelColors.amber : KestrelColors.textFaint)
                }

                Spacer()

                if isLocked {
                    Text("PRO")
                        .font(KestrelFonts.mono(8))
                        .fontWeight(.bold)
                        .tracking(0.8)
                        .foregroundStyle(KestrelColors.background)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(KestrelColors.amber)
                        .clipShape(Capsule())
                } else {
                    EnvBadge(env: server.environment)
                }
            }

            // Middle row: host and stats
            HStack {
                ServerConnectionLabel(
                    username: server.username,
                    host: server.host,
                    port: server.port
                )

                Spacer()

                if !isLocked && status == .online {
                    Text("\(Int(cpuUsage * 100))%")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(cpuBarColor)
                }
            }

            // Bot row: CPU bar
            if !isLocked {
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
        }
        .padding(12)
        .background(isLocked ? KestrelColors.backgroundCard.opacity(0.5) : cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isLocked ? KestrelColors.amber.opacity(0.15) : cardBorderColor, lineWidth: 1)
        )
        .opacity(isLocked ? 0.7 : 1)
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

