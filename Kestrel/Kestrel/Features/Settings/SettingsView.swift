//
//  SettingsView.swift
//  Kestrel
//
//  Full app settings with General, Terminal, AI, Recording, OSPREY,
//  Subscription, Security, and About sections.
//

import SwiftUI
import SwiftData
import LocalAuthentication

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var revenueCat = KestrelRevenueCatService.shared
    @State private var ospreyBridge = OspreyBridgeService.shared
    @State private var termPrefs = TerminalPreferences.shared
    @ObservedObject private var supabaseService = SupabaseService.shared
    @State private var showingPaywall = false

    // General
    @AppStorage("settings.defaultPort") private var defaultPort = 22
    @AppStorage("settings.connectionTimeout") private var connectionTimeout = 30
    @AppStorage("settings.keepaliveInterval") private var keepaliveInterval = 30.0
    @AppStorage("settings.autoReconnect") private var autoReconnect = true
    @AppStorage("settings.autoReconnectRetries") private var autoReconnectRetries = 3
    @AppStorage("settings.defaultUsername") private var defaultUsername = ""

    // Terminal
    @AppStorage("settings.cursorStyle") private var cursorStyle = "block"
    @AppStorage("settings.scrollbackLines") private var scrollbackLines = 10000
    @AppStorage("settings.enableHaptics") private var enableHaptics = true

    // AI
    @AppStorage("settings.aiContextLines") private var aiContextLines = 20.0
    @AppStorage("settings.aiAutoSuggest") private var aiAutoSuggest = false
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var isTestingAPI = false
    @State private var apiTestResult: String?

    // Recording
    @AppStorage("settings.defaultRecordingOn") private var defaultRecordingOn = false
    @AppStorage("settings.autoRecordProd") private var autoRecordProd = true
    @AppStorage("settings.recordingLimitMB") private var recordingLimitMB = 500
    @State private var showingClearRecordings = false

    // Security
    @AppStorage("settings.requireBiometric") private var requireBiometric = false
    @AppStorage("settings.lockAfterBackground") private var lockAfterBackground = "never"
    @State private var showingClearCredentials = false

    // OSPREY
    @AppStorage("settings.sharedVaultEnabled") private var sharedVaultEnabled = true
    @State private var showingClearSharedData = false

    @AppStorage("app.theme") private var selectedTheme = "Phosphor"
    @AppStorage("app.font") private var selectedFont = "jetbrains-mono"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    proStatusCard
                    appearanceSection
                    fontSection
                    cloudSyncSection
                    generalSection
                    terminalSection
                    aiSection
                    recordingSection
                    ospreySection
                    subscriptionSection
                    securitySection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 60)
            }
            .background(KestrelColors.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .sheet(isPresented: $showingPaywall) {
            KestrelPaywallView()
        }
        .onAppear {
            apiKey = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
        }
    }

    // MARK: - Pro Status Card

    private var proStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if revenueCat.isProOrBundle {
                HStack(spacing: 8) {
                    Text("◈")
                        .font(.system(size: 18))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Kestrel Pro")
                                .font(KestrelFonts.monoBold(14))
                                .foregroundStyle(KestrelColors.textPrimary)
                            if revenueCat.hasSuiteBundle {
                                Text("SUITE")
                                    .font(KestrelFonts.mono(8))
                                    .fontWeight(.bold)
                                    .foregroundStyle(KestrelColors.background)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(KestrelColors.amber)
                                    .clipShape(Capsule())
                            }
                        }
                        Text("All features unlocked")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
            } else {
                HStack(spacing: 8) {
                    Text("◈")
                        .font(.system(size: 18))
                        .foregroundStyle(KestrelColors.textFaint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kestrel Free")
                            .font(KestrelFonts.monoBold(14))
                            .foregroundStyle(KestrelColors.textPrimary)
                        Text("\(KestrelFreeLimits.maxServers) servers · \(KestrelFreeLimits.maxKeys) keys · Limited features")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                    Spacer()
                }

                Button {
                    showingPaywall = true
                } label: {
                    Text("Upgrade to Pro")
                        .font(KestrelFonts.monoBold(12))
                        .foregroundStyle(KestrelColors.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(KestrelColors.phosphorGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    revenueCat.isProOrBundle ? KestrelColors.cardBorderGreen : KestrelColors.cardBorder,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Cloud Sync

    private var cloudSyncSection: some View {
        settingsSection("Kestrel Cloud") {
            NavigationLink {
                CloudSyncView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "cloud")
                        .font(.system(size: 14))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(supabaseService.isAuthenticated ? "Signed in" : "Sign in to sync")
                            .font(KestrelFonts.mono(13))
                            .foregroundStyle(KestrelColors.textPrimary)
                        Text(supabaseService.isAuthenticated
                             ? (supabaseService.userEmail ?? "")
                             : "Sync servers across devices")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textMuted)
                            .lineLimit(1)
                    }

                    Spacer()

                    if supabaseService.isAuthenticated {
                        Circle()
                            .fill(supabaseService.syncState == .synced
                                  ? KestrelColors.phosphorGreen
                                  : KestrelColors.textFaint)
                            .frame(width: 8, height: 8)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .padding(12)
                .background(KestrelColors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        settingsSection("Appearance") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AppThemeID.allCases) { themeID in
                        Button {
                            selectedTheme = themeID.rawValue
                            ThemeManager.shared.currentThemeID = themeID
                        } label: {
                            VStack(spacing: 8) {
                                // Theme preview swatch
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(themeID.theme.background)
                                        .frame(width: 64, height: 48)

                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(themeID.theme.accent)
                                            .frame(width: 10, height: 10)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(themeID.theme.accent.opacity(0.4))
                                            .frame(width: 28, height: 4)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(themeID.theme.textFaint)
                                            .frame(width: 20, height: 3)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(
                                            selectedTheme == themeID.rawValue
                                                ? themeID.theme.accent
                                                : themeID.theme.cardBorder,
                                            lineWidth: selectedTheme == themeID.rawValue ? 2 : 1
                                        )
                                )

                                // Label
                                Text(themeID.rawValue)
                                    .font(KestrelFonts.mono(10))
                                    .foregroundStyle(
                                        selectedTheme == themeID.rawValue
                                            ? KestrelColors.textPrimary
                                            : KestrelColors.textMuted
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - App Font

    private var fontSection: some View {
        settingsSection("App Font") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AppFontID.allCases) { fontID in
                        Button {
                            selectedFont = fontID.rawValue
                            FontManager.shared.currentFontID = fontID
                            // Sync the choice so it follows the user to Mac/Windows.
                            Task { await SupabaseService.shared.saveUserSettings(uiFont: fontID.rawValue) }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(KestrelColors.backgroundCard)
                                        .frame(width: 64, height: 48)
                                    Text("Ag")
                                        .font(KestrelFonts.fontForID(fontID, size: 22, weight: .semibold))
                                        .foregroundStyle(KestrelColors.textPrimary)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(
                                            selectedFont == fontID.rawValue
                                                ? KestrelColors.phosphorGreen
                                                : KestrelColors.cardBorder,
                                            lineWidth: selectedFont == fontID.rawValue ? 2 : 1
                                        )
                                )

                                Text(fontID.label)
                                    .font(KestrelFonts.mono(10))
                                    .foregroundStyle(
                                        selectedFont == fontID.rawValue
                                            ? KestrelColors.textPrimary
                                            : KestrelColors.textMuted
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        settingsSection("General") {
            settingsRow {
                HStack {
                    settingsLabel(icon: "network", text: "Default SSH Port")
                    Spacer()
                    TextField("22", value: $defaultPort, format: .number)
                        .font(KestrelFonts.mono(13))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
            }

            settingsRow {
                HStack {
                    settingsLabel(icon: "clock", text: "Connection Timeout")
                    Spacer()
                    Picker("", selection: $connectionTimeout) {
                        Text("10s").tag(10)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                    }
                    .pickerStyle(.menu)
                    .tint(KestrelColors.phosphorGreen)
                }
            }

            settingsRow {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        settingsLabel(icon: "heart.fill", text: "Keepalive Interval")
                        Spacer()
                        Text("\(Int(keepaliveInterval))s")
                            .font(KestrelFonts.mono(12))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                    }
                    Slider(value: $keepaliveInterval, in: 15...120, step: 5)
                        .tint(KestrelColors.phosphorGreen)
                }
            }

            settingsRow {
                HStack {
                    settingsLabel(icon: "arrow.clockwise", text: "Auto-Reconnect")
                    Spacer()
                    Toggle("", isOn: $autoReconnect)
                        .tint(KestrelColors.phosphorGreen)
                        .labelsHidden()
                }
            }

            if autoReconnect {
                settingsRow {
                    HStack {
                        settingsLabel(icon: "repeat", text: "Retry Count")
                        Spacer()
                        Picker("", selection: $autoReconnectRetries) {
                            Text("1").tag(1)
                            Text("3").tag(3)
                            Text("5").tag(5)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                }
            }

            settingsRow {
                HStack {
                    settingsLabel(icon: "person", text: "Default Username")
                    Spacer()
                    TextField("root", text: $defaultUsername)
                        .font(KestrelFonts.mono(13))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(width: 100)
                }
            }
        }
    }

    // MARK: - Terminal

    private var terminalSection: some View {
        settingsSection("Terminal") {
            settingsRow {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        settingsLabel(icon: "textformat.size", text: "Font Size")
                        Spacer()
                        Text("\(Int(termPrefs.fontSize)) pt")
                            .font(KestrelFonts.mono(12))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                    }
                    Slider(value: $termPrefs.fontSize, in: 10...18, step: 1)
                        .tint(KestrelColors.phosphorGreen)

                    // Live preview
                    Text("user@server:~$ ls -la")
                        .font(.system(size: termPrefs.fontSize, design: .monospaced))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                        )
                }
            }

            settingsRow {
                HStack {
                    settingsLabel(icon: "paintpalette", text: "Colour Scheme")
                    Spacer()
                    Picker("", selection: $termPrefs.colorScheme) {
                        ForEach(TerminalColorScheme.allCases, id: \.self) { scheme in
                            Text(scheme.rawValue).tag(scheme)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(KestrelColors.phosphorGreen)
                }
            }

            settingsRow {
                HStack {
                    settingsLabel(icon: "cursor.rays", text: "Cursor Style")
                    Spacer()
                    Picker("", selection: $cursorStyle) {
                        Text("Block").tag("block")
                        Text("Underline").tag("underline")
                        Text("Bar").tag("bar")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }

            settingsRow {
                HStack {
                    settingsLabel(icon: "scroll", text: "Scrollback Lines")
                    Spacer()
                    Picker("", selection: $scrollbackLines) {
                        Text("1,000").tag(1000)
                        Text("5,000").tag(5000)
                        Text("10,000").tag(10000)
                        Text("Unlimited").tag(0)
                    }
                    .pickerStyle(.menu)
                    .tint(KestrelColors.phosphorGreen)
                }
            }

            settingsRow {
                HStack {
                    settingsLabel(icon: "iphone.radiowaves.left.and.right", text: "Haptic Feedback")
                    Spacer()
                    Toggle("", isOn: $enableHaptics)
                        .tint(KestrelColors.phosphorGreen)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: - AI Assistant

    private var aiSection: some View {
        settingsSection("AI Assistant") {
            settingsRow {
                VStack(alignment: .leading, spacing: 8) {
                    settingsLabel(icon: "key", text: "API Key")

                    HStack {
                        Group {
                            if showAPIKey {
                                TextField("sk-ant-...", text: $apiKey)
                            } else {
                                SecureField("sk-ant-...", text: $apiKey)
                            }
                        }
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(KestrelColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .tint(KestrelColors.phosphorGreen)
                        .onChange(of: apiKey) { _, val in
                            UserDefaults.standard.set(val, forKey: "claude_api_key")
                        }

                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .font(.system(size: 14))
                                .foregroundStyle(KestrelColors.textMuted)
                        }
                    }

                    // Test button
                    HStack {
                        Button {
                            testAPIConnection()
                        } label: {
                            HStack(spacing: 4) {
                                if isTestingAPI {
                                    ProgressView().scaleEffect(0.6).tint(KestrelColors.phosphorGreen)
                                }
                                Text(isTestingAPI ? "Testing..." : "Test Connection")
                                    .font(KestrelFonts.mono(11))
                            }
                            .foregroundStyle(KestrelColors.phosphorGreen)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(KestrelColors.phosphorGreenDim)
                            .clipShape(Capsule())
                        }
                        .disabled(apiKey.isEmpty || isTestingAPI)

                        if let result = apiTestResult {
                            Text(result)
                                .font(KestrelFonts.mono(10))
                                .foregroundStyle(result.contains("OK") ? KestrelColors.phosphorGreen : KestrelColors.red)
                        }
                    }
                }
            }

            settingsRow {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        settingsLabel(icon: "text.line.last.and.arrowtriangle.forward", text: "Context Lines")
                        Spacer()
                        Text("\(Int(aiContextLines))")
                            .font(KestrelFonts.mono(12))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                    }
                    Slider(value: $aiContextLines, in: 10...50, step: 5)
                        .tint(KestrelColors.phosphorGreen)
                }
            }

            settingsRow {
                HStack {
                    settingsLabel(icon: "exclamationmark.bubble", text: "Auto-Suggest on Error")
                    Spacer()
                    Toggle("", isOn: $aiAutoSuggest)
                        .tint(KestrelColors.phosphorGreen)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: - Session Recording

    private var recordingSection: some View {
        settingsSection("Session Recording") {
            settingsRow {
                HStack {
                    settingsLabel(icon: "record.circle", text: "Record by Default")
                    Spacer()
                    Toggle("", isOn: $defaultRecordingOn)
                        .tint(KestrelColors.phosphorGreen)
                        .labelsHidden()
                }
            }

            settingsRow {
                HStack {
                    settingsLabel(icon: "exclamationmark.shield", text: "Auto-Record Production")
                    Spacer()
                    Toggle("", isOn: $autoRecordProd)
                        .tint(KestrelColors.phosphorGreen)
                        .labelsHidden()
                }
            }

            settingsRow {
                HStack {
                    settingsLabel(icon: "internaldrive", text: "Storage Limit")
                    Spacer()
                    Picker("", selection: $recordingLimitMB) {
                        Text("100 MB").tag(100)
                        Text("500 MB").tag(500)
                        Text("1 GB").tag(1000)
                    }
                    .pickerStyle(.menu)
                    .tint(KestrelColors.phosphorGreen)
                }
            }

            NavigationLink {
                HistoryView()
            } label: {
                settingsActionRow(icon: "clock.arrow.circlepath", text: "View Recordings & History", color: KestrelColors.phosphorGreen)
            }

            Button {
                showingClearRecordings = true
            } label: {
                settingsActionRow(icon: "trash", text: "Clear All Recordings", color: KestrelColors.red)
            }
            .confirmationDialog("Clear Recordings", isPresented: $showingClearRecordings, titleVisibility: .visible) {
                Button("Clear All", role: .destructive) { clearRecordings() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all session recordings.")
            }
        }
    }

    // MARK: - OSPREY Integration

    private var ospreySection: some View {
        settingsSection("OSPREY Integration") {
            settingsRow {
                HStack {
                    settingsLabel(icon: "antenna.radiowaves.left.and.right", text: "OSPREY Status")
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ospreyBridge.hasOspreyInstalled ? KestrelColors.phosphorGreen : KestrelColors.textFaint)
                            .frame(width: 6, height: 6)
                        Text(ospreyBridge.hasOspreyInstalled ? "Installed" : "Not Installed")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(ospreyBridge.hasOspreyInstalled ? KestrelColors.phosphorGreen : KestrelColors.textMuted)
                    }
                }
            }

            settingsRow {
                HStack {
                    settingsLabel(icon: "lock.shield", text: "Shared Vault")
                    Spacer()
                    Toggle("", isOn: $sharedVaultEnabled)
                        .tint(KestrelColors.phosphorGreen)
                        .labelsHidden()
                }
            }

            NavigationLink {
                OspreyBridgeView()
            } label: {
                settingsActionRow(icon: "arrow.right.circle", text: "OSPREY Bridge Details", color: KestrelColors.blue)
            }

            Button {
                showingClearSharedData = true
            } label: {
                settingsActionRow(icon: "xmark.bin", text: "Clear Shared Data", color: KestrelColors.amber)
            }
            .confirmationDialog("Clear Shared Data", isPresented: $showingClearSharedData, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    UserDefaults(suiteName: kestrelAppGroup)?.removePersistentDomain(forName: kestrelAppGroup)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove data shared between KESTREL and OSPREY.")
            }
        }
    }

    // MARK: - Suite & Subscription

    private var subscriptionSection: some View {
        settingsSection("Suite & Subscription") {
            settingsRow {
                HStack {
                    settingsLabel(icon: "creditcard", text: "Current Plan")
                    Spacer()
                    Text(revenueCat.hasSuiteBundle ? "Suite Bundle" : revenueCat.isProOrBundle ? "Pro" : "Free")
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(revenueCat.isProOrBundle ? KestrelColors.phosphorGreen : KestrelColors.textMuted)
                }
            }

            Button {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            } label: {
                settingsActionRow(icon: "arrow.up.right", text: "Manage Subscription", color: KestrelColors.textMuted)
            }

            Button {
                Task { _ = await revenueCat.restorePurchases() }
            } label: {
                settingsActionRow(icon: "arrow.clockwise", text: "Restore Purchases", color: KestrelColors.textMuted)
            }

            if !revenueCat.hasSuiteBundle {
                Button {
                    showingPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("OSPREY + KESTREL Suite")
                                .font(KestrelFonts.monoBold(12))
                            Text("Unlock both apps together")
                                .font(KestrelFonts.mono(10))
                                .foregroundStyle(KestrelColors.amber.opacity(0.7))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(KestrelColors.amber)
                    .padding(12)
                    .background(KestrelColors.amber.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(KestrelColors.amber.opacity(0.2), lineWidth: 1)
                    )
                }
            }

        }
    }

    // MARK: - Security

    private var securitySection: some View {
        settingsSection("Security") {
            settingsRow {
                HStack {
                    settingsLabel(icon: "faceid", text: "Require Face ID / Touch ID")
                    Spacer()
                    Toggle("", isOn: $requireBiometric)
                        .tint(KestrelColors.phosphorGreen)
                        .labelsHidden()
                }
            }

            if requireBiometric {
                settingsRow {
                    HStack {
                        settingsLabel(icon: "lock.clock", text: "Lock After Background")
                        Spacer()
                        Picker("", selection: $lockAfterBackground) {
                            Text("Immediately").tag("immediately")
                            Text("1 min").tag("1min")
                            Text("5 min").tag("5min")
                            Text("Never").tag("never")
                        }
                        .pickerStyle(.menu)
                        .tint(KestrelColors.phosphorGreen)
                    }
                }
            }

            Button {
                showingClearCredentials = true
            } label: {
                settingsActionRow(icon: "trash", text: "Clear All Credentials", color: KestrelColors.red)
            }
            .confirmationDialog("Clear All Credentials", isPresented: $showingClearCredentials, titleVisibility: .visible) {
                Button("Clear Everything", role: .destructive) {
                    clearAllCredentials()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete ALL saved passwords and SSH keys from the Keychain. This cannot be undone.")
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsSection("About") {
            settingsRow {
                HStack {
                    settingsLabel(icon: "info.circle", text: "Version")
                    Spacer()
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1")")
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.textMuted)
                }
            }

            Link(destination: URL(string: "https://apps.apple.com/app/id6764020106?action=write-review")!) {
                settingsActionRow(icon: "star", text: "Rate Kestrel on App Store", color: KestrelColors.amber)
            }

            Link(destination: URL(string: "https://testflight.apple.com/join/XXXXXX")!) {
                settingsActionRow(icon: "hammer", text: "Join Beta (TestFlight)", color: KestrelColors.blue)
            }

            Link(destination: URL(string: "https://getosprey.app/terms")!) {
                settingsActionRow(icon: "doc.text", text: "Terms of Use", color: KestrelColors.textMuted)
            }

            Link(destination: URL(string: "https://getosprey.app/privacy")!) {
                settingsActionRow(icon: "hand.raised", text: "Privacy Policy", color: KestrelColors.textMuted)
            }

            NavigationLink {
                AcknowledgementsView()
            } label: {
                settingsActionRow(icon: "heart", text: "Open Source Acknowledgements", color: KestrelColors.textMuted)
            }

            // Suite branding
            suiteCard
        }
    }

    // MARK: - Suite Branding Card

    private var suiteCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(KestrelColors.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16))
                    .foregroundStyle(KestrelColors.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("OSPREY")
                    .font(KestrelFonts.monoBold(13))
                    .foregroundStyle(KestrelColors.textPrimary)
                Text("Network Intelligence")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textMuted)
            }

            Spacer()

            if ospreyBridge.hasOspreyInstalled {
                Button {
                    if let url = URL(string: "osprey://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(KestrelColors.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            } else {
                Text("Get it →")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.blue)
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [KestrelColors.blue.opacity(0.04), KestrelColors.phosphorGreen.opacity(0.02)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    LinearGradient(
                        colors: [KestrelColors.blue.opacity(0.2), KestrelColors.phosphorGreen.opacity(0.1)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Actions

    private func testAPIConnection() {
        isTestingAPI = true
        apiTestResult = nil

        Task {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let body: [String: Any] = [
                "model": "claude-sonnet-4-20250514",
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                apiTestResult = code == 200 ? "OK — Connected" : "Error (HTTP \(code))"
            } catch {
                apiTestResult = "Failed"
            }
            isTestingAPI = false
        }
    }

    @MainActor
    private func clearRecordings() {
        do {
            try modelContext.delete(model: SessionLog.self)
            try modelContext.save()
        } catch {
            print("[Settings] Failed to clear recordings: \(error)")
        }
    }

    private func clearAllCredentials() {
        // Delete all passwords
        let passwordQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.kestrel.ssh-passwords"
        ]
        SecItemDelete(passwordQuery as CFDictionary)

        // Delete all SSH keys
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.kestrel.ssh-keys"
        ]
        SecItemDelete(keyQuery as CFDictionary)
    }

    // MARK: - Reusable Components

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            content()
        }
    }

    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
            )
    }

    private func settingsLabel(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(KestrelColors.textMuted)
                .frame(width: 18)
            Text(text)
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textPrimary)
        }
    }

    private func settingsActionRow(icon: String, text: String, color: Color) -> some View {
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

// MARK: - Acknowledgements View

struct AcknowledgementsView: View {
    private let libraries: [(String, String, String)] = [
        ("Citadel", "SSH client library", "MIT License"),
        ("SwiftTerm", "Terminal emulator", "MIT License"),
        ("RevenueCat", "In-app purchases", "MIT License"),
        ("SwiftNIO", "Networking framework", "Apache 2.0"),
        ("Swift Crypto", "Cryptography", "Apache 2.0"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(libraries, id: \.0) { name, desc, license in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(KestrelFonts.monoBold(13))
                            .foregroundStyle(KestrelColors.textPrimary)
                        Text(desc)
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textMuted)
                        Text(license)
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KestrelColors.backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                    )
                }
            }
            .padding(16)
        }
        .background(KestrelColors.background)
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(KestrelColors.background, for: .navigationBar)
    }
}
