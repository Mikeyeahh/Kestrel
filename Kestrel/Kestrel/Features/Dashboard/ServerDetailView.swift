//
//  ServerDetailView.swift
//  Kestrel
//

import SwiftUI
import Charts

struct ServerDetailView: View {
    let server: SSHServer

    @State private var sessionManager = SSHSessionManager.shared
    @State private var statsEngine: ServerStatsEngine?
    @State private var cpuHistory: [CPUReading] = []
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var selectedProcess: ProcessInfo?
    @State private var showingKillConfirmation = false
    @State private var showingServices = false

    private var session: SSHSession? {
        sessionManager.activeSession(for: server.id)
    }

    private var isConnected: Bool {
        session?.isConnected == true
    }

    private var stats: ServerStats? {
        statsEngine?.stats
    }

    @State private var revenueCat = KestrelRevenueCatService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                connectionErrorBanner
                quickActionsRow

                if isConnected {
                    Group {
                        if stats != nil {
                            dashboardContent
                        } else {
                            skeletonLoading
                        }
                    }
                    .proGated(feature: .serverDashboard)
                } else {
                    offlineState
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .background(KestrelColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startStatsIfConnected() }
        .onDisappear { statsEngine?.stopPolling() }
        .onChange(of: session?.isConnected) { _, newValue in
            if newValue == true {
                startStatsIfConnected()
            } else {
                statsEngine?.stopPolling()
            }
        }
        .onChange(of: statsEngine?.stats?.cpuPercent) { _, newCPU in
            if let cpu = newCPU {
                appendCPUReading(cpu)
            }
        }
        .sheet(item: $selectedProcess) { process in
            ProcessDetailSheet(
                process: process,
                session: session,
                showingKillConfirmation: $showingKillConfirmation
            )
        }
        .navigationDestination(isPresented: $showingServices) {
            if let session {
                ServicesView(server: server, session: session)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        StatusDot(status: isConnected ? .online : .offline)
                        Text(server.name)
                            .font(KestrelFonts.display(26, weight: .bold))
                            .foregroundStyle(KestrelColors.textPrimary)
                    }

                    ServerConnectionLabel(
                        username: server.username,
                        host: server.host,
                        port: server.port,
                        size: 12
                    )

                    if let stats {
                        if !stats.osName.isEmpty {
                            Text(stats.osName)
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(KestrelColors.textFaint)
                        }
                        if !stats.kernelVersion.isEmpty {
                            Text("kernel \(stats.kernelVersion)")
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(KestrelColors.textFaint)
                        }
                    }
                }

                Spacer()

                EnvBadge(env: server.environment)
            }

            // Uptime
            if let stats, !stats.uptime.isEmpty && stats.uptime != "—" {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                    Text("up \(stats.uptime)")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(KestrelColors.phosphorGreenDim)
                .clipShape(Capsule())
            }

