//
//  ServerStatsEngine.swift
//  Kestrel
//

import Foundation

// MARK: - Server Stats Models

struct ServerStats: Sendable, Equatable {
    var cpuPercent: Double
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var memoryFree: UInt64
    var diskMounts: [DiskMount]
    var netInterfaces: [NetInterface]
    var uptime: String
    var load1m: Double
    var load5m: Double
    var load15m: Double
    var processes: [ProcessInfo]
    var osName: String
    var osVersion: String
    var kernelVersion: String

    var memoryUsedPercent: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal) * 100.0
    }

    var totalDiskUsed: UInt64 {
        diskMounts.reduce(0) { $0 + $1.used }
    }

    var totalDiskSize: UInt64 {
        diskMounts.reduce(0) { $0 + $1.size }
    }

    static let empty = ServerStats(
        cpuPercent: 0,
        memoryUsed: 0,
        memoryTotal: 0,
        memoryFree: 0,
        diskMounts: [],
        netInterfaces: [],
        uptime: "—",
        load1m: 0,
        load5m: 0,
        load15m: 0,
        processes: [],
        osName: "",
        osVersion: "",
        kernelVersion: ""
    )
}

struct DiskMount: Sendable, Equatable, Identifiable {
    var id: String { mountPoint }
    let filesystem: String
    let mountPoint: String
    let size: UInt64
    let used: UInt64
    let available: UInt64

    var usedPercent: Double {
        guard size > 0 else { return 0 }
        return Double(used) / Double(size) * 100.0
    }
}

struct NetInterface: Sendable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let bytesReceived: UInt64
    let bytesSent: UInt64
    var rxMbps: Double = 0
    var txMbps: Double = 0
}

struct ProcessInfo: Sendable, Equatable, Identifiable {
    var id: String { "\(user)-\(pid)" }
    let user: String
    let pid: Int
    let cpuPercent: Double
    let memPercent: Double
    let command: String
}

// MARK: - Server Stats Engine

@Observable
@MainActor
final class ServerStatsEngine {
    // MARK: - Properties

    private let session: SSHSession
    private(set) var stats: ServerStats?
    private(set) var isPolling: Bool = false
    private(set) var lastError: String?
    private(set) var lastUpdated: Date?

    private var pollingTask: Task<Void, Never>?
    private var pollInterval: TimeInterval
    private var previousNetStats: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousNetTimestamp: Date?

    // MARK: - Init

    init(session: SSHSession, pollInterval: TimeInterval = 3.0) {
        self.session = session
        self.pollInterval = pollInterval
    }

    nonisolated deinit {
        // pollingTask will be cancelled when this object is deallocated
    }

    // MARK: - Polling Control

