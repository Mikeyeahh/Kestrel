//
//  ImportFromOspreySheet.swift
//  Kestrel
//
//  Import hosts discovered by OSPREY's LAN scanner into Kestrel as SSH servers.
//

import SwiftUI
import SwiftData

// MARK: - Import Host Config

@Observable
class ImportHostConfig: Identifiable {
    let id = UUID()
    let host: DiscoveredHost
    var isSelected: Bool
    var username: String = "root"
    var authMethod: AuthMethod = .password

    init(host: DiscoveredHost, isSelected: Bool = true) {
        self.host = host
        self.isSelected = isSelected
    }
}

// MARK: - Import Sheet

struct ImportFromOspreySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SSHServer.orderIndex) private var existingServers: [SSHServer]

    let discoveredHosts: [DiscoveredHost]

    @State private var configs: [ImportHostConfig] = []
    @State private var importedCount = 0
    @State private var showingResult = false

    private var selectedCount: Int {
        configs.filter(\.isSelected).count
    }

    /// Hosts not already saved as servers (match by IP).
    private var newHosts: [DiscoveredHost] {
        let existingIPs = Set(existingServers.map(\.host))
        return discoveredHosts.filter { !existingIPs.contains($0.ip) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Summary
                    summaryBanner

                    if configs.isEmpty {
                        emptyState
                    } else {
                        // Select all
                        HStack {
                            Button {
                                let allSelected = configs.allSatisfy(\.isSelected)
                                for config in configs {
                                    config.isSelected = !allSelected
                                }
                            } label: {
                                Text(configs.allSatisfy(\.isSelected) ? "Deselect All" : "Select All")
                                    .font(KestrelFonts.mono(11))
                                    .foregroundStyle(KestrelColors.phosphorGreen)
                            }
                            Spacer()
                            Text("\(selectedCount) selected")
                                .font(KestrelFonts.mono(10))
                                .foregroundStyle(KestrelColors.textFaint)
                        }

                        // Host list
                        ForEach(configs) { config in
                            hostConfigCard(config)
                        }

                        // Import button
                        Button {
                            importSelected()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import \(selectedCount) Host\(selectedCount == 1 ? "" : "s")")
                            }
                            .font(KestrelFonts.monoBold(13))
                            .foregroundStyle(selectedCount > 0 ? KestrelColors.background : KestrelColors.textFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedCount > 0 ? KestrelColors.phosphorGreen : KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(selectedCount == 0)
                    }
                }
                .padding(16)
            }
            .background(KestrelColors.background)
            .navigationTitle("Import from OSPREY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(KestrelColors.textMuted)
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KestrelColors.background)
        .onAppear {
            configs = newHosts.map { ImportHostConfig(host: $0, isSelected: $0.hasSSH) }
        }
        .alert("Imported", isPresented: $showingResult) {
            Button("Done") { dismiss() }
        } message: {
            Text("\(importedCount) server\(importedCount == 1 ? "" : "s") added to Kestrel")
        }
    }

    // MARK: - Summary Banner

    private var summaryBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 20))
                .foregroundStyle(KestrelColors.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("OSPREY LAN Scan")
                    .font(KestrelFonts.monoBold(12))
                    .foregroundStyle(KestrelColors.textPrimary)
                Text("\(discoveredHosts.count) hosts found · \(newHosts.count) new")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textMuted)
            }
            Spacer()
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [KestrelColors.blue.opacity(0.06), KestrelColors.phosphorGreen.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(KestrelColors.blue.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Host Config Card

    private func hostConfigCard(_ config: ImportHostConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row with checkbox
            HStack(spacing: 10) {
                Button {
                    config.isSelected.toggle()
                } label: {
                    Image(systemName: config.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(config.isSelected ? KestrelColors.phosphorGreen : KestrelColors.textFaint)
                }

                Image(systemName: config.host.deviceIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(KestrelColors.blue)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.host.hostname ?? config.host.ip)
                        .font(KestrelFonts.monoBold(13))
                        .foregroundStyle(KestrelColors.textPrimary)
                    Text(config.host.ip)
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.textMuted)
                }

                Spacer()

                if config.host.hasSSH {
                    Text("SSH")
                        .font(KestrelFonts.mono(9))
                        .fontWeight(.bold)
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(KestrelColors.phosphorGreenDim)
                        .clipShape(Capsule())
                }
            }

            // Open ports
            if !config.host.openPorts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(config.host.openPorts, id: \.self) { port in
                            Text("\(port)")
                                .font(KestrelFonts.mono(9))
                                .foregroundStyle(port == 22 ? KestrelColors.phosphorGreen : KestrelColors.textFaint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(KestrelColors.backgroundCard)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            port == 22 ? KestrelColors.cardBorderGreen : KestrelColors.cardBorder,
                                            lineWidth: 1
                                        )
                                )
                        }
                    }
                }
            }

            // Auth config (shown when selected)
            if config.isSelected {
                HStack(spacing: 10) {
                    // Username
                    VStack(alignment: .leading, spacing: 3) {
                        Text("User")
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textFaint)
                        TextField("root", text: Bindable(config).username)
                            .font(KestrelFonts.mono(12))
                            .foregroundStyle(KestrelColors.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(KestrelColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                            )
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .tint(KestrelColors.phosphorGreen)
                    }
                    .frame(maxWidth: .infinity)

                    // Auth method
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Auth")
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textFaint)
                        Picker("", selection: Bindable(config).authMethod) {
                            Text("Password").tag(AuthMethod.password)
                            Text("Key").tag(AuthMethod.privateKey)
                        }
                        .pickerStyle(.segmented)
                        .tint(KestrelColors.phosphorGreen)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .background(config.isSelected ? KestrelColors.phosphorGreenDim.opacity(0.3) : KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    config.isSelected ? KestrelColors.cardBorderGreen : KestrelColors.cardBorder,
                    lineWidth: 1
                )
        )
        .animation(.snappy(duration: 0.15), value: config.isSelected)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(KestrelColors.phosphorGreen)
            Text("All hosts already imported")
                .font(KestrelFonts.display(16, weight: .semibold))
                .foregroundStyle(KestrelColors.textMuted)
            Text("Every host OSPREY found is already saved in Kestrel")
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Import

    private func importSelected() {
        let selected = configs.filter(\.isSelected)
        let maxOrder = existingServers.map(\.orderIndex).max() ?? 0

        for (index, config) in selected.enumerated() {
            let server = SSHServer(
                name: config.host.hostname ?? config.host.ip,
                host: config.host.ip,
                port: 22,
                username: config.username,
                authMethod: config.authMethod,
                environment: .other,
                orderIndex: maxOrder + index + 1
            )
            modelContext.insert(server)
        }

        try? modelContext.save()
        importedCount = selected.count
        showingResult = true
    }
}
