//
//  CloudSyncView.swift
//  Kestrel
//
//  iOS Cloud Sync and account management view.
//

import SwiftUI

// MARK: - Cloud Sync View

struct CloudSyncView: View {
    @ObservedObject private var supabaseService = SupabaseService.shared
    @State private var revenueCat = KestrelRevenueCatService.shared

    // Sign in form state
    @State private var signInEmail = ""
    @State private var signInPassword = ""
    @State private var isSigningIn = false
    @State private var isSigningUp = false
    @State private var authError: String?
    @State private var showConfirmEmail = false

    // Alerts
    @State private var showingSignOut = false
    @State private var showingDeleteAccount = false
    @State private var deleteConfirmText = ""
    @State private var showingExportShare = false
    @State private var exportData: Data?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if supabaseService.isAuthenticated {
                    accountSection
                    syncStatusCard
                    syncSummaryGrid
                    connectedDevicesSection
                    dataManagementSection
                } else {
                    signInSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(KestrelColors.background)
        .navigationTitle("Kestrel Cloud")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(KestrelColors.background, for: .navigationBar)
        .onAppear {
            if supabaseService.isAuthenticated {
                Task { try? await supabaseService.fetchDevices() }
            }
        }
    }

    // MARK: - Sign In Section

    private var signInSection: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            Image(systemName: "cloud")
                .font(.system(size: 48))
                .foregroundStyle(KestrelColors.phosphorGreen)

