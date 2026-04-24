//
//  OspreyBridgeView.swift
//  Kestrel
//
//  Integration status dashboard for the OSPREY ↔ Kestrel bridge.
//  Shows installed apps, integration features, shared vault, and bundle upgrade.
//

import SwiftUI
import SwiftData

struct OspreyBridgeView: View {
    @State private var bridge = OspreyBridgeService.shared
    @Query(sort: \SSHServer.orderIndex) private var servers: [SSHServer]
    @Query private var keys: [KeychainKey]

    @State private var showingImport = false
    @State private var showingPaywall = false
    @State private var revenueCat = KestrelRevenueCatService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                // App status
                appStatusSection

                // Integration features
                featuresSection

                // Shared vault
                vaultSection

                // Discovered hosts
                if !bridge.discoveredHosts.isEmpty {
                    discoveredSection
                }

                // Actions
                actionsSection

                // Bundle card
                bundleCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(KestrelColors.background)
        .navigationTitle("OSPREY Bridge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(KestrelColors.background, for: .navigationBar)
        .onAppear { bridge.refresh() }
        .sheet(isPresented: $showingImport) {
            ImportFromOspreySheet(discoveredHosts: bridge.discoveredHosts)
        }
        .sheet(isPresented: $showingPaywall) {
            KestrelPaywallView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // OSPREY icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [KestrelColors.blue.opacity(0.2), KestrelColors.phosphorGreen.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 18))
                        .foregroundStyle(KestrelColors.blue)
                }

                Text("↔")
                    .font(.system(size: 18))
                    .foregroundStyle(KestrelColors.textFaint)

                // Kestrel icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(KestrelColors.phosphorGreenDim)
                        .frame(width: 44, height: 44)

                    Text("◈")
                        .font(.system(size: 18))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }

