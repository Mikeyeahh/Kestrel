//
//  ServerGroup.swift
//  Kestrel
//

import Foundation
import SwiftData

@Model
final class ServerGroup {
    var id: UUID = UUID()
    var name: String = ""
    var colour: String = "#00FF9C"
    var orderIndex: Int = 0
    /// Optional parent group id — groups form a tree when set.
    var parentId: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        colour: String = "#00FF9C",
        orderIndex: Int = 0,
        parentId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.colour = colour
        self.orderIndex = orderIndex
        self.parentId = parentId
    }
}
