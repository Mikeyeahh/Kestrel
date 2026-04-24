//
//  WatchedService.swift
//  Kestrel
//
//  Per-server service monitoring configuration for background alerts.
//

import Foundation
import SwiftData

@Model
final class WatchedService {
    var id: UUID = UUID()
    var serverID: UUID = UUID()
    var serverName: String = ""
    var serviceName: String = ""
    var addedAt: Date = Date.now
    var lastCheckedAt: Date?
    var lastKnownState: String?
    var isEnabled: Bool = true

    init(
        id: UUID = UUID(),
        serverID: UUID,
        serverName: String,
        serviceName: String,
        addedAt: Date = .now,
        lastCheckedAt: Date? = nil,
        lastKnownState: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.serverID = serverID
        self.serverName = serverName
        self.serviceName = serviceName
        self.addedAt = addedAt
        self.lastCheckedAt = lastCheckedAt
        self.lastKnownState = lastKnownState
        self.isEnabled = isEnabled
    }
}
