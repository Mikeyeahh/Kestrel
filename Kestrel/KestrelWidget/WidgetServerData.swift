//
//  WidgetServerData.swift
//  KestrelWidget
//
//  Shared data model between the main app and widget extension.
//  Must be kept in sync with WidgetDataProvider.swift in the main app.
//

import Foundation

struct WidgetServerData: Codable, Identifiable {
    let id: UUID
    let name: String
    let host: String
    let environment: String
    let isOnline: Bool
    let cpuPercent: Double
    let uptime: String
    let lastUpdated: Date
}
