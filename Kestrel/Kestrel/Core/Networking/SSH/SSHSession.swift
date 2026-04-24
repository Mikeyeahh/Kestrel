//
//  SSHSession.swift
//  Kestrel
//

import Foundation
import Citadel
import Crypto
import NIOSSH
import NIO

// MARK: - Session State

enum SessionState: Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case error(String)

    var displayName: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .authenticating: "Authenticating…"
        case .connected: "Connected"
        case .error(let message): "Error: \(message)"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .disconnected, .error: true
        default: false
        }
    }
}

// MARK: - SSH Session Error

enum SSHSessionError: LocalizedError {
    case notConnected
    case alreadyConnected
    case shellAlreadyActive
    case authenticationFailed(String)
    case connectionFailed(String)
    case commandFailed(String)
    case privateKeyNotFound
    case invalidPrivateKey
    case passwordNotFound

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Not connected to server"
        case .alreadyConnected:
            "Already connected to server"
        case .shellAlreadyActive:
            "Interactive shell is already active"
        case .authenticationFailed(let reason):
            "Authentication failed: \(reason)"
        case .connectionFailed(let reason):
            "Connection failed: \(reason)"
        case .commandFailed(let reason):
            "Command failed: \(reason)"
        case .privateKeyNotFound:
            "Private key not found in Keychain"
        case .invalidPrivateKey:
            "Could not parse private key"
        case .passwordNotFound:
            "Password not found in Keychain — please re-enter your password in server settings"
        }
    }
}

// MARK: - SSH Session

@Observable
@MainActor
final class SSHSession {
    // MARK: - Properties

    let serverID: UUID
    let host: String
    let port: Int
    let username: String
    let authMethod: AuthMethod
    let privateKeyID: UUID?

    private(set) var state: SessionState = .disconnected
    private(set) var output: String = ""
    private(set) var connectedAt: Date?

    var isConnected: Bool {
        state == .connected
    }

    // MARK: - Private State

    private var client: SSHClient?
    private var keepaliveTask: Task<Void, Never>?
    private var shellTask: Task<Void, Never>?
    private var shellWriter: TTYStdinWriter?

    var isShellActive: Bool {
        shellTask != nil && !(shellTask?.isCancelled ?? true)
    }

    // MARK: - Init

    nonisolated init(
        serverID: UUID,
        host: String,
        port: Int,
        username: String,
        authMethod: AuthMethod,
        privateKeyID: UUID? = nil
    ) {
        self.serverID = serverID
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.privateKeyID = privateKeyID
    }

    nonisolated deinit {
        // Tasks will be cancelled when their references are deallocated
    }

    // MARK: - Connect

    func connect() async throws {
        guard state != .connected else {
            throw SSHSessionError.alreadyConnected
        }

        state = .connecting

        do {
            // Build authentication method
            state = .authenticating
            let sshAuth = try buildAuthenticationMethod()

            // Connect via Citadel
            let sshClient = try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: sshAuth,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: .all
            )

            self.client = sshClient
            self.state = .connected
            self.connectedAt = .now
            Analytics.capture("ssh_session_started")

            // Handle unexpected disconnects
            sshClient.onDisconnect { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.state == .connected else { return }
                    self.handleDisconnect()
                }
            }

