//
//  SessionLog.swift
//  Kestrel
//

import Foundation
import SwiftData

@Model
final class SessionLog {
    var id: UUID = UUID()
    var serverID: UUID = UUID()
    var serverName: String = ""
    var startedAt: Date = Date.now
    var endedAt: Date?
    var commandCount: Int = 0
    var recording: Data?

    init(
        id: UUID = UUID(),
        serverID: UUID,
        serverName: String,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        commandCount: Int = 0,
        recording: Data? = nil
    ) {
        self.id = id
        self.serverID = serverID
        self.serverName = serverName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.commandCount = commandCount
        self.recording = recording
    }
}
