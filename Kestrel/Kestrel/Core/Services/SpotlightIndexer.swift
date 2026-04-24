//
//  SpotlightIndexer.swift
//  Kestrel
//
//  CoreSpotlight integration — indexes saved servers for system search.
//

import CoreSpotlight
import SwiftData

enum SpotlightIndexer {

    private static let domainID = "com.kestrel.servers"

    /// Re-indexes all servers in CoreSpotlight.
    @MainActor
    static func indexServers(_ servers: [SSHServer]) {
        // Delete existing entries
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domainID]
        ) { _ in }

        let items = servers.map { server -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = server.name
            attributes.contentDescription = "\(server.username)@\(server.host):\(server.port) — \(server.environment.displayName)"
            attributes.keywords = [server.name, server.host, server.username, server.environment.displayName]

            return CSSearchableItem(
                uniqueIdentifier: "server-\(server.id.uuidString)",
                domainIdentifier: domainID,
                attributeSet: attributes
            )
        }

        guard !items.isEmpty else { return }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                print("[Spotlight] Indexing error: \(error)")
            }
        }
    }

    /// Removes a single server from the Spotlight index.
    static func removeServer(_ serverID: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: ["server-\(serverID.uuidString)"]
        ) { _ in }
    }

    /// Parses a Spotlight continuation user activity into a server ID.
    static func serverID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix("server-") else {
            return nil
        }
        let idString = String(identifier.dropFirst(7))
        return UUID(uuidString: idString)
    }
}
