//
//  SSHSessionManager.swift
//  Kestrel
//

import Foundation

// MARK: - Session Manager Error

enum SessionManagerError: LocalizedError {
    case maxSessionsReached
    case sessionNotFound
    case serverNotFound

    var errorDescription: String? {
        switch self {
        case .maxSessionsReached:
            "Maximum concurrent sessions reached (8). Close an existing session to connect."
        case .sessionNotFound:
            "No active session found for this server."
        case .serverNotFound:
            "Server configuration not found."
        }
    }
}

// MARK: - SSH Session Manager

@Observable
@MainActor
final class SSHSessionManager {
    // MARK: - Singleton

    static let shared = SSHSessionManager()

    // MARK: - Configuration

    static let maxConcurrentSessions = 8

    // MARK: - State

    private(set) var activeSessions: [UUID: SSHSession] = [:]
    private(set) var statsEngines: [UUID: ServerStatsEngine] = [:]

    var sessionCount: Int {
        activeSessions.count
    }

    var connectedSessions: [SSHSession] {
        activeSessions.values.filter(\.isConnected)
    }

    var hasCapacity: Bool {
        activeSessions.count < Self.maxConcurrentSessions
    }

    // MARK: - Init

    private init() {}

    // MARK: - Session Lifecycle

    /// Opens a new SSH session for the given server.
    /// If a session already exists for this server, returns the existing one.
    @discardableResult
    func openSession(for server: SSHServer) async throws -> SSHSession {
        // Return existing session if alive
        if let existing = activeSessions[server.id], existing.isConnected {
            return existing
        }

        // Clean up any stale session for this server
        if let stale = activeSessions[server.id] {
            stale.disconnect()
            activeSessions.removeValue(forKey: server.id)
        }

        // Check capacity
        guard hasCapacity else {
            throw SessionManagerError.maxSessionsReached
        }

        // Create new session
        let session = SSHSession(
            serverID: server.id,
            host: server.host,
            port: server.port,
            username: server.username,
            authMethod: server.authMethod,
            privateKeyID: server.privateKeyID
        )

        // Store before connecting so the UI can observe state changes
        activeSessions[server.id] = session

        do {
            try await session.connect()

            // Update server's lastConnected timestamp
            server.lastConnected = .now

            // A successful connection is a positive moment — count it toward
            // possibly asking the user for an App Store review.
            AppReviewManager.shared.recordMilestone()

            return session
        } catch {
            // Remove session on failure
            activeSessions.removeValue(forKey: server.id)
            throw error
        }
    }

    /// Returns or creates a stats engine for a connected server.
    func statsEngine(for serverID: UUID) -> ServerStatsEngine? {
        if let engine = statsEngines[serverID] {
            return engine
        }
        guard let session = activeSessions[serverID], session.isConnected else { return nil }
        let engine = ServerStatsEngine(session: session)
        statsEngines[serverID] = engine
        engine.startPolling()
        return engine
    }

    /// Closes a session for the given server ID.
    func closeSession(serverID: UUID) {
        statsEngines[serverID]?.stopPolling()
        statsEngines.removeValue(forKey: serverID)
        guard let session = activeSessions[serverID] else { return }
        session.disconnect()
        activeSessions.removeValue(forKey: serverID)
    }

    /// Returns the active session for a server ID, or nil if none exists.
    func activeSession(for serverID: UUID) -> SSHSession? {
        activeSessions[serverID]
    }

    /// Closes all active sessions.
    func closeAllSessions() {
        for engine in statsEngines.values {
            engine.stopPolling()
        }
        statsEngines.removeAll()
        for session in activeSessions.values {
            session.disconnect()
        }
        activeSessions.removeAll()
    }

    /// Removes sessions that are no longer connected.
    func pruneDisconnectedSessions() {
        let stale = activeSessions.filter { !$0.value.isConnected }
        for (id, session) in stale {
            session.disconnect()
            activeSessions.removeValue(forKey: id)
        }
    }
}
