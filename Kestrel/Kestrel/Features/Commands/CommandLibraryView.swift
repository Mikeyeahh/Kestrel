//
//  CommandLibraryView.swift
//  Kestrel
//
//  Command library with search, categories, variable substitution, and send-to-terminal.
//

import SwiftUI
import SwiftData

// MARK: - Command Sheet Type

enum CommandSheetType: Identifiable {
    case variablePrompt(SavedCommand)
    case sendConfirm(SavedCommand)

    var id: String {
        switch self {
        case .variablePrompt(let cmd): "var_\(cmd.id)"
        case .sendConfirm(let cmd): "send_\(cmd.id)"
        }
    }
}

// MARK: - Command Library View

struct CommandLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedCommand.useCount, order: .reverse) private var commands: [SavedCommand]
    @Query(sort: \SSHServer.orderIndex) private var servers: [SSHServer]

    @State private var searchText = ""
    @State private var selectedCategory: CommandCategory? = nil
    @State private var showingAddCommand = false

    // Send-to-terminal flow
    @State private var activeCommandSheet: CommandSheetType?
    @State private var resolvedCommand = ""
    @State private var variableValues: [String: String] = [:]

    // Edit flow
    @State private var commandToEdit: SavedCommand?
    @State private var showingEditCommand = false

    // Quick run inline
    @State private var quickRunCommand: SavedCommand?
    @State private var quickRunOutput: String?
    @State private var quickRunError: String?
    @State private var quickRunning = false

    @State private var revenueCat = KestrelRevenueCatService.shared
    @State private var showingPaywall = false

    private var sessionManager: SSHSessionManager { .shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category pills
                categoryPills

                // Command list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if filteredCommands.isEmpty {
                            emptyState
                        } else {
                            // Recently used section (only when showing all, no search)
                            if selectedCategory == nil && searchText.isEmpty {
                                let recent = commands.filter { $0.useCount > 0 }
                                    .sorted { $0.useCount > $1.useCount }
                                    .prefix(5)
                                if !recent.isEmpty {
                                    recentSection(Array(recent))
                                }
                            }

                            // Favourites section
                            let favs = filteredCommands.filter(\.isFavourite)
                            if !favs.isEmpty {
                                favouritesSection(favs)
                            }

                            // All commands
                            allCommandsSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 40)
                }
            }
            .background(KestrelColors.background)
            .navigationTitle("Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if revenueCat.canAccess(.commandLibraryEdit) {
                            showingAddCommand = true
                        } else {
                            showingPaywall = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(KestrelColors.phosphorGreen)
                            if !revenueCat.isProOrBundle {
                                ProBadge()
                            }
                        }
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search commands..."
            )
            .tint(KestrelColors.phosphorGreen)
        }
        .onAppear {
            BuiltInCommands.seedIfNeeded(into: modelContext)
        }
        .sheet(isPresented: $showingAddCommand) {
            AddEditCommandSheet(mode: .add) { name, command, category, description in
                let cmd = SavedCommand(
                    name: name,
                    command: command,
                    category: category,
                    commandDescription: description
                )
                modelContext.insert(cmd)
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $showingEditCommand) {
            if let cmd = commandToEdit {
                AddEditCommandSheet(
                    mode: .edit(cmd)
                ) { name, command, category, description in
                    cmd.name = name
                    cmd.command = command
                    cmd.category = category
                    cmd.commandDescription = description
                    try? modelContext.save()
                }
            }
        }
        .sheet(item: $activeCommandSheet) { sheetType in
            switch sheetType {
            case .variablePrompt(let cmd):
                VariablePromptSheet(
                    command: cmd,
                    variableValues: $variableValues
                ) { finalCommand in
                    resolvedCommand = finalCommand
                    activeCommandSheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        activeCommandSheet = .sendConfirm(cmd)
                    }
                }
            case .sendConfirm(let cmd):
                SendToTerminalSheet(
                    command: cmd,
                    resolvedCommand: resolvedCommand,
                    servers: servers,
                    sessionManager: sessionManager
                ) {
                    cmd.useCount += 1
                    try? modelContext.save()
                    activeCommandSheet = nil
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            KestrelPaywallView()
        }
    }

    // MARK: - Filtering

    private var filteredCommands: [SavedCommand] {
        var result = commands

        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.command.lowercased().contains(query) ||
                ($0.commandDescription?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    // MARK: - Category Pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryPill(label: "All", category: nil)

                ForEach(CommandCategory.allCases, id: \.self) { cat in
                    categoryPill(label: cat.displayName, category: cat)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KestrelColors.cardBorder)
                .frame(height: 1)
        }
    }

    private func categoryPill(label: String, category: CommandCategory?) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            withAnimation(.snappy(duration: 0.15)) {
                selectedCategory = category
            }
        } label: {
            Text(label)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(isSelected ? KestrelColors.background : KestrelColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? KestrelColors.phosphorGreen : KestrelColors.backgroundCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? KestrelColors.phosphorGreen : KestrelColors.cardBorder,
                            lineWidth: 1
                        )
                )
        }
    }

    // MARK: - Recent Section

    private func recentSection(_ recent: [SavedCommand]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Recently Used")
                .padding(.top, 4)

            ForEach(recent) { cmd in
                commandCard(cmd)
            }
        }
    }

    // MARK: - Favourites Section

    private func favouritesSection(_ favs: [SavedCommand]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Favourites")
                .padding(.top, 4)

            ForEach(favs) { cmd in
                commandCard(cmd)
            }
        }
    }

    // MARK: - All Commands Section

    private var allCommandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: selectedCategory?.displayName ?? "All Commands")
                .padding(.top, 4)

            ForEach(filteredCommands) { cmd in
                commandCard(cmd)
            }
        }
    }

    // MARK: - Command Card

    private func commandCard(_ cmd: SavedCommand) -> some View {
        Button {
            handleCommandTap(cmd)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(cmd.name)
                        .font(KestrelFonts.monoBold(13))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Category badge
                    categoryBadge(cmd.category)

                    // Favourite star
                    Button {
                        cmd.isFavourite.toggle()
                        try? modelContext.save()
                    } label: {
                        Image(systemName: cmd.isFavourite ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(cmd.isFavourite ? KestrelColors.amber : KestrelColors.textFaint)
                    }
                    .buttonStyle(.plain)
                }

                // Command string
                Text(cmd.command)
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.6))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Bottom row: description + use count
                HStack {
                    if let desc = cmd.commandDescription, !desc.isEmpty {
                        Text(desc)
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)
                            .lineLimit(1)
                    }

                    Spacer()

                    if cmd.useCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 8))
                            Text("\(cmd.useCount)")
                                .font(KestrelFonts.mono(9))
                        }
                        .foregroundStyle(KestrelColors.textFaint)
                    }
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
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = cmd.command
            } label: {
                Label("Copy Command", systemImage: "doc.on.doc")
            }

            Button {
                commandToEdit = cmd
                showingEditCommand = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                duplicateCommand(cmd)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Button {
                cmd.isFavourite.toggle()
                try? modelContext.save()
            } label: {
                Label(
                    cmd.isFavourite ? "Unfavourite" : "Favourite",
                    systemImage: cmd.isFavourite ? "star.slash" : "star"
                )
            }

            Divider()

            Button(role: .destructive) {
                modelContext.delete(cmd)
                try? modelContext.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func categoryBadge(_ category: CommandCategory) -> some View {
        Text(category.displayName.uppercased())
            .font(KestrelFonts.mono(8))
            .fontWeight(.bold)
            .tracking(0.6)
            .foregroundStyle(categoryColor(category))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor(category).opacity(0.12))
            .clipShape(Capsule())
    }

    private func categoryColor(_ category: CommandCategory) -> Color {
        switch category {
        case .system: KestrelColors.blue
        case .networking: KestrelColors.phosphorGreen
        case .docker: KestrelColors.blue
        case .kubernetes: KestrelColors.blue
        case .git: KestrelColors.amber
        case .nginx: KestrelColors.phosphorGreen
        case .files: KestrelColors.amber
        case .custom: .purple
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(KestrelColors.textFaint)

            Text("No commands found")
                .font(KestrelFonts.display(16, weight: .semibold))
                .foregroundStyle(KestrelColors.textMuted)

            if !searchText.isEmpty {
                Text("Try a different search term")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textFaint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Actions

    private func handleCommandTap(_ cmd: SavedCommand) {
        let vars = CommandVariableParser.extractVariables(from: cmd.command)

        if vars.isEmpty {
            resolvedCommand = cmd.command
            variableValues = [:]
            activeCommandSheet = .sendConfirm(cmd)
        } else {
            variableValues = Dictionary(uniqueKeysWithValues: vars.map { ($0, "") })
            activeCommandSheet = .variablePrompt(cmd)
        }
    }

    private func duplicateCommand(_ cmd: SavedCommand) {
        let dupe = SavedCommand(
            name: "\(cmd.name) (copy)",
            command: cmd.command,
            category: cmd.category,
            commandDescription: cmd.commandDescription
        )
        modelContext.insert(dupe)
        try? modelContext.save()
    }
}

// MARK: - Variable Parser

enum CommandVariableParser {
    /// Extracts unique variable names from {variableName} placeholders.
    static func extractVariables(from command: String) -> [String] {
        let pattern = #"\{([a-zA-Z_][a-zA-Z0-9_]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(command.startIndex..., in: command)
        let matches = regex.matches(in: command, range: range)

        var seen = Set<String>()
        var result: [String] = []

        for match in matches {
            if let varRange = Range(match.range(at: 1), in: command) {
                let name = String(command[varRange])
                if !seen.contains(name) {
                    seen.insert(name)
                    result.append(name)
                }
            }
        }
        return result
    }

    /// Substitutes {variableName} placeholders with provided values.
    static func resolve(command: String, variables: [String: String]) -> String {
        var result = command
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    /// Formats a variable name for display: snake_case → Title Case
    static func displayName(for variable: String) -> String {
        variable
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// MARK: - Variable Prompt Sheet

struct VariablePromptSheet: View {
    let command: SavedCommand
    @Binding var variableValues: [String: String]
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var variables: [String] {
        CommandVariableParser.extractVariables(from: command.command)
    }

    private var isComplete: Bool {
        variables.allSatisfy { !(variableValues[$0]?.isEmpty ?? true) }
    }

    private var resolvedPreview: String {
        CommandVariableParser.resolve(command: command.command, variables: variableValues)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Command name
                    VStack(alignment: .leading, spacing: 4) {
                        Text(command.name)
                            .font(KestrelFonts.monoBold(15))
                            .foregroundStyle(KestrelColors.textPrimary)

                        Text(command.command)
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.5))
                    }

                    // Variable fields
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "Variables")

                        ForEach(variables, id: \.self) { varName in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(CommandVariableParser.displayName(for: varName))
                                    .font(KestrelFonts.mono(11))
                                    .foregroundStyle(KestrelColors.textMuted)

                                TextField(varName, text: binding(for: varName))
                                    .font(KestrelFonts.mono(14))
                                    .foregroundStyle(KestrelColors.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(KestrelColors.backgroundCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                                    )
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .tint(KestrelColors.phosphorGreen)
                            }
                        }
                    }

                    // Preview
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Preview")

                        Text(resolvedPreview)
                            .font(KestrelFonts.mono(12))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(KestrelColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                            )
                    }

                    // Send button
                    Button {
                        onSubmit(resolvedPreview)
                    } label: {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Send to Terminal")
                        }
                        .font(KestrelFonts.monoBold(13))
                        .foregroundStyle(isComplete ? KestrelColors.background : KestrelColors.textFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isComplete ? KestrelColors.phosphorGreen : KestrelColors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(!isComplete)
                }
                .padding(16)
            }
            .background(KestrelColors.background)
            .navigationTitle("Fill Variables")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(KestrelColors.textMuted)
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KestrelColors.background)
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { variableValues[key] ?? "" },
            set: { variableValues[key] = $0 }
        )
    }
}

