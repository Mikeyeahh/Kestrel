//
//  ServerRepository.swift
//  Kestrel
//
//  Local SwiftData storage with optional Supabase cloud sync.
//

import Foundation
import SwiftData
import SwiftUI

@Observable
final class ServerRepository {
    private let modelContext: ModelContext
    private var supabase: SupabaseService { SupabaseService.shared }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - SSHServer

    func fetchServers() async throws -> [SSHServer] {
        let descriptor = FetchDescriptor<SSHServer>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchServers(inGroup group: String) async throws -> [SSHServer] {
        let descriptor = FetchDescriptor<SSHServer>(
            predicate: #Predicate { $0.group == group },
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchByEnvironment(_ env: ServerEnvironment) async throws -> [SSHServer] {
        let descriptor = FetchDescriptor<SSHServer>(
            predicate: #Predicate { $0.environment == env },
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        return try modelContext.fetch(descriptor)
    }

    func addServer(_ server: SSHServer) async throws {
        server.updatedAt = .now
        modelContext.insert(server)
        try modelContext.save()
        Task {
            do {
                try await supabase.upsertServer(SyncableServer(from: server))
            } catch {
                print("[CloudSync] addServer upsert failed for '\(server.name)': \(error)")
            }
        }
    }

    func deleteServer(_ server: SSHServer) async throws {
        let syncable = SyncableServer(from: server)
        modelContext.delete(server)
        try modelContext.save()
        Task { try? await supabase.deleteServer(syncable) }
    }

    func moveServer(from source: IndexSet, to destination: Int) async throws {
        var servers = try await fetchServers()
        servers.move(fromOffsets: source, toOffset: destination)
        for (index, server) in servers.enumerated() {
            server.orderIndex = index
            server.updatedAt = .now
        }
        try modelContext.save()
        Task {
            for server in servers {
                try? await supabase.upsertServer(SyncableServer(from: server))
            }
        }
    }

    // MARK: - Cloud Sync

    /// IDs we've seen in the cloud at least once — used to distinguish
    /// "new local server" from "deleted on another device".
    private static let syncedIDsKey = "kestrel.synced.server.ids"
    private static let syncedGroupIDsKey = "kestrel.synced.group.ids"

    private func loadSyncedIDs(key: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private func saveSyncedIDs(_ ids: Set<String>, key: String) {
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    /// Two-way sync: push new local items, pull remote changes, delete remotely-removed items.
    func loadFromCloud() async {
        guard supabase.isAuthenticated else {
            print("[iOS CloudSync] loadFromCloud skipped — not authenticated")
            return
        }
        print("[iOS CloudSync] loadFromCloud starting...")
        do {
            // Fetch remote and local servers
            let remoteServers = try await supabase.fetchServers()
            let localServers = try await fetchServers()
            let remoteIDs = Set(remoteServers.map { $0.id })
            let localByID = Dictionary(uniqueKeysWithValues: localServers.map { ($0.id, $0) })
            var knownServerIDs = loadSyncedIDs(key: Self.syncedIDsKey)

            for local in localServers where !remoteIDs.contains(local.id) {
                if knownServerIDs.contains(local.id.uuidString) {
                    // Was synced before but now gone from cloud → deleted on another device
                    print("[CloudSync] Removing locally: '\(local.name)' (deleted on another device)")
                    modelContext.delete(local)
                    knownServerIDs.remove(local.id.uuidString)
                } else {
                    // Never synced → push to cloud
                    do {
                        try await supabase.upsertServer(SyncableServer(from: local))
                        knownServerIDs.insert(local.id.uuidString)
                        print("[CloudSync] Pushed local-only server '\(local.name)' to cloud")
                    } catch {
                        print("[CloudSync] Failed to push '\(local.name)': \(error)")
                    }
                }
            }

            // Pull remote servers into local store
            for remote in remoteServers {
                knownServerIDs.insert(remote.id.uuidString)
                if let local = localByID[remote.id] {
                    let localDate = local.updatedAt ?? .distantPast
                    let remoteDate = remote.updatedAt ?? .distantPast
                    if remoteDate > localDate {
                        remote.apply(to: local)
                    }
                } else {
                    let newServer = remote.toSSHServer()
                    modelContext.insert(newServer)
                }
            }

            saveSyncedIDs(knownServerIDs, key: Self.syncedIDsKey)

            // Fetch remote and local groups
            let remoteGroups = try await supabase.fetchGroups()
            let localGroups = try await fetchGroups()
            let remoteGroupIDs = Set(remoteGroups.map { $0.id })
            let localGroupByID = Dictionary(uniqueKeysWithValues: localGroups.map { ($0.id, $0) })
            var knownGroupIDs = loadSyncedIDs(key: Self.syncedGroupIDsKey)

            for local in localGroups where !remoteGroupIDs.contains(local.id) {
                if knownGroupIDs.contains(local.id.uuidString) {
                    print("[CloudSync] Removing local group: '\(local.name)' (deleted on another device)")
                    modelContext.delete(local)
                    knownGroupIDs.remove(local.id.uuidString)
                } else {
                    do {
                        try await supabase.upsertGroup(SyncableServerGroup(from: local))
                        knownGroupIDs.insert(local.id.uuidString)
                        print("[CloudSync] Pushed local-only group '\(local.name)' to cloud")
                    } catch {
                        print("[CloudSync] Failed to push group '\(local.name)': \(error)")
                    }
                }
            }

            for remote in remoteGroups {
                knownGroupIDs.insert(remote.id.uuidString)
                if let local = localGroupByID[remote.id] {
                    remote.apply(to: local)
                } else {
                    let newGroup = remote.toServerGroup()
                    modelContext.insert(newGroup)
                }
            }

            saveSyncedIDs(knownGroupIDs, key: Self.syncedGroupIDsKey)

            try modelContext.save()
        } catch {
            print("[CloudSync] loadFromCloud failed: \(error)")
        }
    }

    // MARK: - Auto Sync

    func startAutoSync() {
        Task {
            await syncWithCloud()
            
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if supabase.isAuthenticated {
                    await syncWithCloud()
                }
            }
        }
    }

    /// Pull latest servers and groups from Supabase.
    /// Individual add/update/delete operations already push immediately,
    /// so the sync loop only needs to pull.
    func syncWithCloud() async {
        guard supabase.isAuthenticated else { return }
        await loadFromCloud()
        try? await supabase.syncNow()
    }

    // MARK: - KeychainKey

    func fetchKeys() async throws -> [KeychainKey] {
        let descriptor = FetchDescriptor<KeychainKey>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func addKey(_ key: KeychainKey) async throws {
        modelContext.insert(key)
        try modelContext.save()
    }

    func deleteKey(_ key: KeychainKey) async throws {
        modelContext.delete(key)
        try modelContext.save()
    }

    // MARK: - SavedCommand

    func fetchCommands() async throws -> [SavedCommand] {
        let descriptor = FetchDescriptor<SavedCommand>(
            sortBy: [SortDescriptor(\.useCount, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchCommands(category: CommandCategory) async throws -> [SavedCommand] {
        let descriptor = FetchDescriptor<SavedCommand>(
            predicate: #Predicate { $0.category == category },
            sortBy: [SortDescriptor(\.useCount, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchFavouriteCommands() async throws -> [SavedCommand] {
        let descriptor = FetchDescriptor<SavedCommand>(
            predicate: #Predicate { $0.isFavourite == true },
            sortBy: [SortDescriptor(\.useCount, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func addCommand(_ command: SavedCommand) async throws {
        modelContext.insert(command)
        try modelContext.save()
    }

    func deleteCommand(_ command: SavedCommand) async throws {
        modelContext.delete(command)
        try modelContext.save()
    }

    func incrementUseCount(for command: SavedCommand) async throws {
        command.useCount += 1
        try modelContext.save()
    }

    // MARK: - ServerGroup

    func fetchGroups() async throws -> [ServerGroup] {
        let descriptor = FetchDescriptor<ServerGroup>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        return try modelContext.fetch(descriptor)
    }

    func addGroup(_ group: ServerGroup) async throws {
        modelContext.insert(group)
        try modelContext.save()
        Task { try? await supabase.upsertGroup(SyncableServerGroup(from: group)) }
    }

    func deleteGroup(_ group: ServerGroup) async throws {
        let syncable = SyncableServerGroup(from: group)
        modelContext.delete(group)
        try modelContext.save()
        Task { try? await supabase.deleteGroup(syncable) }
    }

    // MARK: - SessionLog

    func fetchSessionLogs(for serverID: UUID? = nil) async throws -> [SessionLog] {
        if let serverID {
            let descriptor = FetchDescriptor<SessionLog>(
                predicate: #Predicate { $0.serverID == serverID },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        }
        let descriptor = FetchDescriptor<SessionLog>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func addSessionLog(_ log: SessionLog) async throws {
        modelContext.insert(log)
        try modelContext.save()
    }

    func endSession(_ log: SessionLog) async throws {
        log.endedAt = .now
        try modelContext.save()
    }

    // MARK: - Save

    func save() throws {
        try modelContext.save()
    }
}
