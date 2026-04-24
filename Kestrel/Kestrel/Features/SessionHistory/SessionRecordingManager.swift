//
//  SessionRecordingManager.swift
//  Kestrel
//
//  Captures terminal output with precise timestamps and produces
//  asciinema v2 JSON format for playback and export.
//
//  Asciinema v2 format:
//    Line 1: JSON header {"version": 2, "width": 80, "height": 24, "timestamp": ...}
//    Line 2+: [relative_time, "o", "output_data"]
//

import Foundation

// MARK: - Recording Event

struct RecordingEvent {
    let relativeTime: TimeInterval
    let data: String
}

// MARK: - Session Recording Manager

@Observable
@MainActor
final class SessionRecordingManager {

    // MARK: - Singleton

    static let shared = SessionRecordingManager()

    // MARK: - State

    private(set) var isRecording = false
    private(set) var currentSessionID: UUID?
    private var startTime: Date?
    private var events: [RecordingEvent] = []
    private var terminalWidth: Int = 80
    private var terminalHeight: Int = 24

    private init() {}

    // MARK: - Control

    /// Begin recording for a session. Clears any previous recording state.
    func startRecording(sessionID: UUID, width: Int = 80, height: Int = 24) {
        self.currentSessionID = sessionID
        self.startTime = .now
        self.events = []
        self.terminalWidth = width
        self.terminalHeight = height
        self.isRecording = true
    }

    /// Append a chunk of terminal output at the current time.
    func appendOutput(_ data: String) {
        guard isRecording, let start = startTime else { return }
        let relativeTime = Date.now.timeIntervalSince(start)
        events.append(RecordingEvent(relativeTime: relativeTime, data: data))
    }

    /// Append output with an explicit timestamp offset.
    func appendOutput(_ data: String, at timestamp: TimeInterval) {
        guard isRecording else { return }
        events.append(RecordingEvent(relativeTime: timestamp, data: data))
    }

    /// Stop recording and return the asciinema v2 JSON data.
    func stopRecording() -> Data? {
        guard isRecording else { return nil }
        isRecording = false

        let json = buildAsciinemaJSON()
        let data = json.data(using: .utf8)

        // Clean up
        currentSessionID = nil
        startTime = nil
        events = []

        return data
    }

    /// Discard the current recording without saving.
    func cancelRecording() {
        isRecording = false
        currentSessionID = nil
        startTime = nil
        events = []
    }

    // MARK: - Duration

    var currentDuration: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date.now.timeIntervalSince(start)
    }

    var eventCount: Int {
        events.count
    }

    // MARK: - Asciinema Export

    private func buildAsciinemaJSON() -> String {
        var lines: [String] = []

        // Header line
        let header: [String: Any] = [
            "version": 2,
            "width": terminalWidth,
            "height": terminalHeight,
            "timestamp": Int(startTime?.timeIntervalSince1970 ?? Date.now.timeIntervalSince1970),
            "env": ["SHELL": "/bin/bash", "TERM": "xterm-256color"]
        ]

        if let headerData = try? JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]),
           let headerString = String(data: headerData, encoding: .utf8) {
            lines.append(headerString)
        }

        // Event lines: [time, "o", data]
        for event in events {
            let escapedData = escapeJSON(event.data)
            let line = "[\(String(format: "%.6f", event.relativeTime)), \"o\", \"\(escapedData)\"]"
            lines.append(line)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func escapeJSON(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    // Escape all control characters (including ESC \u{1B})
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result += String(scalar)
                }
            }
        }
        return result
    }

    // MARK: - Playback Helpers

    /// Parses asciinema v2 JSON data into timed events for replay.
    static func parseRecording(_ data: Data) -> (header: [String: Any]?, events: [RecordingEvent]) {
        guard let string = String(data: data, encoding: .utf8) else {
            return (nil, [])
        }

        let lines = string.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return (nil, []) }

        // Parse header
        var header: [String: Any]?
        if let headerData = lines[0].data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
            header = parsed
        }

        // Parse events
        var events: [RecordingEvent] = []
        for i in 1..<lines.count {
            let line = lines[i]
            guard let lineData = line.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: lineData) as? [Any],
                  array.count >= 3,
                  let time = array[0] as? Double,
                  let outputData = array[2] as? String else {
                continue
            }
            events.append(RecordingEvent(relativeTime: time, data: outputData))
        }

        return (header, events)
    }
}