                Spacer()
            }

            Text("OSPREY ↔ KESTREL")
                .font(KestrelFonts.display(22, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)

            Text("Network diagnostics meets server management")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textMuted)
        }
        .padding(.top, 8)
    }

    // MARK: - App Status

    private var appStatusSection: some View {
        VStack(spacing: 8) {
            appStatusRow(
                name: "OSPREY",
                icon: "antenna.radiowaves.left.and.right",
                color: KestrelColors.blue,
                isInstalled: bridge.hasOspreyInstalled
            )
            appStatusRow(
                name: "KESTREL",
                icon: "terminal",
                color: KestrelColors.phosphorGreen,
                isInstalled: true
            )
        }
    }

    private func appStatusRow(name: String, icon: String, color: Color, isInstalled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)

            Text(name)
                .font(KestrelFonts.monoBold(13))
                .foregroundStyle(KestrelColors.textPrimary)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(isInstalled ? KestrelColors.phosphorGreen : KestrelColors.red)
                    .frame(width: 6, height: 6)
                Text(isInstalled ? "Installed" : "Not Installed")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(isInstalled ? KestrelColors.phosphorGreen : KestrelColors.red)
            }
        }
        .padding(12)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Integration Features")

            featureRow(
                icon: "network",
                title: "LAN Host Discovery",
                subtitle: "Import OSPREY-scanned hosts as SSH servers",
                isAvailable: bridge.hasOspreyInstalled
            )
            featureRow(
                icon: "point.3.connected.trianglepath.dotted",
                title: "Traceroute Handoff",
                subtitle: "Diagnose routes to servers via OSPREY",
                isAvailable: bridge.hasOspreyInstalled
            )
            featureRow(
                icon: "waveform.path.ecg",
                title: "Ping Handoff",
                subtitle: "Quick ping tests via OSPREY",
                isAvailable: bridge.hasOspreyInstalled
            )
            featureRow(
                icon: "key",
                title: "Shared Key Vault",
                subtitle: "SSH keys accessible by both apps",
                isAvailable: true
            )
            featureRow(
                icon: "link",
                title: "Deep Link Integration",
                subtitle: "Open servers directly from OSPREY",
                isAvailable: true
            )
        }
    }

    private func featureRow(icon: String, title: String, subtitle: String, isAvailable: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isAvailable ? KestrelColors.blue : KestrelColors.textFaint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(isAvailable ? KestrelColors.textPrimary : KestrelColors.textMuted)
                Text(subtitle)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            Spacer()

            Image(systemName: isAvailable ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 14))
                .foregroundStyle(isAvailable ? KestrelColors.phosphorGreen : KestrelColors.textFaint)
        }
        .padding(10)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Vault

    private var vaultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Shared Vault")

            HStack(spacing: 16) {
                vaultStat(label: "SSH Keys", value: "\(keys.count)", icon: "key")
                vaultStat(label: "Servers", value: "\(servers.count)", icon: "server.rack")
                vaultStat(label: "App Group", value: "Active", icon: "lock.shield")
            }
            .padding(14)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
            )
        }
    }

    private func vaultStat(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(KestrelColors.phosphorGreen)
            Text(value)
                .font(KestrelFonts.display(18, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)
            Text(label)
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Discovered Hosts

    private var discoveredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Discovered Hosts")
                Spacer()
                if let subnet = bridge.lastScanSubnet {
                    Text(subnet)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textFaint)
                }
            }

            // Show first 5 hosts
            ForEach(Array(bridge.discoveredHosts.prefix(5))) { host in
                HStack(spacing: 8) {
                    Image(systemName: host.deviceIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(KestrelColors.blue)
                        .frame(width: 16)

                    Text(host.hostname ?? host.ip)
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    if host.hasSSH {
                        Text("SSH")
                            .font(KestrelFonts.mono(8))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(KestrelColors.phosphorGreenDim)
                            .clipShape(Capsule())
                    }

                    Text(host.ip)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .padding(.vertical, 4)
            }

            if bridge.discoveredHosts.count > 5 {
                Text("+ \(bridge.discoveredHosts.count - 5) more")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            Button {
                showingImport = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                    Text("Import Hosts")
                        .font(KestrelFonts.mono(12))
                }
                .foregroundStyle(KestrelColors.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(KestrelColors.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(KestrelColors.blue.opacity(0.2), lineWidth: 1)
                )
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

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 8) {
            if bridge.hasOspreyInstalled {
                Button {
                    if let url = URL(string: "osprey://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14))
                        Text("Open OSPREY")
                            .font(KestrelFonts.mono(13))
                    }
                    .foregroundStyle(KestrelColors.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(KestrelColors.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(KestrelColors.blue.opacity(0.2), lineWidth: 1)
                    )
                }
            } else {
                // Install OSPREY CTA
                VStack(spacing: 8) {
                    Text("Install OSPREY for network diagnostics")
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.textMuted)
                    Text("LAN scanning · Traceroute · Ping · Wake-on-LAN")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(KestrelColors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Bundle Card

    private var bundleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("SUITE BUNDLE")
                    .font(KestrelFonts.mono(10))
                    .fontWeight(.bold)
                    .tracking(1.5)
                    .foregroundStyle(KestrelColors.amber)

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(KestrelColors.amber)
            }

            Text("Unlock OSPREY Pro + KESTREL Pro together")
                .font(KestrelFonts.monoBold(13))
                .foregroundStyle(KestrelColors.textPrimary)

            Text("One subscription for the complete network toolkit. Shared SSH keys, priority background monitoring, and unlimited servers.")
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textMuted)
                .lineSpacing(2)

            Button {
                showingPaywall = true
            } label: {
                Text("View Bundle")
                    .font(KestrelFonts.monoBold(12))
                    .foregroundStyle(KestrelColors.amber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(KestrelColors.amber.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(KestrelColors.amber.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [KestrelColors.amber.opacity(0.06), KestrelColors.amber.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.amber.opacity(0.2), lineWidth: 1)
        )
    }
}
