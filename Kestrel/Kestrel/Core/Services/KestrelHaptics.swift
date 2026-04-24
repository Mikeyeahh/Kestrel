//
//  KestrelHaptics.swift
//  Kestrel
//
//  Centralised haptic feedback respecting user preferences.
//

import UIKit

enum KestrelHaptics {

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "settings.enableHaptics") as? Bool ?? true
    }

    /// Successful connection — medium impact.
    static func connectionSuccess() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Connection failed — heavy impact.
    static func connectionFailed() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Command sent — light impact.
    static func commandSent() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Copy to clipboard — light impact.
    static func copied() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Button tap — soft impact.
    static func tap() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Warning — notification feedback.
    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Success — notification feedback.
    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
