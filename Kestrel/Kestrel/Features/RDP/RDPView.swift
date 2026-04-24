//
//  RDPView.swift
//  Kestrel
//
//  RDP launcher — hands off to Microsoft Remote Desktop via `rdp://`
//  or falls back to sharing a generated .rdp file.
//

import SwiftUI
import UniformTypeIdentifiers

struct RDPView: View {
    let server: SSHServer
    @State private var launchError: String?
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    private var effectivePort: Int {
        server.rdpPort ?? 3389
    }

    private var endpointText: String {
        let userPrefix = server.username.isEmpty ? "" : "\(server.username)@"
        return "\(userPrefix)\(server.host):\(effectivePort)"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "desktopcomputer")
                .font(.system(size: 56))
                .foregroundStyle(KestrelColors.blue)

            Text(server.name)
                .font(KestrelFonts.display(22, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)

            Text(endpointText)
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.textMuted)

            VStack(spacing: 10) {
                Button {
                    openRemoteDesktop()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Open Remote Desktop")
                    }
                    .font(KestrelFonts.monoBold(13))
                    .foregroundStyle(KestrelColors.background)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(KestrelColors.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    shareRDPFile()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share .rdp file")
                    }
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(KestrelColors.backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if let launchError {
                Text(launchError)
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.red)
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(KestrelColors.textFaint)
                Text("Requires Microsoft Remote Desktop from the App Store")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .padding(.horizontal, 24)
            .multilineTextAlignment(.center)

            if let group = server.group, !group.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(group)
                        .font(KestrelFonts.mono(10))
                }
                .foregroundStyle(KestrelColors.textFaint)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KestrelColors.background)
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                RDPShareSheet(items: [shareURL])
            }
        }
    }

    private func openRemoteDesktop() {
        launchError = nil
        let urlString = "rdp://full%20address=s:\(server.host):\(effectivePort)&username=s:\(server.username)"
        guard let url = URL(string: urlString) else {
            launchError = "Invalid RDP URL"
            return
        }
        UIApplication.shared.open(url) { success in
            if !success {
                launchError = "Microsoft Remote Desktop is not installed."
            }
        }
    }

    private func shareRDPFile() {
        launchError = nil

        let rdpContent = """
        full address:s:\(server.host):\(effectivePort)
        username:s:\(server.username)
        prompt for credentials:i:1
        desktopwidth:i:1920
        desktopheight:i:1080
        session bpp:i:32
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(server.name)-\(UUID().uuidString.prefix(8)).rdp")

        do {
            try rdpContent.write(to: tempURL, atomically: true, encoding: .utf8)
            shareURL = tempURL
            showShareSheet = true
        } catch {
            launchError = "Failed to create RDP file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Share Sheet wrapper

private struct RDPShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
