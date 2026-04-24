//
//  QuickCommandPickerSheet.swift
//  Kestrel
//
//  Quick command picker presented from the terminal action bar.
//  Lists saved commands grouped by category and sends the selected
//  command directly to the active terminal session.
//

import SwiftUI
import SwiftData

struct QuickCommandPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedCommand.name) private var allCommands: [SavedCommand]

    @State private var searchText = ""
    @State private var selectedCategory: CommandCategory?

    /// Called with the resolved command string when the user taps a command.
    var onSend: (String) -> Void

    // MARK: - Filtered Commands

    private var filteredCommands: [SavedCommand] {
        var result = allCommands

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.command.lowercased().contains(query)
            }
        }

        return result
    }

    private var favourites: [SavedCommand] {
        filteredCommands.filter(\.isFavourite)
    }

    private var recentlyUsed: [SavedCommand] {
        filteredCommands
            .filter { $0.useCount > 0 }
            .sorted { $0.useCount > $1.useCount }
            .prefix(5)
            .map { $0 }
    }

    private var commandsByCategory: [(CommandCategory, [SavedCommand])] {
        let grouped = Dictionary(grouping: filteredCommands) { $0.category }
        return CommandCategory.allCases
            .compactMap { cat in
                guard let cmds = grouped[cat], !cmds.isEmpty else { return nil }
                return (cat, cmds)
            }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Category filter chips
                    categoryChips

                    if filteredCommands.isEmpty {
                        emptyState
                    } else {
                        // Favourites
                        if !favourites.isEmpty && selectedCategory == nil {
                            commandSection(title: "Favourites", icon: "star.fill", commands: favourites)
                        }

                        // Recently used
                        if !recentlyUsed.isEmpty && selectedCategory == nil && searchText.isEmpty {
                            commandSection(title: "Recently Used", icon: "clock", commands: recentlyUsed)
                        }

                        // By category
                        ForEach(commandsByCategory, id: \.0) { category, commands in
                            commandSection(
                                title: category.displayName,
                                icon: category.icon,
                                commands: commands
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(KestrelColors.background)
            .searchable(text: $searchText, prompt: "Search commands")
            .navigationTitle("Quick Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(KestrelFonts.mono(13))
                        .foregroundStyle(KestrelColors.textMuted)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "All", icon: "tray.full", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(CommandCategory.allCases, id: \.self) { category in
                    chipButton(
                        label: category.displayName,
                        icon: category.icon,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = (selectedCategory == category) ? nil : category
                    }
                }
            }
        }
    }

    private func chipButton(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(KestrelFonts.mono(10))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? KestrelColors.phosphorGreenDim : KestrelColors.backgroundCard)
            .foregroundStyle(isSelected ? KestrelColors.phosphorGreen : KestrelColors.textMuted)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? KestrelColors.cardBorderGreen : KestrelColors.cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Command Section

    private func commandSection(title: String, icon: String, commands: [SavedCommand]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(KestrelColors.textFaint)
                Text(title)
                    .font(KestrelFonts.monoBold(11))
                    .foregroundStyle(KestrelColors.textMuted)
            }

            VStack(spacing: 4) {
                ForEach(commands) { command in
                    commandRow(command)
                }
            }
        }
    }

    private func commandRow(_ command: SavedCommand) -> some View {
        Button {
            sendCommand(command)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: command.category.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(command.name)
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .lineLimit(1)

                    Text(command.command)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(KestrelColors.textFaint)
                        .lineLimit(1)
                }

                Spacer()

                if command.isFavourite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(KestrelColors.amber)
                }

                Image(systemName: "paperplane.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 32))
                .foregroundStyle(KestrelColors.textFaint)

            Text("No commands found")
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.textMuted)

            Text("Add commands in the Commands tab")
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func sendCommand(_ command: SavedCommand) {
        command.useCount += 1
        try? modelContext.save()
        onSend(command.command)
        dismiss()
    }
}
