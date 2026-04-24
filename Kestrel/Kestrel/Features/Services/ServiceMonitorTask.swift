//
//  ServiceMonitorTask.swift
//  Kestrel
//
//  Background app refresh task that checks watched services every ~15 minutes
//  and sends local notifications if any enter a failed state.
//

import Foundation
import BackgroundTasks
import UserNotifications
import SwiftData

enum ServiceMonitorTask {

    static let taskIdentifier = "com.kestrel.service-monitor"

    // MARK: - Registration

    /// Call from KestrelApp.init or AppDelegate to register the background task.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleRefresh(refreshTask)
        }
    }

    // MARK: - Scheduling

    /// Schedules the next background refresh. Call after each check completes.
    static func scheduleNextCheck() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[ServiceMonitor] Failed to schedule: \(error)")
        }
    }

    // MARK: - Execution

    private static func handleRefresh(_ task: BGAppRefreshTask) {
        // Schedule the next one immediately
        scheduleNextCheck()

        let checkTask = Task {
            await performServiceCheck()
        }

        task.expirationHandler = {
            checkTask.cancel()
        }

        Task {
            await checkTask.value
            task.setTaskCompleted(success: true)
        }
    }

    @MainActor
    private static func performServiceCheck() async {
        // Load watched services from SwiftData
        guard let container = try? ModelContainer(for: WatchedService.self, SSHServer.self) else {
            return
        }

        let context = container.mainContext
        let descriptor = FetchDescriptor<WatchedService>(
            predicate: #Predicate { $0.isEnabled == true }
        )

        guard let watchedServices = try? context.fetch(descriptor),
              !watchedServices.isEmpty else {
            return
        }

        // Group by server
        let grouped = Dictionary(grouping: watchedServices) { $0.serverID }
        let sessionManager = SSHSessionManager.shared

        for (serverID, services) in grouped {
            // Find the server
            let serverDescriptor = FetchDescriptor<SSHServer>(
                predicate: #Predicate { $0.id == serverID }
            )
            guard let server = try? context.fetch(serverDescriptor).first else {
                continue
            }

            // Try to connect and check
            do {
                let session = try await sessionManager.openSession(for: server)

                for watched in services {
                    let output = try await session.execute(
                        "systemctl is-active \(watched.serviceName) 2>/dev/null || echo 'unknown'"
                    )
                    let state = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let previousState = watched.lastKnownState

                    watched.lastKnownState = state
                    watched.lastCheckedAt = .now

                    // Notify if newly failed
                    if state == "failed" && previousState != "failed" {
                        await sendFailureNotification(
                            serviceName: watched.serviceName,
                            serverName: watched.serverName
                        )
                    }
                }

                try? context.save()

                // Disconnect — background tasks shouldn't hold connections
                sessionManager.closeSession(serverID: serverID)
            } catch {
                // Connection failed — skip this server
                continue
            }
        }
    }

    // MARK: - Notifications

    private static func sendFailureNotification(serviceName: String, serverName: String) async {
        let center = UNUserNotificationCenter.current()

        // Request permission if needed
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .notDetermined else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Service Failed"
        content.subtitle = serverName
        content.body = "\(serviceName) has entered a failed state on \(serverName)"
        content.sound = .default
        content.categoryIdentifier = "SERVICE_ALERT"
        content.threadIdentifier = "service-\(serverName)-\(serviceName)"

        let request = UNNotificationRequest(
            identifier: "service-fail-\(serverName)-\(serviceName)-\(Date.now.timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )

        try? await center.add(request)
    }

    // MARK: - Notification Setup

    /// Call from app launch to configure notification categories.
    static func configureNotificationCategories() {
        let category = UNNotificationCategory(
            identifier: "SERVICE_ALERT",
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
