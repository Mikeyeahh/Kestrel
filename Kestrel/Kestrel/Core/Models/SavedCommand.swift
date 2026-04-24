//
//  SavedCommand.swift
//  Kestrel
//

import Foundation
import SwiftData

@Model
final class SavedCommand {
    var id: UUID = UUID()
    var name: String = ""
    var command: String = ""
    var category: CommandCategory = CommandCategory.custom
    var commandDescription: String?
    var isFavourite: Bool = false
    var useCount: Int = 0

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        category: CommandCategory = .custom,
        commandDescription: String? = nil,
        isFavourite: Bool = false,
        useCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.category = category
        self.commandDescription = commandDescription
        self.isFavourite = isFavourite
        self.useCount = useCount
    }
}