// MARK: - Send to Terminal Sheet

struct SendToTerminalSheet: View {
    let command: SavedCommand
    let resolvedCommand: String
    let servers: [SSHServer]
    let sessionManager: SSHSessionManager
    let onSent: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isRunning = false
    @State private var commandOutput: String?
    @State private var outputError: String?
    @State private var selectedServer: SSHServer?

    private var activeSessions: [(server: SSHServer, session: SSHSession)] {
        servers.compactMap { server in
            if let session = sessionManager.activeSession(for: server.id), session.isConnected {
                return (server, session)
            }
            return nil
        }
    }

    private var disconnectedServers: [SSHServer] {
        servers.filter { server in
            sessionManager.activeSession(for: server.id)?.isConnected != true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Command preview
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Command")

                        Text(resolvedCommand)
                            .font(KestrelFonts.mono(13))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(KestrelColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                            )
                    }

                    // Output area
                    if isRunning || commandOutput != nil || outputError != nil {
                        outputSection
                    }

                    // Active sessions — send to terminal
                    if !activeSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "Send to Terminal")

                            ForEach(activeSessions, id: \.server.id) { item in
                                Button {
                                    item.session.send(resolvedCommand + "\n")
                                    onSent()
                                    dismiss()
                                } label: {
                                    serverRow(server: item.server, icon: "paperplane.fill", iconColor: KestrelColors.phosphorGreen)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Quick run — execute on any server and show output
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Quick Run")

                        if servers.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: 24))
                                    .foregroundStyle(KestrelColors.textFaint)
                                Text("No servers configured")
                                    .font(KestrelFonts.mono(12))
                                    .foregroundStyle(KestrelColors.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        } else {
                            ForEach(servers) { server in
                                Button {
                                    quickRun(on: server)
                                } label: {
                                    serverRow(
                                        server: server,
                                        icon: "bolt.fill",
                                        iconColor: KestrelColors.amber,
                                        showStatus: true
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isRunning)
                            }
                        }
                    }