            // Connect / Disconnect button
            connectButton
        }
        .padding(.top, 4)
    }

    private var connectButton: some View {
        Button {
            if isConnected {
                disconnect()
            } else {
                connect()
            }
        } label: {
            HStack(spacing: 8) {
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(KestrelColors.phosphorGreen)
                } else {
                    Image(systemName: isConnected ? "bolt.slash.fill" : "bolt.fill")
                        .font(.system(size: 13))
                }

                Text(isConnecting ? "Connecting…" : isConnected ? "Disconnect" : "Connect")
                    .font(KestrelFonts.mono(13))
            }
            .foregroundStyle(isConnected ? KestrelColors.red : KestrelColors.phosphorGreen)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                (isConnected ? KestrelColors.red : KestrelColors.phosphorGreen).opacity(0.1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        (isConnected ? KestrelColors.red : KestrelColors.phosphorGreen).opacity(0.25),
                        lineWidth: 1
                    )
            )
        }
        .disabled(isConnecting)
    }

    @ViewBuilder
    private var connectionErrorBanner: some View {
        if let error = connectionError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(KestrelColors.red)
                Text(error)
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.red)
                    .lineLimit(2)
                Spacer()
                Button {
                    connectionError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(KestrelColors.textMuted)
                }
            }
            .padding(10)
            .background(KestrelColors.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                quickActionButton(icon: "terminal", label: "Terminal", color: KestrelColors.phosphorGreen) {
                    let router = NavigationRouter.shared
                    router.terminalServerID = server.id
                    router.pendingTerminalServer = server
                    router.selectedTab = .terminal
                }
                quickActionButton(icon: "folder", label: "Files", color: KestrelColors.blue) {
                    let router = NavigationRouter.shared
                    router.sftpServerID = server.id
                    router.pendingSFTPServer = server
                    router.selectedTab = .files
                }
                quickActionButton(icon: "gearshape.2", label: "Services", color: KestrelColors.amber) {
                    showingServices = true
                }
                quickActionButton(icon: "sparkles", label: "AI", color: .purple) {
                    let router = NavigationRouter.shared
                    router.terminalServerID = server.id
                    router.pendingTerminalServer = server
                    router.pendingAIOverlay = true
                    router.selectedTab = .terminal
                }
                if OspreyBridgeService.shared.hasOspreyInstalled {
                    quickActionButton(icon: "antenna.radiowaves.left.and.right", label: "Diagnose", color: KestrelColors.blue) {
                        OspreyBridgeService.shared.shareServerForDiagnosis(server)
                    }
                }
            }
        }
    }

    private func quickActionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isConnected ? color : KestrelColors.textFaint)
                Text(label)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(isConnected ? KestrelColors.textMuted : KestrelColors.textFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
            )
        }
        .disabled(!isConnected)
    }

    // MARK: - Dashboard

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            cpuCard
            memoryCard
            diskCard
            networkCard
            processesSection
            servicesQuickView
        }
    }

    // MARK: - CPU Card

    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "CPU")

            HStack(spacing: 16) {
                // Ring gauge
                cpuRingGauge

                VStack(alignment: .leading, spacing: 8) {
                    // CPU %
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(stats?.cpuPercent ?? 0))")
                            .font(KestrelFonts.display(32, weight: .bold))
                            .foregroundStyle(cpuColor)
                        Text("%")
                            .font(KestrelFonts.mono(14))
                            .foregroundStyle(KestrelColors.textMuted)
                    }

                    // Load averages
                    if let stats {
                        HStack(spacing: 12) {
                            loadItem(label: "1m", value: stats.load1m)
                            loadItem(label: "5m", value: stats.load5m)
                            loadItem(label: "15m", value: stats.load15m)
                        }
                    }
                }

                Spacer()
            }

            // Sparkline chart
            if cpuHistory.count > 1 {
                cpuSparkline
                    .frame(height: 60)
            }
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    private var cpuRingGauge: some View {
        let progress = (stats?.cpuPercent ?? 0) / 100.0

        return ZStack {
            Circle()
                .stroke(KestrelColors.textFaint.opacity(0.3), lineWidth: 6)

            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    cpuColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
        }
        .frame(width: 64, height: 64)
    }

    private var cpuSparkline: some View {
        Chart(cpuHistory) { reading in
            LineMark(
                x: .value("Time", reading.timestamp),
                y: .value("CPU", reading.value)
            )
            .foregroundStyle(cpuColor.gradient)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Time", reading.timestamp),
                y: .value("CPU", reading.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [cpuColor.opacity(0.2), cpuColor.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private func loadItem(label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.2f", value))
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textPrimary)
            Text(label)
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
        }
    }

    private var cpuColor: Color {
        guard let cpu = stats?.cpuPercent else { return KestrelColors.phosphorGreen }
        if cpu > 80 { return KestrelColors.red }
        if cpu > 50 { return KestrelColors.amber }
        return KestrelColors.phosphorGreen
    }

    // MARK: - Memory Card

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Memory")

            if let stats {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatBytes(stats.memoryUsed))
                        .font(KestrelFonts.display(24, weight: .bold))
                        .foregroundStyle(KestrelColors.textPrimary)
                    Text("/ \(formatBytes(stats.memoryTotal))")
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.textMuted)
                }

                // Segmented memory bar
                memoryBar(stats: stats)

                HStack {
                    legendDot(color: KestrelColors.phosphorGreen, label: "Used")
                    legendDot(color: KestrelColors.blue, label: "Cached")
                    legendDot(color: KestrelColors.textFaint.opacity(0.3), label: "Free")
                    Spacer()
                    Text("\(Int(stats.memoryUsedPercent))%")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(memoryColor(percent: stats.memoryUsedPercent))
                }
            }
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    private func memoryBar(stats: ServerStats) -> some View {
        let total = max(Double(stats.memoryTotal), 1)
        let usedFraction = Double(stats.memoryUsed) / total
        let freeFraction = Double(stats.memoryFree) / total
        let cachedFraction = max(0, 1.0 - usedFraction - freeFraction)

        return GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(KestrelColors.phosphorGreen)
                    .frame(width: geo.size.width * usedFraction)

                RoundedRectangle(cornerRadius: 3)
                    .fill(KestrelColors.blue)
                    .frame(width: geo.size.width * cachedFraction)

                RoundedRectangle(cornerRadius: 3)
                    .fill(KestrelColors.textFaint.opacity(0.3))
                    .frame(width: geo.size.width * freeFraction)
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
        }
    }

    private func memoryColor(percent: Double) -> Color {
        if percent > 90 { return KestrelColors.red }
        if percent > 70 { return KestrelColors.amber }
        return KestrelColors.phosphorGreen
    }

    // MARK: - Disk Card

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Disk")

            if let stats {
                ForEach(stats.diskMounts) { mount in
                    diskMountRow(mount)
                }
            }
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    private func diskMountRow(_ mount: DiskMount) -> some View {
        let isAlert = mount.usedPercent > 85

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mount.mountPoint)
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textPrimary)

                Spacer()

                Text("\(formatBytes(mount.used)) / \(formatBytes(mount.size))")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textMuted)

                if isAlert {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(KestrelColors.red)
                }
            }

            MiniBar(
                progress: mount.usedPercent / 100.0,
                color: diskColor(percent: mount.usedPercent)
            )

            Text("\(Int(mount.usedPercent))% used")
                .font(KestrelFonts.mono(9))
                .foregroundStyle(diskColor(percent: mount.usedPercent))
        }
        .padding(.vertical, 4)
    }

    private func diskColor(percent: Double) -> Color {
        if percent > 85 { return KestrelColors.red }
        if percent > 70 { return KestrelColors.amber }
        return KestrelColors.phosphorGreen
    }

    // MARK: - Network Card

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Network")

            if let stats {
                ForEach(stats.netInterfaces) { iface in
                    networkInterfaceRow(iface)
                }
            }
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    private func networkInterfaceRow(_ iface: NetInterface) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(iface.name)
                .font(KestrelFonts.monoBold(12))
                .foregroundStyle(KestrelColors.textPrimary)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                    Text(String(format: "%.2f Mbps", iface.rxMbps))
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.textMuted)
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9))
                        .foregroundStyle(KestrelColors.blue)
                    Text(String(format: "%.2f Mbps", iface.txMbps))
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.textMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("↓ \(formatBytes(iface.bytesReceived))")
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.textFaint)
                    Text("↑ \(formatBytes(iface.bytesSent))")
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.textFaint)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Processes

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Top Processes")

            if let stats {
                // Header row
                HStack {
                    Text("COMMAND")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("PID")
                        .frame(width: 50, alignment: .trailing)
                    Text("CPU%")
                        .frame(width: 50, alignment: .trailing)
                    Text("MEM%")
                        .frame(width: 50, alignment: .trailing)
                }
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)

                ForEach(stats.processes.prefix(8)) { process in
                    processRow(process)
                }
            }
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    private func processRow(_ process: ProcessInfo) -> some View {
        Button {
            selectedProcess = process
        } label: {
            HStack {
                Text(processName(process.command))
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(process.pid)")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textFaint)
                    .frame(width: 50, alignment: .trailing)

                Text(String(format: "%.1f", process.cpuPercent))
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(process.cpuPercent > 50 ? KestrelColors.red : KestrelColors.textMuted)
                    .frame(width: 50, alignment: .trailing)

                Text(String(format: "%.1f", process.memPercent))
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(process.memPercent > 50 ? KestrelColors.amber : KestrelColors.textMuted)
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Services Quick View

    private var servicesQuickView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Services")
                Spacer()
                Button {
                    showingServices = true
                } label: {
                    HStack(spacing: 4) {
                        Text("View all")
                            .font(KestrelFonts.mono(11))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(KestrelColors.textMuted)
                }
            }

            // Placeholder — services will be fetched via SSH
            ForEach(["sshd", "nginx", "docker", "postgresql", "redis"], id: \.self) { service in
                HStack(spacing: 8) {
                    Circle()
                        .fill(KestrelColors.textFaint)
                        .frame(width: 6, height: 6)

                    Text(service)
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.textMuted)

                    Spacer()

                    Text("—")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Skeleton Loading

    private var skeletonLoading: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                SkeletonCard()
            }
        }
    }

    // MARK: - Offline State

    private var offlineState: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(KestrelColors.textFaint)

            Text("Server Offline")
                .font(KestrelFonts.display(18, weight: .semibold))
                .foregroundStyle(KestrelColors.textMuted)

            if let lastConnected = server.lastConnected {
                Text("Last seen \(lastConnected.formatted(.relative(presentation: .named)))")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textFaint)
            } else {
                Text("Never connected")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textFaint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Actions

    private func connect() {
        isConnecting = true
        connectionError = nil

        Task {
            do {
                _ = try await sessionManager.openSession(for: server)
            } catch {
                connectionError = error.localizedDescription
            }
            isConnecting = false
        }
    }

    private func disconnect() {
        statsEngine = nil
        sessionManager.closeSession(serverID: server.id)
    }

    private func startStatsIfConnected() {
        guard session?.isConnected == true, statsEngine == nil else { return }
        self.statsEngine = sessionManager.statsEngine(for: server.id)
    }

    private func appendCPUReading(_ value: Double) {
        cpuHistory.append(CPUReading(timestamp: .now, value: value))
        // Keep last 60 readings (3 minutes at 3s interval)
        if cpuHistory.count > 60 {
            cpuHistory.removeFirst(cpuHistory.count - 60)
        }
    }

    // MARK: - Helpers

    private func processName(_ command: String) -> String {
        // Extract just the process name from the full command path
        let components = command.components(separatedBy: "/")
        let name = components.last ?? command
        return name.components(separatedBy: " ").first ?? name
    }
}

