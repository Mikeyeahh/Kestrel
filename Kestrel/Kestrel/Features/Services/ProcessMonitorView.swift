//
//  ProcessMonitorView.swift
//  Kestrel
//
//  Full process list with sorting, filtering, detail view, and kill support.
//

import SwiftUI

// MARK: - Sort Option

enum ProcessSortOption: String, CaseIterable {
    case cpu = "CPU"
    case memory = "Memory"
    case pid = "PID"
    case name = "Name"
}

// MARK: - Process Monitor View

struct ProcessMonitorView: View {
    let session: SSHSession

    @Environment(\.dismiss) private var dismiss

    @State private var processes: [ProcessInfo] = []
    @State private var sortOption: ProcessSortOption = .cpu
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var loadError: String?

    // Detail / kill
    @State private var selectedProcess: ProcessInfo?
    @State private var showingProcessDetail = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sort bar
                sortBar

                // Process list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if isLoading {
                            loadingState
                        } else if let error = loadError {
                            errorState(error)
                        } else {
                            // Column headers
                            processHeader

                            ForEach(sortedProcesses) { process in
                                processRow(process)
                            }

                            if sortedProcesses.isEmpty {
                                Text("No processes match filter")
                                    .font(KestrelFonts.mono(12))
                                    .foregroundStyle(KestrelColors.textFaint)
                                    .padding(.vertical, 40)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .background(KestrelColors.background)
            .navigationTitle("Processes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(KestrelColors.textMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Text("\(processes.count) total")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)

                        Button {
                            Task { await loadProcesses() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .foregroundStyle(KestrelColors.textMuted)
                        }
                    }
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Filter processes..."
            )
            .tint(KestrelColors.phosphorGreen)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KestrelColors.background)
        .task { await loadProcesses() }
        .sheet(isPresented: $showingProcessDetail) {
            if let process = selectedProcess {
                ProcessKillSheet(process: process, session: session) {
                    // Refresh after kill
                    Task { await loadProcesses() }
                }
            }
        }
    }

    // MARK: - Sorted & Filtered

    private var sortedProcesses: [ProcessInfo] {
        var result = processes

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.command.lowercased().contains(query) ||
                $0.user.lowercased().contains(query) ||
                String($0.pid).contains(query)
            }
        }

        switch sortOption {
        case .cpu:
            result.sort { $0.cpuPercent > $1.cpuPercent }
        case .memory:
            result.sort { $0.memPercent > $1.memPercent }
        case .pid:
            result.sort { $0.pid < $1.pid }
        case .name:
            result.sort { $0.command.lowercased() < $1.command.lowercased() }
        }

        return result
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Sort:")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textFaint)

                ForEach(ProcessSortOption.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.snappy(duration: 0.15)) {
                            sortOption = option
                        }
                    } label: {
                        Text(option.rawValue)
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(
                                sortOption == option
                                    ? KestrelColors.background
                                    : KestrelColors.textMuted
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                sortOption == option
                                    ? KestrelColors.phosphorGreen
                                    : KestrelColors.backgroundCard
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        sortOption == option
                                            ? KestrelColors.phosphorGreen
                                            : KestrelColors.cardBorder,
                                        lineWidth: 1
                                    )
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KestrelColors.cardBorder)
                .frame(height: 1)
        }
    }

    // MARK: - Process Header

    private var processHeader: some View {
        HStack {
            Text("COMMAND")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("USER")
                .frame(width: 50, alignment: .trailing)
            Text("PID")
                .frame(width: 46, alignment: .trailing)
            Text("CPU%")
                .frame(width: 44, alignment: .trailing)
            Text("MEM%")
                .frame(width: 44, alignment: .trailing)
        }
        .font(KestrelFonts.mono(9))
        .foregroundStyle(KestrelColors.textFaint)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: - Process Row

    private func processRow(_ process: ProcessInfo) -> some View {
        Button {
            selectedProcess = process
            showingProcessDetail = true
        } label: {
            HStack {
                Text(shortName(process.command))
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(process.user)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
                    .lineLimit(1)
                    .frame(width: 50, alignment: .trailing)

                Text("\(process.pid)")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
                    .frame(width: 46, alignment: .trailing)

                Text(String(format: "%.1f", process.cpuPercent))
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(cpuColor(process.cpuPercent))
                    .frame(width: 44, alignment: .trailing)

                Text(String(format: "%.1f", process.memPercent))
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(memColor(process.memPercent))
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(KestrelColors.phosphorGreen)
            Text("Loading processes…")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(KestrelColors.red)
            Text(error)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)
            Button {
                Task { await loadProcesses() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.phosphorGreen)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Data

    private func loadProcesses() async {
        isLoading = true
        loadError = nil

        do {
            let output = try await session.execute("ps aux --sort=-%cpu")
            processes = parseProcessOutput(output)
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    private func parseProcessOutput(_ output: String) -> [ProcessInfo] {
        var results: [ProcessInfo] = []
        let lines = output.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            guard index > 0 else { continue } // skip header

            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 11 else { continue }

            let user = parts[0]
            let pid = Int(parts[1]) ?? 0
            let cpu = Double(parts[2]) ?? 0
            let mem = Double(parts[3]) ?? 0
            let command = parts[10...].joined(separator: " ")

            results.append(ProcessInfo(
                user: user,
                pid: pid,
                cpuPercent: cpu,
                memPercent: mem,
                command: command
            ))
        }

        return results
    }

    // MARK: - Helpers

    private func shortName(_ command: String) -> String {
        let components = command.components(separatedBy: "/")
        let name = components.last ?? command
        return name.components(separatedBy: " ").first ?? name
    }

    private func cpuColor(_ value: Double) -> Color {
        if value > 80 { return KestrelColors.red }
        if value > 40 { return KestrelColors.amber }
        return KestrelColors.textMuted
    }

    private func memColor(_ value: Double) -> Color {
        if value > 50 { return KestrelColors.red }
        if value > 25 { return KestrelColors.amber }
        return KestrelColors.textMuted
    }
}

// MARK: - Process Kill Sheet

struct ProcessKillSheet: View {
    let process: ProcessInfo
    let session: SSHSession
    let onKilled: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isKilling = false
    @State private var killResult: String?
    @State private var killIsError = false
    @State private var showingKillConfirmation = false
    @State private var killSignal = "TERM"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Process info card
                VStack(alignment: .leading, spacing: 10) {
                    Text(process.command)
                        .font(KestrelFonts.mono(13))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .textSelection(.enabled)

                    HStack(spacing: 16) {
                        detailItem(label: "PID", value: "\(process.pid)")
                        detailItem(label: "USER", value: process.user)
                        detailItem(
                            label: "CPU",
                            value: String(format: "%.1f%%", process.cpuPercent),
                            color: process.cpuPercent > 50 ? KestrelColors.red : KestrelColors.textPrimary
                        )
                        detailItem(
                            label: "MEM",
                            value: String(format: "%.1f%%", process.memPercent),
                            color: process.memPercent > 50 ? KestrelColors.amber : KestrelColors.textPrimary
                        )
                    }
                }
                .padding(14)
                .background(KestrelColors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                )

                // Kill result banner
                if let result = killResult {
                    HStack(spacing: 8) {
                        Image(systemName: killIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        Text(result)
                            .font(KestrelFonts.mono(11))
                    }
                    .foregroundStyle(killIsError ? KestrelColors.red : KestrelColors.phosphorGreen)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (killIsError ? KestrelColors.red : KestrelColors.phosphorGreen).opacity(0.1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Kill buttons
                VStack(spacing: 10) {
                    Button {
                        killSignal = "TERM"
                        showingKillConfirmation = true
                    } label: {
                        HStack(spacing: 8) {
                            if isKilling && killSignal == "TERM" {
                                ProgressView().scaleEffect(0.7).tint(KestrelColors.amber)
                            }
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Terminate (SIGTERM)")
                        }
                        .font(KestrelFonts.mono(13))
                        .foregroundStyle(KestrelColors.amber)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(KestrelColors.amber.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(KestrelColors.amber.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .disabled(isKilling)

                    Button {
                        killSignal = "KILL"
                        showingKillConfirmation = true
                    } label: {
                        HStack(spacing: 8) {
                            if isKilling && killSignal == "KILL" {
                                ProgressView().scaleEffect(0.7).tint(KestrelColors.red)
                            }
                            Image(systemName: "xmark.circle.fill")
                            Text("Force Kill (SIGKILL)")
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
        .confirmationDialog(
            "Kill process \(process.pid)?",
            isPresented: $showingKillConfirmation,
            titleVisibility: .visible
        ) {
            Button("Send \(killSignal == "TERM" ? "SIGTERM" : "SIGKILL")", role: .destructive) {
                Task { await killProcess() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will \(killSignal == "KILL" ? "forcefully terminate" : "terminate") \"\(shortName(process.command))\" (PID \(process.pid)). This action cannot be undone.")
        }
    }

    private func detailItem(label: String, value: String, color: Color = KestrelColors.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
            Text(value)
                .font(KestrelFonts.mono(12))
                .foregroundStyle(color)
        }
    }

    private func killProcess() async {
        isKilling = true
        killResult = nil

        do {
            let output = try await session.execute(
                "kill -\(killSignal) \(process.pid) 2>&1 && echo '__OK__' || echo '__FAIL__'"
            )
            if output.contains("__OK__") {
                killResult = "Process \(process.pid) killed (\(killSignal))"
                killIsError = false
                onKilled()
            } else {
                let cleaned = output
                    .replacingOccurrences(of: "__FAIL__", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                killResult = cleaned.isEmpty ? "Failed to kill process" : cleaned
                killIsError = true
            }
        } catch {
            killResult = error.localizedDescription
            killIsError = true
        }

        isKilling = false
    }

    private func shortName(_ command: String) -> String {
        let components = command.components(separatedBy: "/")
        let name = components.last ?? command
        return name.components(separatedBy: " ").first ?? name
    }
}