                    // Copy button
                    Button {
                        UIPasteboard.general.string = commandOutput ?? resolvedCommand
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text(commandOutput != nil ? "Copy Output" : "Copy Command")
                        }
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(KestrelColors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }
            .background(KestrelColors.background)
            .navigationTitle("Run Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(KestrelColors.textMuted)
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KestrelColors.background)
    }

    // MARK: - Output Section

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Output")
                Spacer()
                if let server = selectedServer {
                    Text(server.name)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textFaint)
                }
            }

            Group {
                if isRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(KestrelColors.phosphorGreen)
                        Text("Running…")
                            .font(KestrelFonts.mono(12))
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                } else if let error = outputError {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(KestrelColors.red)
                        Text(error)
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                } else if let output = commandOutput {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(output.isEmpty ? "(no output)" : output)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(output.isEmpty ? KestrelColors.textFaint : KestrelColors.phosphorGreen)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .frame(maxHeight: 200)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        outputError != nil ? KestrelColors.red.opacity(0.3) : KestrelColors.cardBorderGreen,
                        lineWidth: 1
                    )
            )
        }
    }

    // MARK: - Server Row

    private func serverRow(server: SSHServer, icon: String, iconColor: Color, showStatus: Bool = false) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(server.environment.colour)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(KestrelFonts.monoBold(13))
                    .foregroundStyle(KestrelColors.textPrimary)
                ServerConnectionLabel(
                    username: server.username,
                    host: server.host
                )
            }

            Spacer()

            if showStatus {
                let isOnline = sessionManager.activeSession(for: server.id)?.isConnected == true
                Circle()
                    .fill(isOnline ? KestrelColors.phosphorGreen : KestrelColors.textFaint)
                    .frame(width: 5, height: 5)
            }

            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
        }
        .padding(12)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Quick Run

    private func quickRun(on server: SSHServer) {
        isRunning = true
        commandOutput = nil
        outputError = nil
        selectedServer = server

        Task {
            do {
                // Use existing session or create a new one
                let session = try await sessionManager.openSession(for: server)
                let output = try await session.execute(resolvedCommand)
                commandOutput = output
                onSent()
            } catch {
                outputError = error.localizedDescription
            }
            isRunning = false
        }
    }
}

