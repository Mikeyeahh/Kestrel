//
//  KestrelApp.swift
//  Kestrel
//
//  Created by Mike on 03/04/2026.
//

import SwiftUI
import SwiftData

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
