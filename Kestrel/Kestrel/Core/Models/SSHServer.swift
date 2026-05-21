//
//  SSHServer.swift
//  Kestrel
//

import Foundation
import SwiftData

@Model
final class SSHServer {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var authMethod: AuthMethod = AuthMethod.password
    var privateKeyID: UUID?
    var jumpHostID: UUID?
    /// Canonical group membership — the owning `ServerGroup.id`. Stable
    /// across group renames. `nil` means the server is ungrouped.
    var groupId: UUID?
    /// Legacy group *name*. Kept only so older data still resolves; new
    /// code groups by `groupId`.
    var group: String?
    var environment: ServerEnvironment = ServerEnvironment.other
    var colour: String = "#00FF9C"
    var lastConnected: Date?
    var notes: String?
    var tags: [String] = []
    var orderIndex: Int = 0
    var updatedAt: Date?
    var connectionType: String = "ssh"
    var useMosh: Bool = false
    var vncPort: Int?
    var rdpPort: Int?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod = .password,
        privateKeyID: UUID? = nil,
        jumpHostID: UUID? = nil,
        groupId: UUID? = nil,
        group: String? = nil,
        environment: ServerEnvironment = .other,
        colour: String = "#00FF9C",
        lastConnected: Date? = nil,
        notes: String? = nil,
        tags: [String] = [],
        orderIndex: Int = 0,
        updatedAt: Date? = nil,
        connectionType: String = "ssh",
        useMosh: Bool = false,
        vncPort: Int? = nil,
        rdpPort: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.privateKeyID = privateKeyID
        self.jumpHostID = jumpHostID
        self.groupId = groupId
        self.group = group
        self.environment = environment
        self.colour = colour
        self.lastConnected = lastConnected
        self.notes = notes
        self.tags = tags
        self.orderIndex = orderIndex
        self.updatedAt = updatedAt
        self.connectionType = connectionType
        self.useMosh = useMosh
        self.vncPort = vncPort
        self.rdpPort = rdpPort
    }

    var connectionProtocol: ConnectionProtocol {
        ConnectionProtocol(rawValue: connectionType) ?? .ssh
    }
}
