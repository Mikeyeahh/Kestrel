//
//  SFTPView.swift
//  Kestrel
//
//  SFTP file browser with server selection, directory navigation, and file operations.
//

import SwiftUI
import SwiftData
import PostHog

// MARK: - SFTP View (Root)

struct SFTPView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SSHServer.orderIndex) private var servers: [SSHServer]

    @State private var router = NavigationRouter.shared
    @State private var session: SFTPSession?
    @State private var showingServerPicker = false
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var showingFilePreview = false
    @State private var previewContent: String?
    @State private var previewFileName: String?
    @State private var itemToDelete: SFTPFileItem?
    @State private var showingDeleteConfirmation = false

    @State private var revenueCat = KestrelRevenueCatService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let session {
                    if session.isConnected {
                        // Mask file names and contents from session replay.
                        fileBrowser(session: session)
                            .postHogMask()
                    } else if session.isLoading {
                        connectingState(serverName: session.serverName)
                    } else if let error = session.error {
                        errorState(message: error)
                    }
                } else {
                    emptyState
                }
            }
            .proGated(feature: .sftpFiles)
            .background(KestrelColors.background)
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if let session, session.isConnected {
                        Button {
                            session.disconnect()
                            self.session = nil
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(KestrelColors.textMuted)
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let session, session.isConnected {
                        Button {
                            Task { try? await session.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .foregroundStyle(KestrelColors.textMuted)
                        }

                        Button {
                            showingNewFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 14))
                                .foregroundStyle(KestrelColors.textMuted)
                        }
                    }

                    Button {
                        showingServerPicker = true
                    } label: {
                        Image(systemName: session?.isConnected == true ? "server.rack" : "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                    }
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
            .sheet(isPresented: $showingServerPicker) {
                ServerPickerSheet(servers: servers) { server in
                    connectToServer(server)
                }
            }
            .alert("New Folder", isPresented: $showingNewFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Create") {
                    guard let session, !newFolderName.isEmpty else { return }
                    let name = newFolderName
                    newFolderName = ""
                    Task { try? await session.createDirectory(named: name) }
                }
                Button("Cancel", role: .cancel) {
                    newFolderName = ""
                }
            }
            .confirmationDialog(
                "Delete Item",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete, let session {
                        Task {
                            try? await session.deleteItem(at: item.path, isDirectory: item.isDirectory)
                        }
                    }
                    itemToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    itemToDelete = nil
                }
            } message: {
                if let item = itemToDelete {
                    Text("Delete \"\(item.name)\"? This cannot be undone.")
                }
            }
            .sheet(isPresented: $showingFilePreview) {
                filePreviewSheet
            }
            .onAppear { consumePendingSFTP() }
            .onChange(of: router.pendingSFTPServer?.id) { _, _ in consumePendingSFTP() }
        }
    }

    // MARK: - File Browser

    private func fileBrowser(session: SFTPSession) -> some View {
        VStack(spacing: 0) {
            // Connection bar
            connectionBar(session: session)

            // Path breadcrumb
            pathBar(session: session)

            // File list
            if session.isLoading {
                Spacer()
                ProgressView()
                    .tint(KestrelColors.phosphorGreen)
                Spacer()
            } else if session.items.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 36))
                        .foregroundStyle(KestrelColors.textFaint)
                    Text("Empty directory")
                        .font(KestrelFonts.mono(13))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Navigate up row
                        if session.currentPath != "/" {
                            Button {
                                Task { try? await session.navigateUp() }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.turn.up.left")
                                        .font(.system(size: 14))
                                        .foregroundStyle(KestrelColors.phosphorGreen)
                                        .frame(width: 28)

                                    Text("..")
                                        .font(KestrelFonts.monoBold(13))
                                        .foregroundStyle(KestrelColors.phosphorGreen)

                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(KestrelColors.backgroundCard)
                            }
                        }

                        ForEach(session.items) { item in
                            fileRow(item, session: session)
                        }
                    }
                    .padding(.bottom, 80)
                }
            }

            if let error = session.error {
                errorBanner(message: error)
            }
        }
    }

    // MARK: - Connection Bar

    private func connectionBar(session: SFTPSession) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(KestrelColors.phosphorGreen)
                .frame(width: 6, height: 6)

            Text(session.serverName)
                .font(KestrelFonts.monoBold(12))
                .foregroundStyle(KestrelColors.textPrimary)

            Text("SFTP")
                .font(KestrelFonts.mono(9))
                .fontWeight(.bold)
                .tracking(1)
                .foregroundStyle(KestrelColors.phosphorGreen)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(KestrelColors.phosphorGreenDim)
                .clipShape(Capsule())

            Spacer()

            Button {
                Task { try? await session.goBack() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        session.pathHistory.count > 1
                            ? KestrelColors.textMuted
                            : KestrelColors.textFaint
                    )
            }
            .disabled(session.pathHistory.count <= 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(KestrelColors.backgroundCard)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KestrelColors.cardBorder)
                .frame(height: 1)
        }
    }

    // MARK: - Path Bar

    private func pathBar(session: SFTPSession) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                let components = pathComponents(session.currentPath)
                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundStyle(KestrelColors.textFaint)
                    }

                    Button {
                        let targetPath = buildPath(from: components, upTo: index)
                        Task { try? await session.navigateTo(targetPath) }
                    } label: {
                        Text(component.name)
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(
                                index == components.count - 1
                                    ? KestrelColors.phosphorGreen
                                    : KestrelColors.textMuted
                            )
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(Color.black.opacity(0.3))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KestrelColors.cardBorder)
                .frame(height: 1)
        }
    }

    // MARK: - File Row

    private func fileRow(_ item: SFTPFileItem, session: SFTPSession) -> some View {
        Button {
            if item.isDirectory {
                Task { try? await session.navigateTo(item.path) }
            } else {
                previewFile(item, session: session)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(item.isDirectory ? KestrelColors.amber : KestrelColors.textMuted)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(KestrelFonts.mono(13))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(item.permissions)
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textFaint)

                        if let modified = item.modified {
                            Text(modified, style: .relative)
                                .font(KestrelFonts.mono(9))
                                .foregroundStyle(KestrelColors.textFaint)
                        }
                    }
                }

                Spacer()

                if !item.isDirectory {
                    Text(item.formattedSize)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textMuted)
                }

                if item.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(KestrelColors.textFaint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(KestrelColors.background)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.isDirectory {
                Button {
                    Task { try? await session.navigateTo(item.path) }
                } label: {
                    Label("Open", systemImage: "folder")
                }
            } else {
                Button {
                    previewFile(item, session: session)
                } label: {
                    Label("Preview", systemImage: "eye")
                }

                Button {
                    UIPasteboard.general.string = item.path
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button(role: .destructive) {
                itemToDelete = item
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(KestrelColors.textFaint)

            Text("SFTP File Manager")
                .font(KestrelFonts.display(18, weight: .semibold))
                .foregroundStyle(KestrelColors.textMuted)

            Text("Browse and manage files on your servers")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textFaint)

            Button {
                showingServerPicker = true
            } label: {
                Label("Connect to Server", systemImage: "server.rack")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Connecting State

    private func connectingState(serverName: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(KestrelColors.phosphorGreen)

            Text("Connecting to \(serverName)…")
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.textMuted)

            Text("Establishing SFTP session")
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundStyle(KestrelColors.red)

            Text("Connection Failed")
                .font(KestrelFonts.monoBold(14))
                .foregroundStyle(KestrelColors.textPrimary)

            Text(message)
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                session = nil
                showingServerPicker = true
            } label: {
                Label("Try Another Server", systemImage: "arrow.clockwise")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(KestrelColors.phosphorGreenDim)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(KestrelColors.amber)

            Text(message)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.amber)
                .lineLimit(2)

            Spacer()
        }
        .padding(10)
        .background(KestrelColors.amber.opacity(0.08))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KestrelColors.amber.opacity(0.3))
                .frame(height: 1)
        }
    }

    // MARK: - File Preview

    private var filePreviewSheet: some View {
        NavigationStack {
            ScrollView {
                if let content = previewContent {
                    Text(content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ProgressView()
                        .tint(KestrelColors.phosphorGreen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                }
            }
            .background(Color.black)
            .navigationTitle(previewFileName ?? "File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingFilePreview = false
                        previewContent = nil
                        previewFileName = nil
                    }
                    .foregroundStyle(KestrelColors.phosphorGreen)
                }

                if let content = previewContent {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            UIPasteboard.general.string = content
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundStyle(KestrelColors.textMuted)
                        }
                    }
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.black)
    }

    // MARK: - Helpers

    private func consumePendingSFTP() {
        guard let server = router.pendingSFTPServer else { return }
        if session?.serverID != server.id || session?.isConnected != true {
            connectToServer(server)
        }
        router.pendingSFTPServer = nil
    }

    private func connectToServer(_ server: SSHServer) {
        // Disconnect existing session if any
        session?.disconnect()

        let newSession = SFTPSession(serverID: server.id, serverName: server.name)
        session = newSession

        Task {
            do {
                try await newSession.connect(server: server)
            } catch {
                // Error is shown via session.error
            }
        }
    }

    private func previewFile(_ item: SFTPFileItem, session: SFTPSession) {
        // Only preview text-like files under 1MB
        guard item.size < 1_048_576 else { return }

        previewFileName = item.name
        previewContent = nil
        showingFilePreview = true

        Task {
            do {
                let data = try await session.readFile(at: item.path)
                if let text = String(data: data, encoding: .utf8) {
                    previewContent = text
                } else {
                    previewContent = "[Binary file — cannot preview]"
                }
            } catch {
                previewContent = "[Error reading file: \(error.localizedDescription)]"
            }
        }
    }

    private struct PathComponent {
        let name: String
        let fullPath: String
    }

    private func pathComponents(_ path: String) -> [PathComponent] {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        var components = [PathComponent(name: "/", fullPath: "/")]

        var accumulated = ""
        for part in parts {
            accumulated += "/\(part)"
            components.append(PathComponent(name: String(part), fullPath: accumulated))
        }

        return components
    }

    private func buildPath(from components: [PathComponent], upTo index: Int) -> String {
        guard index < components.count else { return "/" }
        return components[index].fullPath
    }
}
