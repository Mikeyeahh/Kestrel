//
//  AIOverlaySheet.swift
//  Kestrel
//
//  AI assistant overlay for terminal context analysis.
//  Uses the Anthropic API for streaming responses when an API key is configured.
//

import SwiftUI

struct AIOverlaySheet: View {
    let tab: TerminalTab

    @Environment(\.dismiss) private var dismiss

    @State private var selectedPrompt: String?
    @State private var customPrompt = ""
    @State private var response = ""
    @State private var isStreaming = false
    @State private var extractedCommands: [String] = []
    @State private var streamingTask: Task<Void, Never>?

    @State private var showingRunConfirmation = false
    @State private var commandToRun = ""

    private let quickPrompts = [
        "Explain this output",
        "What went wrong?",
        "How do I fix this?",
    ]

    private let systemPrompt = """
    You are an expert Linux/networking sysadmin assistant embedded in a terminal app. \
    Analyse the terminal output provided and explain what it means. \
    If there is an error, identify the root cause clearly and provide the specific command to fix it. \
    Be concise and technical.
    """

    private var contextLines: String {
        // Take last 20 lines of terminal output
        let lines = tab.transcript
            .components(separatedBy: "\n")
            .suffix(20)
            .joined(separator: "\n")
        return lines.isEmpty ? "(no terminal output)" : lines
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Context preview
                        contextCard

                        // Quick prompts
                        quickPromptsRow

                        // Custom prompt
                        customPromptField

                        // Response
                        if !response.isEmpty || isStreaming {
                            responseCard
                                .id("response-bottom")
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
                .onChange(of: response) { _, _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("response-bottom", anchor: .bottom)
                    }
                }
            }
            .background(KestrelColors.background)
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        streamingTask?.cancel()
                        dismiss()
                    }
                    .foregroundStyle(KestrelColors.textMuted)
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KestrelColors.background)
        .confirmationDialog(
            "Run this command?",
            isPresented: $showingRunConfirmation,
            titleVisibility: .visible
        ) {
            Button("Run") {
                sendToTerminal(commandToRun)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(commandToRun)
        }
        .onDisappear {
            streamingTask?.cancel()
        }
    }

    // MARK: - Context Card

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Terminal Context")
                Spacer()
                Text("\(contextLines.components(separatedBy: "\n").count) lines")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            ScrollView {
                Text(contextLines)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .padding(10)
            .background(KestrelColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
            )
        }
    }

    // MARK: - Quick Prompts

    private var quickPromptsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Quick Prompts")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPrompts, id: \.self) { prompt in
                        Button {
                            sendPrompt(prompt)
                        } label: {
                            Text(prompt)
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.purple.opacity(0.1))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(.purple.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .disabled(isStreaming)
                    }
                }
            }
        }
    }

    // MARK: - Custom Prompt

    private var customPromptField: some View {
        HStack(spacing: 8) {
            TextField("Ask about the output...", text: $customPrompt)
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
                .tint(.purple)
                .onSubmit {
                    if !customPrompt.isEmpty {
                        sendPrompt(customPrompt)
                    }
                }

            Button {
                sendPrompt(customPrompt)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        customPrompt.isEmpty ? KestrelColors.textFaint : .purple
                    )
            }
            .disabled(customPrompt.isEmpty || isStreaming)
        }
    }

    // MARK: - Response Card

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.purple)
                Text("AI Response")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(.purple)
                Spacer()

                if isStreaming {
                    Button {
                        streamingTask?.cancel()
                        isStreaming = false
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(KestrelColors.red)
                    }

                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.purple)
                }
            }

            Text(response + (isStreaming ? "▌" : ""))
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Extracted commands
            if !extractedCommands.isEmpty {
                Divider()
                    .background(KestrelColors.cardBorder)

                ForEach(extractedCommands, id: \.self) { command in
                    Button {
                        commandToRun = command
                        showingRunConfirmation = true
                    } label: {
                        HStack(spacing: 8) {
                            Text("$")
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(KestrelColors.phosphorGreen)
                            Text(command)
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(KestrelColors.textPrimary)
                                .lineLimit(2)
                            Spacer()
                            Text("Run this fix")
                                .font(KestrelFonts.mono(9))
                                .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.7))
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(KestrelColors.phosphorGreen)
                        }
                        .padding(10)
                        .background(KestrelColors.phosphorGreenDim)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.purple.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func sendPrompt(_ prompt: String) {
        guard !isStreaming else { return }
        isStreaming = true
        response = ""
        extractedCommands = []
        customPrompt = ""

        // Build the full prompt with context
        let fullPrompt = """
        Terminal output:
        ```
        \(contextLines)
        ```

        User question: \(prompt)
        """

        streamingTask = Task {
            await streamAIResponse(prompt: fullPrompt)
        }
    }

    /// Stream response from AI API. Falls back to simulated response if no API key is set.
    private func streamAIResponse(prompt: String) async {
        // Check for API key in UserDefaults or Keychain
        let apiKey = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""

        guard !apiKey.isEmpty else {
            await simulateAIResponse(prompt: prompt)
            return
        }

        // Build the API request
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "stream": true,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            await MainActor.run {
                response = "Error: Failed to encode request."
                isStreaming = false
            }
            return
        }
        request.httpBody = httpBody

        do {
            let (bytes, httpResponse) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = httpResponse as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run {
                    response = "Error: API request failed. Check your API key in Settings."
                    isStreaming = false
                }
                return
            }

            // Parse SSE stream
            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }

                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))

                guard jsonString != "[DONE]",
                      let data = jsonString.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                let eventType = event["type"] as? String

                if eventType == "content_block_delta",
                   let delta = event["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    await MainActor.run {
                        response.append(text)
                    }
                }

                if eventType == "message_stop" {
                    break
                }
            }

            await MainActor.run {
                isStreaming = false
                extractCommands()
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run {
                    response += "\n\n[Error: \(error.localizedDescription)]"
                    isStreaming = false
                    extractCommands()
                }
            }
        }
    }

    private func simulateAIResponse(prompt: String) async {
        // Placeholder: In production, replace with actual API streaming call
        let placeholder = """
        Analysing the terminal output...

        This is where the AI response would appear. To enable this feature:

        1. Add your API key in Settings
        2. The terminal context (last 20 lines) is sent as context
        3. Responses stream in token-by-token

        To wire up the real API, add your API key via the Settings tab.
        """

        for char in placeholder {
            guard !Task.isCancelled else { break }
            try? await Task.sleep(for: .milliseconds(15))
            await MainActor.run {
                response.append(char)
            }
        }

        await MainActor.run {
            isStreaming = false
            extractCommands()
        }
    }

    private func extractCommands() {
        // Look for lines that start with $ or are in code blocks
        let lines = response.components(separatedBy: "\n")
        var inCodeBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }

            if inCodeBlock && !trimmed.isEmpty {
                // Lines inside code blocks are likely commands
                let cleaned = trimmed.hasPrefix("$ ") ? String(trimmed.dropFirst(2)) : trimmed
                if !cleaned.hasPrefix("#") && !cleaned.isEmpty {
                    extractedCommands.append(cleaned)
                }
            } else if trimmed.hasPrefix("$ ") {
                extractedCommands.append(String(trimmed.dropFirst(2)))
            }
        }
    }

    private func sendToTerminal(_ command: String) {
        let session = SSHSessionManager.shared.activeSession(for: tab.server.id)
        session?.send(command + "\n")
    }
}
