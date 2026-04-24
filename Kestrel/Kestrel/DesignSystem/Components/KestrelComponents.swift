//
//  KestrelComponents.swift
//  Kestrel
//

import SwiftUI

// MARK: - TerminalCard

struct TerminalCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .font(KestrelFonts.mono(13))
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
}

// MARK: - ServerCard

struct ServerCard: View {
    let name: String
    let host: String
    let environment: ServerEnvironment
    let status: ServerStatus
    let cpuUsage: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(status: status)
                Text(name)
                    .font(KestrelFonts.monoBold(14))
                    .foregroundStyle(KestrelColors.textPrimary)
                Spacer()
                EnvBadge(env: environment)
            }

            Text(host)
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textMuted)

            HStack(spacing: 6) {
                Text("CPU")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
                MiniBar(progress: cpuUsage, color: barColor(for: cpuUsage))
                Text("\(Int(cpuUsage * 100))%")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textMuted)
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

    private func barColor(for usage: Double) -> Color {
        if usage > 0.85 { return KestrelColors.red }
        if usage > 0.6 { return KestrelColors.amber }
        return KestrelColors.phosphorGreen
    }
}

// MARK: - StatCard

struct StatCard: View {
    let label: String
    let value: String
    let unit: String
    var progress: Double? = nil
    var color: Color = KestrelColors.phosphorGreen

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(KestrelFonts.mono(10))
                .foregroundStyle(KestrelColors.textFaint)
                .tracking(1.2)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(KestrelFonts.display(24, weight: .bold))
                    .foregroundStyle(KestrelColors.textPrimary)
                Text(unit)
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textMuted)
            }

            if let progress {
                MiniBar(progress: progress, color: color)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - EnvBadge

struct EnvBadge: View {
    let env: ServerEnvironment

    var body: some View {
        Text(env.badge)
            .font(KestrelFonts.mono(9))
            .fontWeight(.bold)
            .tracking(0.8)
            .foregroundStyle(env.colour)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(env.colour.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - StatusDot

struct StatusDot: View {
    let status: ServerStatus

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
            .shadow(color: status.color.opacity(isPulsing ? 0.6 : 0.2), radius: isPulsing ? 6 : 2)
            .onAppear {
                guard status == .online else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - MiniBar

struct MiniBar: View {
    let progress: Double
    var color: Color = KestrelColors.phosphorGreen

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))

                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - ServerConnectionLabel

struct ServerConnectionLabel: View {
    let username: String
    let host: String
    var port: Int? = nil
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 0) {
            Text(username)
                .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.8))
            Text("@")
                .foregroundStyle(KestrelColors.textFaint)
            Text(host)
                .foregroundStyle(KestrelColors.textPrimary.opacity(0.85))
            if let port, port != 22 {
                Text(":")
                    .foregroundStyle(KestrelColors.textFaint)
                Text("\(port)")
                    .foregroundStyle(KestrelColors.textMuted)
            }
        }
        .font(KestrelFonts.mono(size))
        .lineLimit(1)
    }
}

// MARK: - SectionLabel

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(KestrelFonts.mono(11))
            .tracking(1.5)
            .foregroundStyle(KestrelColors.textMuted)
    }
}

// MARK: - KestrelTextField

struct KestrelTextField: View {
    let placeholder: String
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(KestrelFonts.mono(14))
            .foregroundStyle(KestrelColors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isFocused ? KestrelColors.cardBorderGreen : KestrelColors.cardBorder,
                        lineWidth: 1
                    )
            )
            .focused($isFocused)
            .tint(KestrelColors.phosphorGreen)
    }
}

// MARK: - Previews

#Preview("Design System") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "Terminal Card")

            TerminalCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("$ ssh root@192.168.1.1")
                    Text("Connected to prod-web-01")
                        .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.6))
                }
            }

            SectionLabel(text: "Server Cards")

            ServerCard(
                name: "prod-web-01",
                host: "192.168.1.10",
                environment: .production,
                status: .online,
                cpuUsage: 0.72
            )

            ServerCard(
                name: "staging-api",
                host: "10.0.0.5",
                environment: .staging,
                status: .warning,
                cpuUsage: 0.91
            )

            ServerCard(
                name: "dev-local",
                host: "127.0.0.1",
                environment: .development,
                status: .offline,
                cpuUsage: 0.12
            )

            SectionLabel(text: "Stat Cards")

            HStack(spacing: 10) {
                StatCard(label: "CPU", value: "72", unit: "%", progress: 0.72)
                StatCard(label: "Memory", value: "3.2", unit: "GB", progress: 0.41, color: KestrelColors.blue)
            }

            SectionLabel(text: "Text Field")

            KestrelTextField(placeholder: "hostname or IP", text: .constant(""))
        }
        .padding(16)
    }
    .background(KestrelColors.background)
    .preferredColorScheme(.dark)
}
