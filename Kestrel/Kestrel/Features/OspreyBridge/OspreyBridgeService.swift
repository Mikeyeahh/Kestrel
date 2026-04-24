//
//  OspreyBridgeService.swift
//  Kestrel
//
//  Singleton service managing the shared App Group integration with OSPREY.
//  Reads LAN scan results, writes server info for diagnosis, and handles deep links.
//

import Foundation
import UIKit

// MARK: - Discovered Host Model

struct DiscoveredHost: Identifiable, Codable, Equatable {
    var id: String { ip }
    let ip: String
    let hostname: String?
    let openPorts: [Int]
    let deviceType: String?
    let lastSeen: Date?

    /// Whether this host likely supports SSH (port 22 open).
    var hasSSH: Bool {
        openPorts.contains(22)
    }

    /// Human-readable device type icon name.
    var deviceIcon: String {
        switch deviceType?.lowercased() {
        case "router", "gateway":  return "wifi.router"
        case "server":             return "server.rack"
        case "desktop", "pc":      return "desktopcomputer"
        case "laptop":             return "laptopcomputer"
        case "phone", "mobile":    return "iphone"
        case "printer":            return "printer"
        case "iot", "embedded":    return "sensor"
        default:                   return "network"
        }
    }

    /// Formatted open ports string.
    var portsDisplay: String {
        openPorts.map(String.init).joined(separator: ", ")
    }
}

// MARK: - Deep Link Action

enum KestrelDeepLinkAction {
    case connect(host: String, port: Int, username: String?)
    case importHost(host: String)
    case terminal(serverID: UUID)
    case files(serverID: UUID, path: String?)
}

// MARK: - OSPREY Bridge Service

@Observable
final class OspreyBridgeService {

    // MARK: - Singleton

    static let shared = OspreyBridgeService()

    // MARK: - Keys

    private enum Keys {
        static let lanScanResults     = "osprey.lanScan.lastResults"
        static let lastTraceroute     = "osprey.traceroute.lastTarget"
        static let lastScanSubnet     = "osprey.lanScan.subnet"
        static let lastScanDate       = "osprey.lanScan.date"
        static let selectedServer     = "kestrel.selectedServer"
    }

    // MARK: - State

    private(set) var discoveredHosts: [DiscoveredHost] = []
    private(set) var lastScanSubnet: String?
    private(set) var lastScanDate: Date?
    private(set) var pendingDeepLink: KestrelDeepLinkAction?

    /// IPs the user has dismissed from the servers view.
    private var dismissedHostIPs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(dismissedHostIPs), forKey: "kestrel.dismissedOspreyHosts")
        }
    }

    /// Discovered hosts minus any the user has dismissed.
    var visibleDiscoveredHosts: [DiscoveredHost] {
        discoveredHosts.filter { !dismissedHostIPs.contains($0.ip) }
    }

    /// Dismiss all currently discovered hosts so the card hides.
    func dismissDiscoveredHosts() {
        dismissedHostIPs.formUnion(discoveredHosts.map(\.ip))
    }

    // MARK: - Shared Defaults

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: kestrelAppGroup)
    }

    // MARK: - Init

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: "kestrel.dismissedOspreyHosts") ?? []
        dismissedHostIPs = Set(saved)
        refresh()
    }

    // MARK: - OSPREY Detection

    var hasOspreyInstalled: Bool {
        guard let url = URL(string: "osprey://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    var hasRecentScanResults: Bool {
        guard let date = lastScanDate else { return false }
        // Consider results stale after 24 hours
        return date.timeIntervalSinceNow > -86400
    }

    // MARK: - Reading from OSPREY

    /// Refreshes all data from shared UserDefaults.
    func refresh() {
        discoveredHosts = fetchDiscoveredHosts()
        lastScanSubnet = sharedDefaults?.string(forKey: Keys.lastScanSubnet)

        if let interval = sharedDefaults?.object(forKey: Keys.lastScanDate) as? TimeInterval {
            lastScanDate = Date(timeIntervalSince1970: interval)
        } else {
            lastScanDate = nil
        }
    }

    /// Reads LAN scan results from OSPREY's shared UserDefaults.
    func fetchDiscoveredHosts() -> [DiscoveredHost] {
        guard let data = sharedDefaults?.data(forKey: Keys.lanScanResults) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([DiscoveredHost].self, from: data)) ?? []
    }

    /// Reads the last traceroute target from OSPREY.
    func fetchLastTracerouteTarget() -> String? {
        sharedDefaults?.string(forKey: Keys.lastTraceroute)
    }

    // MARK: - Writing to OSPREY

    /// Shares a server's host info for OSPREY to diagnose.
    func shareServerForDiagnosis(_ server: SSHServer) {
        let payload: [String: Any] = [
            "host": server.host,
            "port": server.port,
            "name": server.name
        ]
        sharedDefaults?.set(payload, forKey: Keys.selectedServer)

        openOsprey(path: "traceroute", host: server.host)
    }

    /// Opens OSPREY's ping tool targeting the server's host.
    func shareServerForPing(_ server: SSHServer) {
        openOsprey(path: "ping", host: server.host)
    }

    private func openOsprey(path: String, host: String) {
        guard let encoded = host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "osprey://\(path)?host=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Deep Link Handling

    /// Parses an incoming `kestrel://` URL into an action.
    func handleDeepLink(_ url: URL) -> KestrelDeepLinkAction? {
        guard url.scheme == "kestrel" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        func param(_ name: String) -> String? {
            queryItems.first { $0.name == name }?.value
        }

        switch url.host {
        case "connect":
            guard let host = param("host") else { return nil }
            let port = param("port").flatMap(Int.init) ?? 22
            let user = param("user")
            let action = KestrelDeepLinkAction.connect(host: host, port: port, username: user)
            pendingDeepLink = action
            return action

        case "import":
            guard let host = param("host") else { return nil }
            let action = KestrelDeepLinkAction.importHost(host: host)
            pendingDeepLink = action
            return action

        case "terminal":
            guard let idStr = param("serverID"), let id = UUID(uuidString: idStr) else { return nil }
            let action = KestrelDeepLinkAction.terminal(serverID: id)
            pendingDeepLink = action
            return action

        case "files":
            guard let idStr = param("serverID"), let id = UUID(uuidString: idStr) else { return nil }
            let action = KestrelDeepLinkAction.files(serverID: id, path: param("path"))
            pendingDeepLink = action
            return action

        default:
            return nil
        }
    }

    /// Clears any pending deep link after it's been handled.
    func clearPendingDeepLink() {
        pendingDeepLink = nil
    }

    // MARK: - Shared Vault Stats

    /// Counts the number of SSH keys stored in the shared Keychain group.
    var sharedKeyCount: Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.kestrel.ssh-keys",
            kSecAttrAccessGroup as String: kestrelAppGroup,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let items = result as? [Any] {
            return items.count
        }
        return 0
    }
}