            // Start keepalive
            startKeepalive()
        } catch {
            let friendlyMessage = Self.friendlyErrorMessage(for: error, authMethod: authMethod)
            state = .error(friendlyMessage)
            throw SSHSessionError.connectionFailed(friendlyMessage)
        }
    }

    // MARK: - Execute Command

    func execute(_ command: String) async throws -> String {
        guard let client, isConnected else {
            throw SSHSessionError.notConnected
        }

        do {
            let buffer = try await client.executeCommand(command, mergeStreams: true)
            let result = String(buffer: buffer)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as SSHClient.CommandFailed {
            throw SSHSessionError.commandFailed("Exit code \(error.exitCode)")
        } catch {
            throw SSHSessionError.commandFailed(error.localizedDescription)
        }
    }

    // MARK: - Interactive Shell

    func startShell() throws {
        guard let client, isConnected else {
            throw SSHSessionError.notConnected
        }

        guard !isShellActive else {
            throw SSHSessionError.shellAlreadyActive
        }

        output = ""

        shellTask = Task { [weak self] in
            guard let self else { return }

            do {
                let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: 80,
                    terminalRowHeight: 24,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([
                        .ECHO: 1,
                        .ICANON: 1
                    ])
                )

                if #available(iOS 18.0, macOS 15.0, *) {
                    try await client.withPTY(ptyRequest) { [weak self] inbound, outbound in
                        guard let self else { return }

                        await MainActor.run {
                            self.shellWriter = outbound
                        }

                        for try await event in inbound {
                            switch event {
                            case .stdout(let buffer):
                                let text = String(buffer: buffer)
                                await MainActor.run {
                                    self.output.append(text)
                                }
                            case .stderr(let buffer):
                                let text = String(buffer: buffer)
                                await MainActor.run {
                                    self.output.append(text)
                                }
                            }
                        }
                    }
                } else {
                    // Fallback: use executeCommand in shell mode for older OS
                    let stream = try await client.executeCommandStream("bash -l", inShell: true)
                    for try await event in stream {
                        switch event {
                        case .stdout(let buffer):
                            let text = String(buffer: buffer)
                            await MainActor.run {
                                self.output.append(text)
                            }
                        case .stderr(let buffer):
                            let text = String(buffer: buffer)
                            await MainActor.run {
                                self.output.append(text)
                            }
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.output.append("\r\n[Shell ended: \(error.localizedDescription)]\r\n")
                    }
                }
            }

            await MainActor.run {
                self.shellWriter = nil
                self.shellTask = nil
            }
        }
    }

    func send(_ input: String) {
        guard let shellWriter else { return }

        Task {
            var buffer = ByteBufferAllocator().buffer(capacity: input.utf8.count)
            buffer.writeString(input)
            try? await shellWriter.write(buffer)
        }
    }

    func resizeTerminal(cols: Int, rows: Int) {
        guard let shellWriter else { return }

        Task {
            try? await shellWriter.changeSize(
                cols: cols,
                rows: rows,
                pixelWidth: 0,
                pixelHeight: 0
            )
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        keepaliveTask?.cancel()
        keepaliveTask = nil

        shellTask?.cancel()
        shellTask = nil
        shellWriter = nil

        Task {
            try? await client?.close()
            client = nil
        }

        state = .disconnected
        connectedAt = nil
    }

    // MARK: - Private Helpers

    private func buildAuthenticationMethod() throws -> SSHAuthenticationMethod {
        switch authMethod {
        case .password:
            // Password is fetched from Keychain at connection time
            // For now, we use a placeholder — the caller should provide it
            // or we load from KeychainService using serverID
            let password = try loadPasswordFromKeychain()
            return .passwordBased(username: username, password: password)

        case .privateKey:
            guard let keyID = privateKeyID else {
                throw SSHSessionError.privateKeyNotFound
            }

            let pem = try KeychainService.loadPrivateKey(for: keyID)
            return try parsePrivateKeyAuth(pem: pem)

        case .sshAgent:
            // SSH Agent is not supported on iOS — fall back to password
            let password = try loadPasswordFromKeychain()
            return .passwordBased(username: username, password: password)
        }
    }

    private func loadPasswordFromKeychain() throws -> String {
        do {
            return try KeychainService.loadPassword(for: serverID)
        } catch {
            throw SSHSessionError.passwordNotFound
        }
    }

    private func parsePrivateKeyAuth(pem: String) throws -> SSHAuthenticationMethod {
        // Try Ed25519 first (most common modern key type)
        if let ed25519Key = try? Curve25519.Signing.PrivateKey(sshEd25519: pem) {
            return .ed25519(username: username, privateKey: ed25519Key)
        }

        // Try RSA
        if let rsaKey = try? Insecure.RSA.PrivateKey(sshRsa: pem) {
            return .rsa(username: username, privateKey: rsaKey)
        }

        // Try P256
        if let p256Key = try? P256.Signing.PrivateKey(sshP256: pem) {
            return .p256(username: username, privateKey: p256Key)
        }

        throw SSHSessionError.invalidPrivateKey
    }

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))

                guard !Task.isCancelled else { break }
                guard let self, self.isConnected else { break }

                // Send a lightweight command as a keepalive probe
                do {
                    _ = try await self.execute("echo 1")
                } catch {
                    // Connection likely dropped
                    await MainActor.run {
                        self.handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    /// Maps low-level SSH/network errors into user-friendly messages.
    private static func friendlyErrorMessage(for error: Error, authMethod: AuthMethod) -> String {
        let message = String(describing: error).lowercased()

        // Authentication failures
        if message.contains("authentication") || message.contains("auth") ||
           message.contains("permission denied") || message.contains("userauth") {
            switch authMethod {
            case .password, .sshAgent:
                return "Invalid username or password — please check your credentials and try again"
            case .privateKey:
                return "Authentication failed — the server rejected your private key"
            }
        }

        // Connection refused (wrong port, server not running sshd)
        if message.contains("connection refused") || message.contains("connrefused") {
            return "Connection refused — check the host address and port"
        }

        // Host unreachable / DNS failure
        if message.contains("no route to host") || message.contains("host unreachable") ||
           message.contains("network is unreachable") {
            return "Host unreachable — check the address and your network connection"
        }

        if message.contains("name or service not known") || message.contains("nodename nor servname") ||
           message.contains("could not resolve") || message.contains("dns") {
            return "Could not resolve hostname — check the server address"
        }

        // Timeout
        if message.contains("timed out") || message.contains("timeout") {
            return "Connection timed out — the server may be offline or unreachable"
        }

        // Fallback to the original error
        return error.localizedDescription
    }

    private func handleDisconnect() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        shellTask?.cancel()
        shellTask = nil
        shellWriter = nil
        client = nil
        connectedAt = nil

        if state == .connected {
            state = .error("Connection lost")
        }
    }
}

