//
//  AddServerSheet.swift
//  Kestrel
//

import SwiftUI
import SwiftData

struct AddServerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ServerGroup.orderIndex) private var groups: [ServerGroup]
    @Query(sort: \KeychainKey.createdAt) private var savedKeys: [KeychainKey]

    @Query private var allServers: [SSHServer]

    /// When non-nil, the sheet is in edit mode for this server.
    let editingServer: SSHServer?

    /// Pre-filled host from deep link (e.g. Osprey LAN scanner import).
    let prefillHost: String?

    init(editing server: SSHServer? = nil, prefillHost: String? = nil) {
        self.editingServer = server
        self.prefillHost = prefillHost
    }

    @State private var revenueCat = KestrelRevenueCatService.shared

    private var isEditing: Bool { editingServer != nil }

    // MARK: - Form State

    @State private var connectionProtocol: ConnectionProtocol = .ssh
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var vncPort = "5900"
    @State private var rdpPort = "3389"
    @State private var useMosh = false
    @State private var username = ""
    @State private var authMethod: AuthMethod = .password
    @State private var password = ""
    @State private var selectedKeyID: UUID?
    @State private var environment: ServerEnvironment = .other
    @State private var selectedGroupId: UUID?
    @State private var newGroupName = ""
    @State private var showingNewGroup = false

    // MARK: - Test State

    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    // MARK: - Validation

    private var isValid: Bool {
        guard !name.isEmpty, !host.isEmpty else { return false }
        switch connectionProtocol {
        case .vnc:
            return Int(vncPort) != nil
        case .rdp:
            return !username.isEmpty && Int(rdpPort) != nil
        case .ssh:
            return !username.isEmpty && Int(port) != nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    protocolSection
                    connectionSection
                    authenticationSection
                    organisationSection
                    if connectionProtocol == .ssh {
                        testSection
                    }
                }
                .padding(16)
                .padding(.bottom, 60)
            }
            .background(KestrelColors.background)
            .navigationTitle(isEditing ? "Edit Server" : "Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(KestrelColors.textMuted)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveServer() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isValid ? KestrelColors.phosphorGreen : KestrelColors.textFaint)
                        .disabled(!isValid)
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KestrelColors.background)
        .onAppear {
            populateFromServer()
        }
        .sheet(isPresented: $showingPaywall) {
            KestrelPaywallView()
        }
    }

    // MARK: - Populate for Edit

    private func populateFromServer() {
        if let server = editingServer {
            connectionProtocol = server.connectionProtocol
            name = server.name
            host = server.host
            port = String(server.port)
            username = server.username
            authMethod = server.authMethod
            selectedKeyID = server.privateKeyID
            environment = server.environment
            // Resolve membership by id, falling back to the legacy name.
            if let gid = server.groupId {
                selectedGroupId = gid
            } else if let name = server.group, !name.isEmpty {
                selectedGroupId = groups.first(where: { $0.name == name })?.id
            } else {
                selectedGroupId = nil
            }
            useMosh = server.useMosh
            vncPort = String(server.vncPort ?? 5900)
            rdpPort = String(server.rdpPort ?? 3389)

            // Load password from the protocol-appropriate keychain entry
            switch connectionProtocol {
            case .vnc:
                password = (try? KeychainService.loadVNCPassword(for: server.id)) ?? ""
            case .rdp:
                password = (try? KeychainService.loadRDPPassword(for: server.id)) ?? ""
            case .ssh:
                if authMethod == .password {
                    password = (try? KeychainService.loadPassword(for: server.id)) ?? ""
                }
            }
        } else if let prefillHost, !prefillHost.isEmpty {
            host = prefillHost
            name = prefillHost
            username = UserDefaults.standard.string(forKey: "settings.defaultUsername") ?? "root"
        }
    }

    // MARK: - Protocol Section

    private var protocolSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Protocol")

            Menu {
                ForEach(ConnectionProtocol.allCases, id: \.self) { proto in
                    Button {
                        connectionProtocol = proto
                    } label: {
                        Label(proto.displayName, systemImage: proto.icon)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: connectionProtocol.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                    Text(connectionProtocol.displayName)
                        .font(KestrelFonts.mono(13))
                        .foregroundStyle(KestrelColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(KestrelColors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Connection")

            VStack(spacing: 10) {
                fieldRow(label: "Name") {
                    KestrelTextField(placeholder: "prod-web-01", text: $name)
                }

                fieldRow(label: "Host") {
                    KestrelTextField(placeholder: "192.168.1.10 or hostname", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                switch connectionProtocol {
                case .ssh:
                    HStack(spacing: 10) {
                        fieldRow(label: "Username") {
                            KestrelTextField(placeholder: "root", text: $username)
                                .textInputAutocapitalization(.never)
                        }

                        fieldRow(label: "Port") {
                            KestrelTextField(placeholder: "22", text: $port)
                                .keyboardType(.numberPad)
                                .frame(width: 80)
                        }
                    }
                case .vnc:
                    fieldRow(label: "VNC Port") {
                        KestrelTextField(placeholder: "5900", text: $vncPort)
                            .keyboardType(.numberPad)
                            .frame(width: 120)
                    }
                case .rdp:
                    HStack(spacing: 10) {
                        fieldRow(label: "Username") {
                            KestrelTextField(placeholder: "administrator", text: $username)
                                .textInputAutocapitalization(.never)
                        }

                        fieldRow(label: "RDP Port") {
                            KestrelTextField(placeholder: "3389", text: $rdpPort)
                                .keyboardType(.numberPad)
                                .frame(width: 80)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Authentication Section

    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Authentication")

            if connectionProtocol == .ssh {
                // Method picker (SSH only)
                HStack(spacing: 0) {
                    ForEach(AuthMethod.allCases, id: \.self) { method in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                authMethod = method
                            }
                        } label: {
                            Text(method.displayName)
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(
                                    authMethod == method
                                        ? KestrelColors.phosphorGreen
                                        : KestrelColors.textMuted
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    authMethod == method
                                        ? KestrelColors.phosphorGreenDim
                                        : Color.clear
                                )
                        }
                    }
                }
                .background(KestrelColors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                )
            }

            // For VNC/RDP, always show a password field.
            if connectionProtocol != .ssh {
                fieldRow(label: "Password") {
                    SecureField("Enter password", text: $password)
                        .font(KestrelFonts.mono(14))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(KestrelColors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                        )
                        .tint(KestrelColors.phosphorGreen)
                }
            } else {
                sshAuthFields
            }

            if connectionProtocol == .ssh {
                Toggle(isOn: $useMosh) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use MOSH")
                            .font(KestrelFonts.mono(12))
                            .foregroundStyle(KestrelColors.textPrimary)
                        Text("Requires mosh on client & server")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                }
                .tint(KestrelColors.phosphorGreen)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var sshAuthFields: some View {
        // Auth-specific fields for SSH
        switch authMethod {
        case .password:
            fieldRow(label: "Password") {
                    SecureField("Enter password", text: $password)
                        .font(KestrelFonts.mono(14))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(KestrelColors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                        )
                        .tint(KestrelColors.phosphorGreen)
                }

            case .privateKey:
                fieldRow(label: "Private Key") {
                    if savedKeys.isEmpty {
                        HStack {
                            Image(systemName: "key")
                                .foregroundStyle(KestrelColors.textFaint)
                            Text("No saved keys — add one in Key Manager")
                                .font(KestrelFonts.mono(12))
                                .foregroundStyle(KestrelColors.textFaint)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KestrelColors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                        )
                    } else {
                        VStack(spacing: 6) {
                            ForEach(savedKeys) { key in
                                keyRow(key)
                            }
                        }
                    }
                }

            case .sshAgent:
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(KestrelColors.blue)
                    Text("Uses the system SSH agent for authentication")
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KestrelColors.blue.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(KestrelColors.blue.opacity(0.15), lineWidth: 1)
                )
            }
    }

    private func keyRow(_ key: KeychainKey) -> some View {
        let isSelected = selectedKeyID == key.id

        return Button {
            selectedKeyID = key.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        isSelected
                            ? KestrelColors.phosphorGreen
                            : KestrelColors.textFaint
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(key.name)
                        .font(KestrelFonts.mono(13))
                        .foregroundStyle(KestrelColors.textPrimary)
                    Text(key.keyType.displayName)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textFaint)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
            }
            .padding(10)
            .background(
                isSelected ? KestrelColors.phosphorGreenDim : KestrelColors.backgroundCard
            )
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

    // MARK: - Organisation Section

    private var organisationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Organisation")

            // Environment picker
            fieldRow(label: "Environment") {
                HStack(spacing: 0) {
                    ForEach(ServerEnvironment.allCases, id: \.self) { env in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                environment = env
                            }
                        } label: {
                            Text(env.badge)
                                .font(KestrelFonts.mono(10))
                                .fontWeight(.bold)
                                .foregroundStyle(
                                    environment == env ? env.colour : KestrelColors.textFaint
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    environment == env ? env.colour.opacity(0.12) : Color.clear
                                )
                        }
                    }
                }
                .background(KestrelColors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                )
            }

            // Group picker
            fieldRow(label: "Group") {
                VStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            groupChip(id: nil, label: "None")
                            ForEach(groups) { group in
                                groupChip(id: group.id, label: group.name)
                            }
                            Button {
                                showingNewGroup.toggle()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11))
                                    .foregroundStyle(KestrelColors.textMuted)
                                    .frame(width: 32, height: 32)
                                    .background(KestrelColors.backgroundCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }

                    if showingNewGroup {
                        HStack(spacing: 8) {
                            KestrelTextField(placeholder: "New group name", text: $newGroupName)

                            Button {
                                createGroup()
                            } label: {
                                Text("Add")
                                    .font(KestrelFonts.mono(12))
                                    .foregroundStyle(KestrelColors.phosphorGreen)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(KestrelColors.phosphorGreenDim)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .disabled(newGroupName.isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func groupChip(id: UUID?, label: String) -> some View {
        let isSelected = selectedGroupId == id

        return Button {
            selectedGroupId = id
        } label: {
            Text(label)
                .font(KestrelFonts.mono(11))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(
                    isSelected ? KestrelColors.phosphorGreen : KestrelColors.textMuted
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected ? KestrelColors.phosphorGreenDim : KestrelColors.backgroundCard
                )
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

    // MARK: - Test Section

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Test")

            Button {
                testConnection()
            } label: {
                HStack(spacing: 10) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(KestrelColors.phosphorGreen)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14))
                    }

                    Text(isTesting ? "Testing…" : "Test Connection")
                        .font(KestrelFonts.mono(13))
                }
                .foregroundStyle(
                    isValid ? KestrelColors.phosphorGreen : KestrelColors.textFaint
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(KestrelColors.phosphorGreenDim)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                )
            }
            .disabled(!isValid || isTesting)

            if let result = testResult {
                testResultBanner(result)
            }
        }
    }

    @ViewBuilder
    private func testResultBanner(_ result: TestResult) -> some View {
        HStack(spacing: 8) {
            switch result {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(KestrelColors.phosphorGreen)
                Text("Connection successful")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.phosphorGreen)
            case .failure(let message):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(KestrelColors.red)
                Text(message)
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (testResult.isSuccess ? KestrelColors.phosphorGreen : KestrelColors.red)
                .opacity(0.08)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Helper Views

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(KestrelFonts.mono(10))
                .tracking(0.8)
                .foregroundStyle(KestrelColors.textFaint)
            content()
        }
    }

    // MARK: - Actions

    @State private var showingPaywall = false

    private func saveServer() {
        guard isValid else { return }

        // Check server limit for new servers (not edits)
        if editingServer == nil && revenueCat.isAtServerLimit(currentCount: allServers.count) {
            showingPaywall = true
            return
        }

        let vncPortNum = Int(vncPort)
        let rdpPortNum = Int(rdpPort)

        // Determine the effective port for the server row.
        let effectivePort: Int
        switch connectionProtocol {
        case .vnc: effectivePort = vncPortNum ?? 5900
        case .rdp: effectivePort = rdpPortNum ?? 3389
        case .ssh: effectivePort = Int(port) ?? 22
        }

        let effectiveUsername = connectionProtocol == .vnc ? "" : username
        let effectiveAuthMethod: AuthMethod = connectionProtocol == .ssh ? authMethod : .password

        if let server = editingServer {
            server.connectionType = connectionProtocol.rawValue
            server.name = name
            server.host = host
            server.port = effectivePort
            server.username = effectiveUsername
            server.authMethod = effectiveAuthMethod
            server.privateKeyID = (connectionProtocol == .ssh && authMethod == .privateKey) ? selectedKeyID : nil
            server.groupId = selectedGroupId
            server.group = nil
            server.environment = environment
            server.useMosh = connectionProtocol == .ssh ? useMosh : false
            server.vncPort = connectionProtocol == .vnc ? vncPortNum : nil
            server.rdpPort = connectionProtocol == .rdp ? rdpPortNum : nil

            savePassword(for: server.id)

            try? modelContext.save()
        } else {
            let server = SSHServer(
                name: name,
                host: host,
                port: effectivePort,
                username: effectiveUsername,
                authMethod: effectiveAuthMethod,
                privateKeyID: (connectionProtocol == .ssh && authMethod == .privateKey) ? selectedKeyID : nil,
                groupId: selectedGroupId,
                environment: environment,
                connectionType: connectionProtocol.rawValue,
                useMosh: connectionProtocol == .ssh ? useMosh : false,
                vncPort: connectionProtocol == .vnc ? vncPortNum : nil,
                rdpPort: connectionProtocol == .rdp ? rdpPortNum : nil
            )

            modelContext.insert(server)
            try? modelContext.save()

            savePassword(for: server.id)

            Analytics.capture("server_added", ["protocol": connectionProtocol.rawValue])
        }

        dismiss()
    }

    private func savePassword(for serverID: UUID) {
        guard !password.isEmpty else { return }
        switch connectionProtocol {
        case .vnc:
            try? KeychainService.saveVNCPassword(password, for: serverID)
        case .rdp:
            try? KeychainService.saveRDPPassword(password, for: serverID)
        case .ssh:
            if authMethod == .password {
                try? KeychainService.savePassword(password, for: serverID)
            }
        }
    }

    private func testConnection() {
        guard isValid, let portNum = Int(port) else { return }
        isTesting = true
        testResult = nil

        Task {
            let testID = editingServer?.id ?? UUID()

            // Temporarily save password for the test
            if authMethod == .password && !password.isEmpty {
                try? KeychainService.savePassword(password, for: testID)
            }

            let session = SSHSession(
                serverID: testID,
                host: host,
                port: portNum,
                username: username,
                authMethod: authMethod,
                privateKeyID: authMethod == .privateKey ? selectedKeyID : nil
            )

            do {
                try await session.connect()
                session.disconnect()

                withAnimation(.snappy) {
                    testResult = .success
                }
            } catch {
                let displayMessage: String
                if let sshError = error as? SSHSessionError {
                    displayMessage = sshError.errorDescription ?? error.localizedDescription
                } else {
                    displayMessage = error.localizedDescription
                }
                withAnimation(.snappy) {
                    testResult = .failure(displayMessage)
                }
            }

            // Clean up temp password (only if not editing an existing server)
            if editingServer == nil {
                try? KeychainService.deletePassword(for: testID)
            }
            isTesting = false
        }
    }

    private func createGroup() {
        guard !newGroupName.isEmpty else { return }

        let group = ServerGroup(
            name: newGroupName,
            orderIndex: groups.count
        )

        modelContext.insert(group)
        try? modelContext.save()

        selectedGroupId = group.id
        newGroupName = ""
        showingNewGroup = false
    }
}

// MARK: - AuthMethod Display Name

extension AuthMethod {
    var displayName: String {
        switch self {
        case .password: "Password"
        case .privateKey: "Private Key"
        case .sshAgent: "SSH Agent"
        }
    }
}

// MARK: - TestResult Helpers

extension Optional where Wrapped == AddServerSheet.TestResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