    func startPolling() {
        guard !isPolling else { return }
        isPolling = true

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                guard self.session.isConnected else {
                    await MainActor.run {
                        self.isPolling = false
                        self.lastError = "Session disconnected"
                    }
                    break
                }

                await self.fetchStats()

                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    func refreshOnce() async {
        await fetchStats()
    }

    // MARK: - Fetch All Stats

    private func fetchStats() async {
        // Run all stat commands concurrently using a combined command
        // This minimises SSH round-trips (1 exec instead of 8)
        let combinedCommand = """
        echo "===CPU===" && top -bn1 | grep 'Cpu(s)' 2>/dev/null || echo "N/A" && \
        echo "===MEMORY===" && free -b 2>/dev/null || echo "N/A" && \
        echo "===DISK===" && df -B1 --output=source,size,used,avail,target 2>/dev/null || df -B1 2>/dev/null || echo "N/A" && \
        echo "===NETWORK===" && cat /proc/net/dev 2>/dev/null || echo "N/A" && \
        echo "===UPTIME===" && uptime -p 2>/dev/null || uptime 2>/dev/null || echo "N/A" && \
        echo "===LOAD===" && cat /proc/loadavg 2>/dev/null || echo "N/A" && \
        echo "===PROCESSES===" && ps aux --sort=-%cpu 2>/dev/null | head -11 || echo "N/A" && \
        echo "===OSINFO===" && (cat /etc/os-release 2>/dev/null; echo "KERNEL=$(uname -r 2>/dev/null)") && \
        echo "===END==="
        """

        do {
            let output = try await session.execute(combinedCommand)
            let sections = parseSections(output)

            let cpu = parseCPU(sections["CPU"] ?? "")
            let memory = parseMemory(sections["MEMORY"] ?? "")
            let disk = parseDisk(sections["DISK"] ?? "")
            let network = parseNetwork(sections["NETWORK"] ?? "")
            let uptime = parseUptime(sections["UPTIME"] ?? "")
            let load = parseLoad(sections["LOAD"] ?? "")
            let processes = parseProcesses(sections["PROCESSES"] ?? "")
            let osInfo = parseOSInfo(sections["OSINFO"] ?? "")

            stats = ServerStats(
                cpuPercent: cpu,
                memoryUsed: memory.used,
                memoryTotal: memory.total,
                memoryFree: memory.free,
                diskMounts: disk,
                netInterfaces: network,
                uptime: uptime,
                load1m: load.0,
                load5m: load.1,
                load15m: load.2,
                processes: processes,
                osName: osInfo.name,
                osVersion: osInfo.version,
                kernelVersion: osInfo.kernel
            )

            lastError = nil
            lastUpdated = .now
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Section Parser

    private func parseSections(_ output: String) -> [String: String] {
        var sections: [String: String] = [:]
        let markers = ["CPU", "MEMORY", "DISK", "NETWORK", "UPTIME", "LOAD", "PROCESSES", "OSINFO"]

        for (index, marker) in markers.enumerated() {
            let start = "===\(marker)==="
            let end: String
            if index + 1 < markers.count {
                end = "===\(markers[index + 1])==="
            } else {
                end = "===END==="
            }

            if let startRange = output.range(of: start),
               let endRange = output.range(of: end) {
                let content = String(output[startRange.upperBound..<endRange.lowerBound])
                sections[marker] = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return sections
    }

    // MARK: - Individual Parsers

    private func parseCPU(_ raw: String) -> Double {
        // Format: %Cpu(s):  2.3 us,  1.0 sy,  0.0 ni, 96.5 id, ...
        // CPU usage = 100 - idle%
        guard let idleMatch = raw.range(of: #"(\d+\.?\d*)\s*(id|idle)"#, options: .regularExpression) else {
            // Try alternative format: just look for a number before "id"
            let components = raw.components(separatedBy: ",")
            for component in components {
                let trimmed = component.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("id") {
                    let parts = trimmed.components(separatedBy: .whitespaces)
                    if let idle = Double(parts.first ?? "") {
                        return max(0, 100.0 - idle)
                    }
                }
            }
            return 0
        }

        let idleString = String(raw[idleMatch])
        let digits = idleString.components(separatedBy: .letters).joined()
            .trimmingCharacters(in: .whitespaces)
        if let idle = Double(digits) {
            return max(0, 100.0 - idle)
        }
        return 0
    }

    private func parseMemory(_ raw: String) -> (total: UInt64, used: UInt64, free: UInt64) {
        // Format from `free -b`:
        //               total        used        free      shared  buff/cache   available
        // Mem:     16777216000   8388608000   4194304000   ...
        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            let lower = line.lowercased()
            guard lower.hasPrefix("mem:") else { continue }

            let parts = line.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            guard parts.count >= 4 else { continue }

            let total = UInt64(parts[1]) ?? 0
            let used = UInt64(parts[2]) ?? 0
            let free = UInt64(parts[3]) ?? 0

            return (total, used, free)
        }
        return (0, 0, 0)
    }

    private func parseDisk(_ raw: String) -> [DiskMount] {
        var mounts: [DiskMount] = []
        let lines = raw.components(separatedBy: "\n")

        for line in lines {
            let parts = line.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            // Skip header lines and non-disk entries
            guard parts.count >= 5 else { continue }
            guard !parts[0].hasPrefix("Filesystem") else { continue }

            // Only include real filesystems
            let fs = parts[0]
            guard fs.hasPrefix("/dev/") || fs.contains("/") else { continue }

            // Try to parse numeric values
            let mountPoint: String
            let size: UInt64
            let used: UInt64
            let available: UInt64

            if parts.count >= 6 {
                // df --output format: source size used avail target
                size = UInt64(parts[1]) ?? 0
                used = UInt64(parts[2]) ?? 0
                available = UInt64(parts[3]) ?? 0
                mountPoint = parts.last ?? parts[4]
            } else {
                size = UInt64(parts[1]) ?? 0
                used = UInt64(parts[2]) ?? 0
                available = UInt64(parts[3]) ?? 0
                mountPoint = parts[4]
            }

            guard size > 0 else { continue }

            // Skip special mounts
            let skipPrefixes = ["/dev/loop", "/snap/"]
            if skipPrefixes.contains(where: { fs.hasPrefix($0) || mountPoint.hasPrefix($0) }) {
                continue
            }

            mounts.append(DiskMount(
                filesystem: fs,
                mountPoint: mountPoint,
                size: size,
                used: used,
                available: available
            ))
        }

        return mounts
    }

    private func parseNetwork(_ raw: String) -> [NetInterface] {
        // Format from /proc/net/dev:
        // Inter-|   Receive                                                |  Transmit
        //  face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets ...
        //    lo: 1234567   8901   0    0    0     0          0         0  1234567 ...
        //  eth0: 9876543  12345   0    0    0     0          0         0  5432109 ...

        var interfaces: [NetInterface] = []
        let lines = raw.components(separatedBy: "\n")
        let now = Date()

        for line in lines {
            guard line.contains(":") else { continue }

            let split = line.components(separatedBy: ":")
            guard split.count >= 2 else { continue }

            let name = split[0].trimmingCharacters(in: .whitespaces)

            // Skip loopback
            guard name != "lo" else { continue }

            let values = split[1].components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            guard values.count >= 9 else { continue }

            let bytesReceived = UInt64(values[0]) ?? 0
            let bytesSent = UInt64(values[8]) ?? 0

            // Calculate Mbps from delta with previous reading
            var rxMbps: Double = 0
            var txMbps: Double = 0

            if let prev = previousNetStats[name],
               let prevTime = previousNetTimestamp {
                let elapsed = now.timeIntervalSince(prevTime)
                if elapsed > 0 {
                    let rxDelta = bytesReceived > prev.rx ? bytesReceived - prev.rx : 0
                    let txDelta = bytesSent > prev.tx ? bytesSent - prev.tx : 0
                    rxMbps = Double(rxDelta) * 8.0 / elapsed / 1_000_000.0
                    txMbps = Double(txDelta) * 8.0 / elapsed / 1_000_000.0
                }
            }

            previousNetStats[name] = (rx: bytesReceived, tx: bytesSent)

            interfaces.append(NetInterface(
                name: name,
                bytesReceived: bytesReceived,
                bytesSent: bytesSent,
                rxMbps: rxMbps,
                txMbps: txMbps
            ))
        }

        previousNetTimestamp = now
        return interfaces
    }

    private func parseUptime(_ raw: String) -> String {
        // `uptime -p` returns: "up 3 days, 4 hours, 23 minutes"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("up ") {
            return String(trimmed.dropFirst(3))
        }
        return trimmed
    }

    private func parseLoad(_ raw: String) -> (Double, Double, Double) {
        // Format: 0.45 0.32 0.28 2/1234 56789
        let parts = raw.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard parts.count >= 3 else { return (0, 0, 0) }

        let load1 = Double(parts[0]) ?? 0
        let load5 = Double(parts[1]) ?? 0
        let load15 = Double(parts[2]) ?? 0

        return (load1, load5, load15)
    }

    private func parseProcesses(_ raw: String) -> [ProcessInfo] {
        // Format from `ps aux --sort=-%cpu | head -11`:
        // USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
        // root         1  2.3  0.1  12345  6789 ?        Ss   Jan01   1:23 /sbin/init

        var processes: [ProcessInfo] = []
        let lines = raw.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            // Skip header
            guard index > 0 else { continue }

            let parts = line.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            // Need at least 11 columns
            guard parts.count >= 11 else { continue }

            let user = parts[0]
            let pid = Int(parts[1]) ?? 0
            let cpu = Double(parts[2]) ?? 0
            let mem = Double(parts[3]) ?? 0
            // Command is everything from column 10 onwards
            let command = parts[10...].joined(separator: " ")

            processes.append(ProcessInfo(
                user: user,
                pid: pid,
                cpuPercent: cpu,
                memPercent: mem,
                command: command
            ))
        }

        return processes
    }

    private func parseOSInfo(_ raw: String) -> (name: String, version: String, kernel: String) {
        var name = ""
        var version = ""
        var kernel = ""

        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("PRETTY_NAME=") {
                name = trimmed
                    .replacingOccurrences(of: "PRETTY_NAME=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            } else if trimmed.hasPrefix("VERSION=") && version.isEmpty {
                version = trimmed
                    .replacingOccurrences(of: "VERSION=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            } else if trimmed.hasPrefix("VERSION_ID=") && version.isEmpty {
                version = trimmed
                    .replacingOccurrences(of: "VERSION_ID=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            } else if trimmed.hasPrefix("KERNEL=") {
                kernel = trimmed
                    .replacingOccurrences(of: "KERNEL=", with: "")
            }
        }

        return (name, version, kernel)
    }
}
