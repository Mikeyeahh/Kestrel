//
//  SFTPSession.swift
//  Kestrel
//
//  SFTP session wrapper using Citadel's SFTPClient for file browsing and transfers.
//

import Foundation
import Citadel
import Crypto
import _CryptoExtras
import NIO
import NIOFoundationCompat
import NIOSSH

// MARK: - SFTP File Item

struct SFTPFileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modified: Date?
    let permissions: String

    var icon: String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "log", "csv":     return "doc.text.fill"
        case "json", "xml", "yaml", "yml":  return "curlybraces"
        case "swift", "py", "js", "ts",
             "go", "rs", "rb", "sh", "bash": return "chevron.left.forwardslash.chevron.right"
        case "conf", "cfg", "ini", "env",
             "toml":                          return "gearshape.fill"
        case "jpg", "jpeg", "png", "gif",
             "svg", "webp":                   return "photo.fill"
        case "zip", "tar", "gz", "bz2",
             "xz", "7z":                      return "archivebox.fill"
        default:                              return "doc.fill"
        }
    }

    var formattedSize: String {
        if isDirectory { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

// MARK: - SFTP Session

@Observable
@MainActor
final class SFTPSession {
    let serverID: UUID
    let serverName: String

    private(set) var isConnected = false
    private(set) var currentPath: String = "/"
    private(set) var items: [SFTPFileItem] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var pathHistory: [String] = ["/"]

    private var sshClient: SSHClient?
    private var sftpClient: SFTPClient?

    init(serverID: UUID, serverName: String) {
        self.serverID = serverID
        self.serverName = serverName
    }

    // MARK: - Connect

    func connect(server: SSHServer) async throws {
        isLoading = true
        error = nil

        do {
            let auth = try buildAuth(server: server)

            let client = try await SSHClient.connect(
                host: server.host,
                port: server.port,
                authenticationMethod: auth,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: .all
            )

            self.sshClient = client
            self.sftpClient = try await client.openSFTP()
            self.isConnected = true
            self.currentPath = "/"
            self.pathHistory = ["/"]

            // Try to start in home directory
            if let resolved = try? await resolveHome(),
               let homeItems = try? await listDirectory(resolved) {
                currentPath = resolved
                pathHistory = [resolved]
                items = homeItems
            } else {
                try await navigateTo("/")
            }

            isLoading = false
        } catch {
            isLoading = false
            self.error = error.localizedDescription
            throw error
        }
    }

    // MARK: - Navigation

    func navigateTo(_ path: String) async throws {
        isLoading = true
        error = nil

        do {
            let listing = try await listDirectory(path)
            currentPath = path
            items = listing
            if pathHistory.last != path {
                pathHistory.append(path)
            }
            isLoading = false
        } catch {
            isLoading = false
            self.error = "Failed to list directory: \(error.localizedDescription)"
            throw error
        }
    }

    func navigateUp() async throws {
        let parent = (currentPath as NSString).deletingLastPathComponent
        let target = parent.isEmpty ? "/" : parent
        try await navigateTo(target)
    }

    func goBack() async throws {
        guard pathHistory.count > 1 else { return }
        pathHistory.removeLast()
        if let previous = pathHistory.last {
            isLoading = true
            error = nil
            do {
                let listing = try await listDirectory(previous)
                currentPath = previous
                items = listing
                isLoading = false
            } catch {
                isLoading = false
                self.error = "Failed to navigate back: \(error.localizedDescription)"
                throw error
            }
        }
    }

    func refresh() async throws {
        try await navigateTo(currentPath)
    }

    // MARK: - File Operations

    func readFile(at path: String) async throws -> Data {
        guard let sftp = sftpClient else { throw SSHSessionError.notConnected }
        let file = try await sftp.openFile(filePath: path, flags: .read)
        let buffer = try await file.readAll()
        try await file.close()
        return Data(buffer: buffer)
    }

    func deleteItem(at path: String, isDirectory: Bool) async throws {
        guard let sftp = sftpClient else { throw SSHSessionError.notConnected }
        if isDirectory {
            try await sftp.rmdir(at: path)
        } else {
            try await sftp.remove(at: path)
        }
        try await refresh()
    }

    func createDirectory(named name: String) async throws {
        guard let sftp = sftpClient else { throw SSHSessionError.notConnected }
        let newPath = (currentPath as NSString).appendingPathComponent(name)
        try await sftp.createDirectory(atPath: newPath)
        try await refresh()
    }

    // MARK: - Disconnect

    func disconnect() {
        Task {
            try? await sftpClient?.close()
            try? await sshClient?.close()
        }
        sftpClient = nil
        sshClient = nil
        isConnected = false
        items = []
        currentPath = "/"
        pathHistory = ["/"]
    }

    // MARK: - Private

    private func listDirectory(_ path: String) async throws -> [SFTPFileItem] {
        guard let sftp = sftpClient else { throw SSHSessionError.notConnected }

        let listing = try await sftp.listDirectory(atPath: path)

        // listDirectory returns [SFTPMessage.Name], each with .components: [SFTPPathComponent]
        var fileItems: [SFTPFileItem] = []

        for nameMessage in listing {
            for component in nameMessage.components {
                let name = component.filename
                guard name != "." && name != ".." else { continue }

                // Permissions are a UInt32 bitmask
                let rawPerms = component.attributes.permissions ?? 0
                let isDir = (rawPerms & 0o40000) != 0
                let size = component.attributes.size ?? 0
                let modified = component.attributes.accessModificationTime?.modificationTime

                let fullPath = (path as NSString).appendingPathComponent(name)
                let perms = formatPermissions(rawPerms, isDirectory: isDir)

                fileItems.append(SFTPFileItem(
                    name: name,
                    path: fullPath,
                    isDirectory: isDir,
                    size: size,
                    modified: modified,
                    permissions: perms
                ))
            }
        }

        return fileItems.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func formatPermissions(_ mode: UInt32, isDirectory: Bool) -> String {
        var s = isDirectory ? "d" : "-"
        s += (mode & 0o400) != 0 ? "r" : "-"
        s += (mode & 0o200) != 0 ? "w" : "-"
        s += (mode & 0o100) != 0 ? "x" : "-"
        s += (mode & 0o040) != 0 ? "r" : "-"
        s += (mode & 0o020) != 0 ? "w" : "-"
        s += (mode & 0o010) != 0 ? "x" : "-"
        s += (mode & 0o004) != 0 ? "r" : "-"
        s += (mode & 0o002) != 0 ? "w" : "-"
        s += (mode & 0o001) != 0 ? "x" : "-"
        return s
    }

    private func resolveHome() async throws -> String? {
        guard let ssh = sshClient else { return nil }
        let buffer = try await ssh.executeCommand("echo $HOME", mergeStreams: true)
        let home = String(buffer: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return home.isEmpty ? nil : home
    }

    private func buildAuth(server: SSHServer) throws -> SSHAuthenticationMethod {
        switch server.authMethod {
        case .password:
            let password = try KeychainService.loadPassword(for: server.id)
            return .passwordBased(username: server.username, password: password)
        case .privateKey:
            guard let keyID = server.privateKeyID else {
                throw SSHSessionError.privateKeyNotFound
            }
            let pem = try KeychainService.loadPrivateKey(for: keyID)
            if let ed25519Key = try? Curve25519.Signing.PrivateKey(sshEd25519: pem) {
                return .ed25519(username: server.username, privateKey: ed25519Key)
            }
            if let rsaKey = try? Insecure.RSA.PrivateKey(sshRsa: pem) {
                return .rsa(username: server.username, privateKey: rsaKey)
            }
            if let p256Key = try? P256.Signing.PrivateKey(sshP256: pem) {
                return .p256(username: server.username, privateKey: p256Key)
            }
            throw SSHSessionError.invalidPrivateKey
        case .sshAgent:
            let password = try KeychainService.loadPassword(for: server.id)
            return .passwordBased(username: server.username, password: password)
        }
    }
}