// MARK: - Add/Edit Command Sheet

enum CommandSheetMode {
    case add
    case edit(SavedCommand)
}

struct AddEditCommandSheet: View {
    let mode: CommandSheetMode
    let onSave: (String, String, CommandCategory, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var command = ""
    @State private var category: CommandCategory = .custom
    @State private var commandDescription = ""

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var title: String {
        isEditing ? "Edit Command" : "New Command"
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var detectedVariables: [String] {
        CommandVariableParser.extractVariables(from: command)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Name")
                        TextField("e.g. Check disk usage", text: $name)
                            .font(KestrelFonts.mono(14))
                            .foregroundStyle(KestrelColors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                            )
                            .tint(KestrelColors.phosphorGreen)
                    }

                    // Command
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Command")
                        TextField("e.g. df -h {path}", text: $command, axis: .vertical)
                            .font(KestrelFonts.mono(14))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                            .lineLimit(3...6)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(KestrelColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                            )
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .tint(KestrelColors.phosphorGreen)

                        Text("Use {variableName} for dynamic values")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)
                    }

                    // Detected variables preview
                    if !detectedVariables.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "Detected Variables")

                            FlowLayout(spacing: 6) {
                                ForEach(detectedVariables, id: \.self) { v in
                                    Text("{\(v)}")
                                        .font(KestrelFonts.mono(11))
                                        .foregroundStyle(KestrelColors.amber)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(KestrelColors.amber.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Category
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Category")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CommandCategory.allCases, id: \.self) { cat in
                                    Button {
                                        category = cat
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: cat.icon)
                                                .font(.system(size: 10))
                                            Text(cat.displayName)
                                                .font(KestrelFonts.mono(11))
                                        }
                                        .foregroundStyle(
                                            category == cat ? KestrelColors.background : KestrelColors.textMuted
                                        )
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(
                                            category == cat ? KestrelColors.phosphorGreen : KestrelColors.backgroundCard
                                        )
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(
                                                    category == cat ? KestrelColors.phosphorGreen : KestrelColors.cardBorder,
                                                    lineWidth: 1
                                                )
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Description (optional)")
                        TextField("What does this command do?", text: $commandDescription)
                            .font(KestrelFonts.mono(13))
                            .foregroundStyle(KestrelColors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                            )
                            .tint(KestrelColors.phosphorGreen)
                    }

                    // Save button
                    Button {
                        let desc = commandDescription.isEmpty ? nil : commandDescription
                        onSave(name.trimmingCharacters(in: .whitespaces),
                               command.trimmingCharacters(in: .whitespaces),
                               category,
                               desc)
                        dismiss()
                    } label: {
                        Text(isEditing ? "Save Changes" : "Add Command")
                            .font(KestrelFonts.monoBold(13))
                            .foregroundStyle(isValid ? KestrelColors.background : KestrelColors.textFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isValid ? KestrelColors.phosphorGreen : KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(!isValid)
                }
                .padding(16)
            }
            .background(KestrelColors.background)
            .navigationTitle(title)
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
            if case .edit(let cmd) = mode {
                name = cmd.name
                command = cmd.command
                category = cmd.category
                commandDescription = cmd.commandDescription ?? ""
            }
        }
    }
}

// MARK: - Flow Layout (for variable tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func flowLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