            Text("Kestrel Cloud")
                .font(KestrelFonts.display(22, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)

            Text("Sign in to sync servers and settings across devices.")
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("Email", text: $signInEmail)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .tint(KestrelColors.phosphorGreen)

                SecureField("Password", text: $signInPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .tint(KestrelColors.phosphorGreen)

                if let authError {
                    Text(authError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if showConfirmEmail {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.badge")
                            .foregroundStyle(KestrelColors.phosphorGreen)
                        Text("Check your email to confirm your account, then sign in.")
                            .font(.caption)
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        performSignIn()
                    } label: {
                        HStack(spacing: 4) {
                            if isSigningIn { ProgressView().scaleEffect(0.5).tint(.white) }
                            Text("Sign In")
                        }
                        .font(KestrelFonts.monoBold(13))
                        .foregroundStyle(KestrelColors.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(KestrelColors.phosphorGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(signInEmail.isEmpty || signInPassword.isEmpty || isSigningIn || isSigningUp)

                    Button {
                        performSignUp()
                    } label: {
                        HStack(spacing: 4) {
                            if isSigningUp { ProgressView().scaleEffect(0.5).tint(KestrelColors.phosphorGreen) }
                            Text("Create Account")
                        }
                        .font(KestrelFonts.monoBold(13))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(KestrelColors.phosphorGreenDim)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(KestrelColors.phosphorGreen.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .disabled(signInEmail.isEmpty || signInPassword.isEmpty || isSigningIn || isSigningUp)
                }
                .padding(.top, 4)
            }

            // Encryption badge
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                Text("End-to-end encrypted · AES-256-GCM")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func performSignIn() {
        isSigningIn = true
        authError = nil
        Task {
            do {
                try await supabaseService.signIn(email: signInEmail, password: signInPassword)
                try? await supabaseService.registerDevice()
                try? await supabaseService.fetchDevices()
            } catch {
                authError = error.localizedDescription
            }
            isSigningIn = false
        }
    }

    private func performSignUp() {
        isSigningUp = true
        authError = nil
        showConfirmEmail = false
        Task {
            do {
                let needsConfirmation = try await supabaseService.signUp(email: signInEmail, password: signInPassword)
                if needsConfirmation {
                    showConfirmEmail = true
                } else {
                    try? await supabaseService.registerDevice()
                }
            } catch {
                authError = error.localizedDescription
            }
            isSigningUp = false
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Avatar
                Circle()
                    .fill(KestrelColors.phosphorGreenDim)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(avatarInitial)
                            .font(KestrelFonts.display(20, weight: .bold))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(supabaseService.userEmail ?? "Not signed in")
                        .font(KestrelFonts.monoBold(13))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(revenueCat.isProOrBundle ? "KESTREL PRO" : "FREE")
                            .font(KestrelFonts.mono(9))
                            .fontWeight(.bold)
                            .tracking(1.0)
                            .foregroundStyle(
                                revenueCat.isProOrBundle ? KestrelColors.phosphorGreen : KestrelColors.textFaint
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                revenueCat.isProOrBundle ? KestrelColors.phosphorGreenDim : KestrelColors.backgroundCard
                            )
                            .clipShape(Capsule())

                        if revenueCat.hasSuiteBundle {
                            Text("SUITE")
                                .font(KestrelFonts.mono(8))
                                .fontWeight(.bold)
                                .foregroundStyle(KestrelColors.background)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(KestrelColors.amber)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                Button("Sign Out") {
                    showingSignOut = true
                }
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.red)
            }
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
        .confirmationDialog("Sign Out", isPresented: $showingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { try? await supabaseService.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to sign in again to sync data.")
        }
    }

    private var avatarInitial: String {
        if let email = supabaseService.userEmail, let first = email.first {
            return String(first).uppercased()
        }
        return "?"
    }

    // MARK: - Sync Status Card

    private var syncStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                syncStatusIndicator

                VStack(alignment: .leading, spacing: 2) {
                    Text(syncStatusText)
                        .font(KestrelFonts.monoBold(13))
                        .foregroundStyle(syncStatusColor)

                    if let lastSync = supabaseService.lastSyncDate {
                        Text("Last sync: \(lastSync.formatted(.relative(presentation: .named)))")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                }

                Spacer()

                Button {
                    Task { try? await supabaseService.syncNow() }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
                .disabled(supabaseService.syncState == .syncing)
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                Text("End-to-end encrypted")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(KestrelColors.phosphorGreenDim)
            .clipShape(Capsule())
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var syncStatusIndicator: some View {
        switch supabaseService.syncState {
        case .synced:
            Circle()
                .fill(KestrelColors.phosphorGreen)
                .frame(width: 10, height: 10)
                .shadow(color: KestrelColors.phosphorGreen.opacity(0.5), radius: 4)
        case .syncing:
            ProgressView()
                .scaleEffect(0.6)
                .tint(KestrelColors.phosphorGreen)
        case .error:
            Circle()
                .fill(KestrelColors.red)
                .frame(width: 10, height: 10)
        case .idle:
            Circle()
                .fill(KestrelColors.textFaint)
                .frame(width: 10, height: 10)
        }
    }

    private var syncStatusText: String {
        switch supabaseService.syncState {
        case .synced: "SYNCED"
        case .syncing: "SYNCING..."
        case .error(let msg): msg
        case .idle: "NOT SYNCED"
        }
    }

    private var syncStatusColor: Color {
        switch supabaseService.syncState {
        case .synced: KestrelColors.phosphorGreen
        case .syncing: KestrelColors.amber
        case .error: KestrelColors.red
        case .idle: KestrelColors.textFaint
        }
    }

    // MARK: - Sync Summary Grid

    private var syncSummaryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            syncStatCard("Servers", "\(supabaseService.syncedServerCount)", "server.rack", KestrelColors.phosphorGreen)
            syncStatCard("Commands", "\(supabaseService.syncedCommandCount)", "terminal", KestrelColors.blue)
            syncStatCard("SSH Keys", "\(supabaseService.syncedKeyCount)", "key", KestrelColors.amber)
            syncStatCard("Sessions", "\(supabaseService.syncedSessionCount)", "clock", KestrelColors.textMuted)
        }
    }

    private func syncStatCard(_ label: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
            Text(value)
                .font(KestrelFonts.display(18, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)
            Text(label.uppercased())
                .font(KestrelFonts.mono(7))
                .tracking(0.8)
                .foregroundStyle(KestrelColors.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Connected Devices

    private var connectedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONNECTED DEVICES")
                .font(KestrelFonts.mono(9))
                .tracking(1.2)
                .foregroundStyle(KestrelColors.textFaint)

            if supabaseService.connectedDevices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone")
                        .font(.system(size: 14))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("This Device")
                            .font(KestrelFonts.mono(12))
                            .foregroundStyle(KestrelColors.textPrimary)
                        Text("Active now")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                Text("Sign in on other devices to sync")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            } else {
                ForEach(supabaseService.connectedDevices) { device in
                    deviceRow(device)
                }
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

    private func deviceRow(_ device: ConnectedDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(device.hasActiveSessions ? KestrelColors.phosphorGreen : KestrelColors.textMuted)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textPrimary)

                Text(device.lastActive.formatted(.relative(presentation: .named)))
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            Spacer()

            if device.hasActiveSessions {
                Text("Active")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(KestrelColors.phosphorGreenDim)
                    .clipShape(Capsule())
            }

            Button {
                Task { try? await supabaseService.removeDevice(device) }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .opacity(0.5)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Management

    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DATA & PRIVACY")
                .font(KestrelFonts.mono(9))
                .tracking(1.2)
                .foregroundStyle(KestrelColors.textFaint)

            // Sync log
            if !supabaseService.syncLog.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT ACTIVITY")
                        .font(KestrelFonts.mono(8))
                        .tracking(1.0)
                        .foregroundStyle(KestrelColors.textFaint)

                    ForEach(supabaseService.syncLog.prefix(5)) { entry in
                        HStack {
                            Text(entry.action)
                                .font(KestrelFonts.mono(10))
                                .foregroundStyle(KestrelColors.textMuted)
                            Spacer()
                            Text(entry.timestamp.formatted(.dateTime.hour().minute()))
                                .font(KestrelFonts.mono(9))
                                .foregroundStyle(KestrelColors.textFaint)
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

            // Export
            Button {
                Task {
                    exportData = try? await supabaseService.exportAllData()
                    if exportData != nil { showingExportShare = true }
                }
            } label: {
                actionRow(icon: "arrow.down.doc", text: "Export All Data", color: KestrelColors.textMuted)
            }
            .sheet(isPresented: $showingExportShare) {
                if let data = exportData {
                    ShareSheet(items: [data])
                }
            }

            // Clear cache
            Button {
                supabaseService.clearLocalCache()
            } label: {
                actionRow(icon: "trash", text: "Clear Local Cache", color: KestrelColors.textMuted)
            }

            // Delete account
            Button {
                showingDeleteAccount = true
            } label: {
                actionRow(icon: "person.crop.circle.badge.minus", text: "Delete Account", color: KestrelColors.red)
            }
            .alert("Delete Account", isPresented: $showingDeleteAccount) {
                TextField("Type DELETE to confirm", text: $deleteConfirmText)
                Button("Delete Account", role: .destructive) {
                    guard deleteConfirmText == "DELETE" else { return }
                    Task { try? await supabaseService.deleteAccount() }
                }
                Button("Cancel", role: .cancel) { deleteConfirmText = "" }
            } message: {
                Text("This permanently deletes your account and all synced data. Type DELETE to confirm.")
            }
        }
    }

    private func actionRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(KestrelColors.textFaint)
        }
        .padding(12)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Share Sheet (UIKit wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
