//
//  VNCView.swift
//  Kestrel
//
//  VNC launcher — hands off to a registered iOS VNC client via the
//  `vnc://` URL scheme (Jump Desktop, Screens, etc.).
//

import SwiftUI

struct VNCView: View {
    let server: SSHServer
    @State private var launchError: String?

    private var effectivePort: Int {
        server.vncPort ?? 5900
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(KestrelColors.phosphorGreen)

            Text(server.name)
                .font(KestrelFonts.display(22, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)

            Text("\(server.host):\(effectivePort)")
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.textMuted)

            Button {
                openVNC()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Open VNC Client")
                }
                .font(KestrelFonts.monoBold(13))
                .foregroundStyle(KestrelColors.background)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(KestrelColors.phosphorGreen)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

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
                Text("Requires a VNC client like Jump Desktop or Screens")
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
    }

    private func openVNC() {
        launchError = nil
        let urlString = "vnc://\(server.host):\(effectivePort)"
        guard let url = URL(string: urlString) else {
            launchError = "Invalid VNC URL: \(urlString)"
            return
        }
        UIApplication.shared.open(url) { success in
            if !success {
                launchError = "No VNC client is registered to handle vnc:// URLs."
            }
        }
    }
}
