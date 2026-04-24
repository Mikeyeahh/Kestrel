//
//  SyncableServer.swift
//  Kestrel
//
//  Codable bridge between the SwiftData SSHServer model and the Supabase
//  "servers" table.  Converts in both directions so local and cloud
//  representations stay in sync.
//

import Foundation

struct SyncableServer: Identifiable, Codable {
    let id: UUID
    var userId: UUID?
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: String
    var privateKeyID: UUID?
    var group: String?
    var environment: String
    var colour: String
    var tags: [String]
    var orderIndex: Int
    var notes: String?
    var updatedAt: Date?
    var connectionType: String
    var useMosh: Bool
    var vncPort: Int?
    var rdpPort: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, host, port, username
        case authMethod = "auth_method"
        case privateKeyID = "private_key_id"
        case group, environment, colour, tags
        case orderIndex = "order_index"
        case notes
        case updatedAt = "updated_at"
        case connectionType = "connection_type"
        case useMosh = "use_mosh"
        case vncPort = "vnc_port"
        case rdpPort = "rdp_port"
    }

    // MARK: - Decodable Fallbacks
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decodeIfPresent(UUID.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try container.decode(String.self, forKey: .username)
        authMethod = try container.decodeIfPresent(String.self, forKey: .authMethod) ?? "password"
        privateKeyID = try container.decodeIfPresent(UUID.self, forKey: .privateKeyID)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        environment = try container.decodeIfPresent(String.self, forKey: .environment) ?? "other"
        colour = try container.decodeIfPresent(String.self, forKey: .colour) ?? "#00FF41"
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex) ?? 0
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        connectionType = try container.decodeIfPresent(String.self, forKey: .connectionType) ?? "ssh"
        useMosh = try container.decodeIfPresent(Bool.self, forKey: .useMosh) ?? false
        vncPort = try container.decodeIfPresent(Int.self, forKey: .vncPort)
        rdpPort = try container.decodeIfPresent(Int.self, forKey: .rdpPort)
    }

    // MARK: - Convert from SwiftData model

    init(from server: SSHServer) {
        self.id = server.id
        self.name = server.name
        self.host = server.host
        self.port = server.port
        self.username = server.username
        self.authMethod = server.authMethod.rawValue
        self.privateKeyID = server.privateKeyID
        self.group = server.group
        self.environment = server.environment.rawValue
        self.colour = server.colour
        self.tags = server.tags
        self.orderIndex = server.orderIndex
        self.notes = server.notes
        self.updatedAt = server.updatedAt
        self.connectionType = server.connectionType
        self.useMosh = server.useMosh
        self.vncPort = server.vncPort
        self.rdpPort = server.rdpPort
    }

    // MARK: - Apply cloud data onto an existing SwiftData model

    func apply(to server: SSHServer) {
        server.name = name
        server.host = host
        server.port = port
        server.username = username
        server.authMethod = AuthMethod(rawValue: authMethod) ?? .password
        server.privateKeyID = privateKeyID
        server.group = group
        server.environment = ServerEnvironment(rawValue: environment) ?? .other
        server.colour = colour
        server.tags = tags
        server.orderIndex = orderIndex
        server.notes = notes
        server.updatedAt = updatedAt
        server.connectionType = connectionType
        server.useMosh = useMosh
        server.vncPort = vncPort
        server.rdpPort = rdpPort
    }

    // MARK: - Create a new SwiftData model from cloud data

    func toSSHServer() -> SSHServer {
        SSHServer(
            id: id,
            name: name,
            host: host,
            port: port,
            username: username,
            authMethod: AuthMethod(rawValue: authMethod) ?? .password,
            privateKeyID: privateKeyID,
            group: group,
            environment: ServerEnvironment(rawValue: environment) ?? .other,
            colour: colour,
            notes: notes,
            tags: tags,
            orderIndex: orderIndex,
            connectionType: connectionType,
            useMosh: useMosh,
            vncPort: vncPort,
            rdpPort: rdpPort
        )
    }
}
