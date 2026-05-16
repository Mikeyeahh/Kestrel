//
//  LaunchScreen.swift
//  Kestrel
//
//  Animated launch screen, Face ID lock gate, and deep link routing.
//

import SwiftUI
import SwiftData
import LocalAuthentication

// MARK: - Launch Screen View

struct LaunchScreenView: View {
    @State private var cursorVisible = true
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScanlineOverlay()
                .opacity(0.02)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("◈ KESTREL")
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(Color(red: 0, green: 1, blue: 0.612))

                Text("█")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundStyle(Color(red: 0, green: 1, blue: 0.612))
                    .opacity(cursorVisible ? 1.0 : 0.0)

                Text("SSH · MONITOR · MANAGE")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color(red: 0, green: 1, blue: 0.612).opacity(0.3))
                    .padding(.top, 8)
            }
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorVisible.toggle()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.4)) {
                    opacity = 0
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Face ID Lock View

struct BiometricLockView: View {
    let onUnlocked: () -> Void

    @State private var authFailed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "faceid")
                    .font(.system(size: 48))
                    .foregroundStyle(KestrelColors.phosphorGreen)

                Text("Kestrel is Locked")
                    .font(KestrelFonts.display(20, weight: .bold))
                    .foregroundStyle(KestrelColors.textPrimary)

                if authFailed {
                    Text("Authentication failed")
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.red)
                }

                Button {
                    authenticate()
                } label: {
                    Text("Unlock")
                        .font(KestrelFonts.monoBold(13))
                        .foregroundStyle(KestrelColors.background)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(KestrelColors.phosphorGreen)
                        .clipShape(Capsule())
                }
            }
        }
        .onAppear {
            authenticate()
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // No biometrics available — fall through
            onUnlocked()
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock Kestrel to access your servers"
        ) { success, _ in
            DispatchQueue.main.async {
                if success {
                    onUnlocked()
                } else {
                    authFailed = true
                }
            }
        }
    }
}

// MARK: - Root View

/// Wrapper that owns the sync lifecycle outside the theme `.id()` refresh.
struct RootSyncWrapper: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var supabaseService: SupabaseService
    @State private var syncRepo: ServerRepository?

    var body: some View {
        RootView()
            .task {
                // Wait up to 5 seconds for Supabase session to restore
                for _ in 0..<10 {
                    if supabaseService.isAuthenticated { break }
                    try? await Task.sleep(for: .milliseconds(500))
                }

                print("[iOS Sync] Auth: \(supabaseService.isAuthenticated), email: \(supabaseService.userEmail ?? "nil")")

                if supabaseService.isAuthenticated {
                    await startSync()
                } else {
                    print("[iOS Sync] Skipped — not authenticated, awaiting sign-in")
                }
            }
            .onChange(of: supabaseService.isAuthenticated) { _, isAuthed in
                if isAuthed && syncRepo == nil {
                    print("[iOS Sync] Auth flipped to true, starting sync")
                    Task { await startSync() }
                }
            }
    }

    private func startSync() async {
        let repo = ServerRepository(modelContext: modelContext)
        syncRepo = repo
        await repo.loadFromCloud()
        print("[iOS Sync] loadFromCloud complete, starting auto sync")
        repo.startAutoSync()
    }
}

struct RootView: View {
    @State private var showingLaunch = true
    @State private var isLocked = false
    @State private var router = NavigationRouter.shared
    @State private var ospreyBridge = OspreyBridgeService.shared

    @AppStorage("settings.requireBiometric") private var requireBiometric = false
    @AppStorage("app.theme") private var themeID = "Phosphor"
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var supabaseService: SupabaseService

    var body: some View {
        ZStack {
            ContentView()

            if isLocked {
                BiometricLockView {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isLocked = false
                    }
                }
                .transition(.opacity)
                .zIndex(2)
            }

            if showingLaunch {
                LaunchScreenView()
                    .transition(.opacity)
                    .zIndex(3)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showingLaunch = false
                            }
                            // Check biometric after launch
                            if requireBiometric {
                                isLocked = true
                            }
                        }
                    }
            }
        }
        .id(themeID)
        .onChange(of: themeID) { _, newValue in
            if let id = AppThemeID(rawValue: newValue) {
                ThemeManager.shared.currentThemeID = id
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && requireBiometric {
                isLocked = true
            }
        }
        .onOpenURL { url in
            print("[KESTREL DEEPLINK] Received URL: \(url)")
            print("[KESTREL DEEPLINK] Scheme: \(url.scheme ?? "nil"), Host: \(url.host ?? "nil"), Query: \(url.query ?? "nil")")
            
            if url.host == "auth" {
                Task {
                    await supabaseService.handleAuthCallback(url)
                }
            } else if let action = ospreyBridge.handleDeepLink(url) {
                print("[KESTREL DEEPLINK] Parsed action: \(action)")
                router.handle(action)
                print("[KESTREL DEEPLINK] Router pendingImportHost: \(router.pendingImportHost ?? "nil"), selectedTab: \(router.selectedTab)")
            } else {
                print("[KESTREL DEEPLINK] handleDeepLink returned nil!")
            }
        }
    }
}
