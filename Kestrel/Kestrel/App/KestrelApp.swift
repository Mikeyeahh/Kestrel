//
//  KestrelApp.swift
//  Kestrel
//
//  Created by Mike on 03/04/2026.
//

import SwiftUI
import SwiftData
import StoreKit

/// Shared App Group container for credential sharing with OSPREY.
let kestrelAppGroup = "group.com.getosprey.suite"

@main
struct KestrelApp: App {
    @StateObject private var supabaseService = SupabaseService.shared

    init() {
        Analytics.configure()

        KestrelRevenueCatService.shared.configure(apiKey: "appl_NrjcEYMRTSJeVklytqRaAFhQcPm")

        ServiceMonitorTask.register()
        ServiceMonitorTask.configureNotificationCategories()
        ServiceMonitorTask.scheduleNextCheck()
    }

    var body: some Scene {
        WindowGroup {
            RootSyncWrapper()
                .preferredColorScheme(.dark)
                .environmentObject(supabaseService)
                .reviewPrompt()
        }
        .modelContainer(for: [
            SSHServer.self,
            KeychainKey.self,
            SavedCommand.self,
            ServerGroup.self,
            SessionLog.self,
            WatchedService.self,
            CommandLogEntry.self
        ])
    }
}

// MARK: - App Review Prompts

/// Decides when to surface the system "rate this app" prompt. It asks only
/// after a few positive moments (successful connections) and never more than
/// once per app version. StoreKit additionally caps the prompt at three times
/// per year, so this stays well within Apple's guidance.
@MainActor
final class AppReviewManager: ObservableObject {
    static let shared = AppReviewManager()

    /// Flips to `true` when a prompt is warranted. The root view observes this,
    /// invokes the StoreKit request, then calls `markPrompted()`.
    @Published var pendingReviewRequest = false

    private let milestoneCountKey = "kestrel.review.milestoneCount"
    private let lastPromptedVersionKey = "kestrel.review.lastPromptedVersion"

    /// Successful connections required before we consider prompting.
    private let milestoneThreshold = 3

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private init() {}

    /// Record a positive moment (e.g. a server connected successfully).
    func recordMilestone() {
        let defaults = UserDefaults.standard
        // Already asked on this version — don't pester until the next update.
        guard defaults.string(forKey: lastPromptedVersionKey) != currentVersion else { return }

        let count = defaults.integer(forKey: milestoneCountKey) + 1
        defaults.set(count, forKey: milestoneCountKey)
        if count >= milestoneThreshold {
            pendingReviewRequest = true
        }
    }

    /// Called by the view layer once the prompt has been requested.
    func markPrompted() {
        pendingReviewRequest = false
        let defaults = UserDefaults.standard
        defaults.set(currentVersion, forKey: lastPromptedVersionKey)
        defaults.set(0, forKey: milestoneCountKey)
    }
}

private struct ReviewPromptModifier: ViewModifier {
    @Environment(\.requestReview) private var requestReview
    @ObservedObject private var manager = AppReviewManager.shared

    func body(content: Content) -> some View {
        content.onChange(of: manager.pendingReviewRequest) { _, pending in
            guard pending else { return }
            Task { @MainActor in
                // Brief delay so the prompt doesn't collide with the
                // connection UI that just appeared.
                try? await Task.sleep(for: .seconds(1.5))
                requestReview()
                manager.markPrompted()
            }
        }
    }
}

extension View {
    /// Surfaces the system review prompt at appropriate moments. Attach once
    /// near the app's root.
    func reviewPrompt() -> some View { modifier(ReviewPromptModifier()) }
}
