//
//  ServerModels.swift
//  Kestrel
//

import SwiftUI

// MARK: - ServerEnvironment

enum ServerEnvironment: String, Codable, CaseIterable {
    case production
    case staging
    case development
    case other

    var displayName: String {
        switch self {
        case .production: "Production"
        case .staging: "Staging"
        case .development: "Development"
        case .other: "Other"
        }
    }

    var badge: String {
        switch self {
        case .production: "PROD"
        case .staging: "STAGE"
        case .development: "DEV"
        case .other: "OTHER"
        }
    }

    var colour: Color {
        switch self {
        case .production: KestrelColors.red
        case .staging: KestrelColors.amber
        case .development: KestrelColors.blue
        case .other: .gray
        }
    }
}

// MARK: - AuthMethod

enum AuthMethod: String, Codable, CaseIterable {
    case password
    case privateKey
    case sshAgent
}

// MARK: - ConnectionProtocol

enum ConnectionProtocol: String, Codable, CaseIterable {
    case ssh
    case vnc
    case rdp

    var displayName: String {
        switch self {
        case .ssh: "SSH"
        case .vnc: "VNC"
        case .rdp: "RDP"
        }
    }

    var icon: String {
        switch self {
        case .ssh: "terminal"
        case .vnc: "rectangle.on.rectangle"
        case .rdp: "desktopcomputer"
        }
    }

    var defaultPort: Int {
        switch self {
        case .ssh: 22
        case .vnc: 5900
        case .rdp: 3389
        }
    }
}

// MARK: - ServerStatus

enum ServerStatus: String, CaseIterable {
    case online
    case offline
    case warning

    var color: Color {
        switch self {
        case .online: KestrelColors.phosphorGreen
        case .offline: KestrelColors.red
        case .warning: KestrelColors.amber
        }
    }
}

// MARK: - KeyType

enum KeyType: String, Codable, CaseIterable {
    case ed25519
    case rsa4096
    case rsa2048

    var displayName: String {
        switch self {
        case .ed25519: "Ed25519"
        case .rsa4096: "RSA 4096"
        case .rsa2048: "RSA 2048"
        }
    }
}

// MARK: - CommandCategory

enum CommandCategory: String, Codable, CaseIterable {
    case system
    case networking
    case docker
    case kubernetes
    case git
    case nginx
    case files
    case custom

    var icon: String {
        switch self {
        case .system: "cpu"
        case .networking: "network"
        case .docker: "shippingbox"
        case .kubernetes: "helm"
        case .git: "point.3.connected.trianglepath.dotted"
        case .nginx: "server.rack"
        case .files: "folder"
        case .custom: "terminal"
        }
    }

    var displayName: String {
        switch self {
        case .system: "System"
        case .networking: "Networking"
        case .docker: "Docker"
        case .kubernetes: "Kubernetes"
        case .git: "Git"
        case .nginx: "Nginx"
        case .files: "Files"
        case .custom: "Custom"
        }
    }
}
