//
//  ContentView.swift
//  Kestrel
//
//  Root TabView with final navigation structure and deep link routing.
//

import SwiftUI

struct ContentView: View {
    @State private var router = NavigationRouter.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            // Tab 1: Servers
            ServersView()
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }
                .tag(KestrelTab.servers)

            // Tab 2: Terminal
            TerminalView()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }
                .tag(KestrelTab.terminal)

            // Tab 3: SFTP File Manager
            SFTPView()
                .tabItem {
                    Label("Files", systemImage: "folder")
                }
                .tag(KestrelTab.files)

            // Tab 4: Commands
            CommandLibraryView()
                .tabItem {
                    Label("Commands", systemImage: "command")
                }
                .tag(KestrelTab.commands)

            // Tab 5: Settings
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(KestrelTab.settings)
        }
        .tint(KestrelColors.phosphorGreen)
    }
}
