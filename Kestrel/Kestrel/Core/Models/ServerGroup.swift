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
    var colour: String = "#00FF41"
    var orderIndex: Int = 0

    init(
        id: UUID = UUID(),
        name: String,
        colour: String = "#00FF41",
        orderIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colour = colour
        self.orderIndex = orderIndex
    }
}
