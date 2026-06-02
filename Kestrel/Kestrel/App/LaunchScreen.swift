//
//  LaunchScreen.swift
//  Kestrel
//
//  Animated launch screen, Face ID lock gate, and deep link routing.
//

import SwiftUI
import SwiftData
import LocalAuthentication
import UIKit

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

// MARK: - Background Grace

/// Requests a short background-execution window when the app leaves the
/// foreground, so a quick app-switch doesn't immediately suspend Kestrel and
/// drop live SSH sessions. iOS grants roughly 30 seconds; the assertion is
/// released as soon as we return to the foreground or the window expires.
///
/// This does not — and on iOS cannot — keep the app running indefinitely in
/// the background; it only smooths over brief excursions to other apps.
@MainActor
final class BackgroundGraceManager {
    static let shared = BackgroundGraceManager()

    private var taskID: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    /// Begin (or renew) the background-time assertion.
    func begin() {
        endIfNeeded()
        taskID = UIApplication.shared.beginBackgroundTask(withName: "kestrel.grace") { [weak self] in
            // iOS calls this when the window is about to expire. We must end
            // the task here or the OS terminates the app.
            self?.endIfNeeded()
        }
    }

    /// Release the assertion if one is held.
    func endIfNeeded() {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }
}

struct RootView: View {
    @State private var showingLaunch = true
    @State private var isLocked = false
    @State private var router = NavigationRouter.shared
    @State private var ospreyBridge = OspreyBridgeService.shared

    @AppStorage("settings.requireBiometric") private var requireBiometric = false
    @AppStorage("app.theme") private var themeID = "Phosphor"
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var supabaseService: SupabaseService

    var body: some View {
        ZStack {
            ContentView()

            // Registration is required to use the app: the welcome overlay
            // stays up until the user has *both* completed onboarding once
            // and has an active authenticated Supabase session.
            if !onboardingCompleted || !supabaseService.isAuthenticated {
                WelcomeView {
                    withAnimation(.easeOut(duration: 0.3)) {
                        onboardingCompleted = true
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }

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
            switch phase {
            case .background:
                // Ask iOS for a short grace window so a quick app-switch
                // doesn't suspend Kestrel (and drop live SSH sessions) the
                // instant we leave the foreground.
                BackgroundGraceManager.shared.begin()
                if requireBiometric { isLocked = true }
            case .active:
                // Back in the foreground — release the assertion.
                BackgroundGraceManager.shared.endIfNeeded()
            default:
                break
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