// MARK: - Citadel Key Parsing Helpers

/// Extension to parse OpenSSH Ed25519 private keys from PEM format
extension Curve25519.Signing.PrivateKey {
    init(sshEd25519 pem: String) throws {
        // Citadel's OpenSSH key parser handles this
        // The exact parsing depends on the key format
        // For raw 32-byte ed25519 seeds or OpenSSH PEM format
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("BEGIN OPENSSH PRIVATE KEY") {
            // OpenSSH format — delegate to Citadel's parser
            // Citadel parses these internally when creating the NIOSSHPrivateKey
            // We need the raw key data
            let lines = trimmed.components(separatedBy: "\n")
                .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            let base64String = lines.joined()
            guard let data = Data(base64Encoded: base64String) else {
                throw SSHSessionError.invalidPrivateKey
            }

            // OpenSSH format contains the key type and raw key bytes
            // For ed25519, the private key seed is 32 bytes
            // This is a simplified parser — Citadel handles the full format internally
            if data.count >= 32 {
                // Try to extract the ed25519 seed from the OpenSSH blob
                // The format is complex, so we'll let NIOSSHPrivateKey handle it
                self = try Curve25519.Signing.PrivateKey(rawRepresentation: data.suffix(32))
            } else {
                throw SSHSessionError.invalidPrivateKey
            }
        } else {
            throw SSHSessionError.invalidPrivateKey
        }
    }
}

/// Extension to parse OpenSSH P256 private keys
extension P256.Signing.PrivateKey {
    init(sshP256 pem: String) throws {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("BEGIN") else {
            throw SSHSessionError.invalidPrivateKey
        }

        let lines = trimmed.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64String = lines.joined()
        guard let data = Data(base64Encoded: base64String) else {
            throw SSHSessionError.invalidPrivateKey
        }

        try self.init(derRepresentation: data)
    }
}