// MARK: - CPU Reading Model

struct CPUReading: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

// MARK: - Skeleton Card

struct SkeletonCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(shimmerGradient)
                .frame(width: 80, height: 12)

            RoundedRectangle(cornerRadius: 4)
                .fill(shimmerGradient)
                .frame(height: 20)

            RoundedRectangle(cornerRadius: 4)
                .fill(shimmerGradient)
                .frame(height: 8)
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }

    private var shimmerGradient: some ShapeStyle {
        KestrelColors.textFaint.opacity(isAnimating ? 0.3 : 0.1)
    }
}

// MARK: - Process Detail Sheet

struct ProcessDetailSheet: View {
    let process: ProcessInfo
    let session: SSHSession?
    @Binding var showingKillConfirmation: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var isKilling = false
    @State private var killResult: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Process header
                VStack(alignment: .leading, spacing: 8) {
                    Text(process.command)
                        .font(KestrelFonts.mono(14))
                        .foregroundStyle(KestrelColors.textPrimary)

                    HStack(spacing: 16) {
                        detailItem(label: "PID", value: "\(process.pid)")
                        detailItem(label: "USER", value: process.user)
                        detailItem(label: "CPU", value: String(format: "%.1f%%", process.cpuPercent))
                        detailItem(label: "MEM", value: String(format: "%.1f%%", process.memPercent))
                    }
                }

