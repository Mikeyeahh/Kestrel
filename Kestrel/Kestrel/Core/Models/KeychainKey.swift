//
//  KeychainKey.swift
//  Kestrel
//

import Foundation
import SwiftData

@Model
final class KeychainKey {
    var id: UUID = UUID()
    var name: String = ""
    var keyType: KeyType = KeyType.ed25519
    var publicKey: String = ""
    var createdAt: Date = Date.now
    var comment: String?

    init(
        id: UUID = UUID(),
        name: String,
        keyType: KeyType,
        publicKey: String,
        createdAt: Date = .now,
        comment: String? = nil
    ) {
        self.id = id
        self.name = name
        self.keyType = keyType
        self.publicKey = publicKey
        self.createdAt = createdAt
        self.comment = comment
    }
}
