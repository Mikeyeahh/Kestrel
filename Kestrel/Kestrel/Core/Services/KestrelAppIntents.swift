//
//  KestrelAppIntents.swift
//  Kestrel
//
//  Apple Shortcuts integration via AppIntents framework.
//  Provides: ConnectToServer, RunCommand, CheckServerStatus.
//

import AppIntents
import SwiftData

// MARK: - Server Entity for AppIntents

struct ServerEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Server")
    static var defaultQuery = ServerEntityQuery()

    var id: UUID
    var name: String
    var host: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(host)")
    }
}

struct ServerEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ServerEntity] {
        let container = try ModelContainer(for: SSHServer.self)
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SSHServer>()
        let servers = try context.fetch(descriptor)
        return servers
            .filter { identifiers.contains($0.id) }
            .map { ServerEntity(id: $0.id, name: $0.name, host: $0.host) }
    }

    func suggestedEntities() async throws -> [ServerEntity] {
        let container = try ModelContainer(for: SSHServer.self)
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SSHServer>(sortBy: [SortDescriptor(\.orderIndex)])
        let servers = try context.fetch(descriptor)
        return servers.map { ServerEntity(id: $0.id, name: $0.name, host: $0.host) }
    }
}

// MARK: - Connect to Server Intent

struct ConnectToServerIntent: AppIntent {
    static var title: LocalizedStringResource = "Connect to Server"
    static var description = IntentDescription("Opens Kestrel and connects to the selected server's terminal.")
    static var openAppWhenRun = true

    @Parameter(title: "Server")
    var server: ServerEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let router = NavigationRouter.shared
        router.terminalServerID = server.id
        router.selectedTab = .terminal
        return .result()
    }
}

// MARK: - Run Command Intent

struct RunCommandIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Command on Server"
    static var description = IntentDescription("Runs a command on the selected server and returns the output.")

    @Parameter(title: "Command")
    var command: String

    @Parameter(title: "Server")
    var server: ServerEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let sessionManager = SSHSessionManager.shared

        // Find the server in SwiftData
        let container = try ModelContainer(for: SSHServer.self)
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SSHServer>()
        let servers = try context.fetch(descriptor)

        guard let sshServer = servers.first(where: { $0.id == server.id }) else {
            return .result(value: "Error: Server not found")
        }

        do {
            let session = try await sessionManager.openSession(for: sshServer)
            let output = try await session.execute(command)
            return .result(value: output)
        } catch {
            return .result(value: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Check Server Status Intent

struct CheckServerStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Server Status"
    static var description = IntentDescription("Checks if a server is online and returns its status.")

    @Parameter(title: "Server")
    var server: ServerEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let sessionManager = SSHSessionManager.shared

        let container = try ModelContainer(for: SSHServer.self)
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SSHServer>()
        let servers = try context.fetch(descriptor)

        guard let sshServer = servers.first(where: { $0.id == server.id }) else {
            return .result(value: "Server not found")
        }

        // Check if already connected
        if let session = sessionManager.activeSession(for: sshServer.id), session.isConnected {
            return .result(value: "\(sshServer.name) is online (connected)")
        }

        // Try to connect
        do {
            let session = try await sessionManager.openSession(for: sshServer)
            let uptime = try await session.execute("uptime -p 2>/dev/null || uptime")
            sessionManager.closeSession(serverID: sshServer.id)
            return .result(value: "\(sshServer.name) is online — \(uptime)")
        } catch {
            return .result(value: "\(sshServer.name) is offline — \(error.localizedDescription)")
        }
    }
}

// MARK: - Shortcuts Provider

struct KestrelShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectToServerIntent(),
            phrases: [
                "Connect to \(\.$server) in \(.applicationName)",
                "Open \(\.$server) terminal in \(.applicationName)"
            ],
            shortTitle: "Connect to Server",
            systemImageName: "terminal"
        )

        AppShortcut(
            intent: CheckServerStatusIntent(),
            phrases: [
                "Is \(\.$server) online in \(.applicationName)",
                "Check \(\.$server) status in \(.applicationName)"
            ],
            shortTitle: "Check Server Status",
            systemImageName: "server.rack"
        )

        AppShortcut(
            intent: RunCommandIntent(),
            phrases: [
                "Run command on \(\.$server) in \(.applicationName)"
            ],
            shortTitle: "Run Command",
            systemImageName: "command"
        )
    }
}
