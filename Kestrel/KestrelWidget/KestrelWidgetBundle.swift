//
//  KestrelWidgetBundle.swift
//  KestrelWidget
//
//  WidgetKit extension for Kestrel.
//
//  To add this extension to the project:
//  1. File → New → Target → Widget Extension
//  2. Name: "KestrelWidget"
//  3. Include Configuration App Intent: Yes
//  4. App Group: group.com.getosprey.suite
//  5. Replace generated files with these source files
//

import WidgetKit
import SwiftUI

@main
struct KestrelWidgetBundle: WidgetBundle {
    var body: some Widget {
        ServerStatusWidget()
        FleetOverviewWidget()
    }
}