                if let result = killResult {
                    HStack(spacing: 8) {
                        Image(systemName: result.contains("Error") ? "xmark.circle.fill" : "checkmark.circle.fill")
                        Text(result)
                            .font(KestrelFonts.mono(12))
                    }
                    .foregroundStyle(result.contains("Error") ? KestrelColors.red : KestrelColors.phosphorGreen)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (result.contains("Error") ? KestrelColors.red : KestrelColors.phosphorGreen).opacity(0.1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Kill button
                Button {
                    showingKillConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        if isKilling {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(KestrelColors.red)
                        }
                        Image(systemName: "xmark.circle.fill")
                        Text(isKilling ? "Killing…" : "Kill Process")
                    }
                    .font(KestrelFonts.mono(13))
                    .foregroundStyle(KestrelColors.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(KestrelColors.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(KestrelColors.red.opacity(0.25), lineWidth: 1)
                    )
                }
                .disabled(isKilling)
                .confirmationDialog(
                    "Kill process \(process.pid)?",
                    isPresented: $showingKillConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Kill (SIGTERM)", role: .destructive) {
                        killProcess(signal: "TERM")
                    }
                    Button("Force Kill (SIGKILL)", role: .destructive) {
                        killProcess(signal: "KILL")
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will terminate \(process.command)")
                }

                Spacer()
            }
            .padding(16)
            .background(KestrelColors.background)
            .navigationTitle("Process Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(KestrelColors.textMuted)
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(KestrelColors.background)
    }

    private func detailItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
            Text(value)
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textPrimary)
        }
    }

    private func killProcess(signal: String) {
        guard let session else { return }
        isKilling = true

        Task {
            do {
                let result = try await session.execute("kill -\(signal) \(process.pid) 2>&1 && echo 'OK' || echo 'FAIL'")
                killResult = result.contains("OK") ? "Process killed" : "Error: \(result)"
            } catch {
                killResult = "Error: \(error.localizedDescription)"
            }
            isKilling = false
        }
    }
}

// MARK: - Byte Formatting

func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0

    while value >= 1024 && unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }

    if unitIndex == 0 {
        return "\(bytes) B"
    }
    return String(format: "%.1f %@", value, units[unitIndex])
}
