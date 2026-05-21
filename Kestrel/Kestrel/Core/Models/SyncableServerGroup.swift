//
//  SyncableServerGroup.swift
//  Kestrel
//
//  Codable bridge between the SwiftData ServerGroup model and the Supabase
//  "server_groups" table.
//

import Foundation

struct SyncableServerGroup: Identifiable, Codable {
    let id: UUID
    var userId: UUID?
    var name: String
    var colour: String
    var orderIndex: Int
    /// Optional parent group id — groups form a tree when set.
    var parentId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, colour
        case orderIndex = "order_index"
        case parentId = "parent_id"
    }

    // MARK: - Convert from SwiftData model

    init(from group: ServerGroup) {
        self.id = group.id
        self.name = group.name
        self.colour = group.colour
        self.orderIndex = group.orderIndex
        self.parentId = group.parentId
    }

    // MARK: - Apply cloud data onto an existing SwiftData model

    func apply(to group: ServerGroup) {
        group.name = name
        group.colour = colour
        group.orderIndex = orderIndex
        group.parentId = parentId
    }

    // MARK: - Create a new SwiftData model from cloud data

    func toServerGroup() -> ServerGroup {
        ServerGroup(
            id: id,
            name: name,
            colour: colour,
            orderIndex: orderIndex,
            parentId: parentId
        )
    }
}
