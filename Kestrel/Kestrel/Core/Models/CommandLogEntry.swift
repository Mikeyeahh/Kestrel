//
//  CommandLogEntry.swift
//  Kestrel
//
//  Audit log entry for every command sent to a server via terminal.
//

import Foundation
import SwiftData

@Model
final class CommandLogEntry {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var serverID: UUID = UUID()
    var serverName: String = ""
    var timestamp: Date = Date.now
    var command: String = ""

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        serverID: UUID,
        serverName: String,
        timestamp: Date = .now,
        command: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.serverID = serverID
        self.serverName = serverName
        self.timestamp = timestamp
        self.command = command
    }
}
