#!/usr/bin/env swift
// latency-probe.swift — Measure keystroke-to-screen latency using Accessibility API + CGEvent
//
// Compile: swiftc -O -o latency-probe latency-probe.swift -framework Cocoa -framework ApplicationServices
//
// Requires Accessibility permission in System Settings.

import Cocoa
import ApplicationServices
import Foundation

// MARK: - Argument Parsing

struct Config {
    var pid: pid_t = 0
    var keystrokes: Int = 100
    var warmup: Int = 10
    var outputPath: String = ""
    var terminalName: String = ""
    var bundleId: String = ""
}

func parseArgs() -> Config {
    var config = Config()
    let args = CommandLine.arguments
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--pid":
            i += 1; config.pid = pid_t(args[i]) ?? 0
        case "--keystrokes":
            i += 1; config.keystrokes = Int(args[i]) ?? 100
        case "--warmup":
            i += 1; config.warmup = Int(args[i]) ?? 10
        case "--output":
            i += 1; config.outputPath = args[i]
        case "--terminal":
            i += 1; config.terminalName = args[i]
        case "--bundle-id":
            i += 1; config.bundleId = args[i]
        default:
            break
        }
        i += 1
    }
    return config
}

// MARK: - Accessibility Helpers

func getAXApp(pid: pid_t) -> AXUIElement {
    return AXUIElementCreateApplication(pid)
}

func getFocusedWindowText(app: AXUIElement) -> String? {
    var focusedWindow: AnyObject?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success else {
        return nil
    }

    // Try to get the AXValue or AXDocument content
    var value: AnyObject?
    if AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXValueAttribute as CFString, &value) == .success {
        return value as? String
    }

    // Fallback: try to find a text area child
    var children: AnyObject?
    guard AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
          let childArray = children as? [AXUIElement] else {
        return nil
    }

    for child in childArray {
        var role: AnyObject?
        AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
        if let roleStr = role as? String,
           (roleStr == "AXTextArea" || roleStr == "AXWebArea" || roleStr == "AXGroup") {
            var childValue: AnyObject?
            if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &childValue) == .success {
                return childValue as? String
            }
        }
    }

    return nil
}

// MARK: - Keystroke Injection

func postKeystroke(char: Character) {
    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!

    var unichar = UniChar(char.asciiValue ?? 0)
    keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
    keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)

    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

// MARK: - Timing

func currentTimeMs() -> Double {
    var time = timespec()
    clock_gettime(CLOCK_MONOTONIC_RAW, &time)
    return Double(time.tv_sec) * 1000.0 + Double(time.tv_nsec) / 1_000_000.0
}

// MARK: - Main

let config = parseArgs()

guard config.pid > 0 else {
    fputs("Error: --pid is required\n", stderr)
    exit(1)
}

guard !config.outputPath.isEmpty else {
    fputs("Error: --output is required\n", stderr)
    exit(1)
}

let app = getAXApp(pid: config.pid)

// Check AX access
guard AXIsProcessTrusted() else {
    fputs("Error: Accessibility access not granted. Enable in System Settings > Privacy & Security > Accessibility.\n", stderr)
    exit(1)
}

let testChars: [Character] = Array("abcdefghijklmnopqrstuvwxyz0123456789")
var latencies: [Double] = []
let totalKeystrokes = config.keystrokes + config.warmup

fputs("Starting latency measurement: \(totalKeystrokes) keystrokes (\(config.warmup) warmup)\n", stderr)

for i in 0..<totalKeystrokes {
    let char = testChars[i % testChars.count]

    // Get baseline text
    let baselineText = getFocusedWindowText(app: app) ?? ""

    // Post keystroke and start timer
    let t0 = currentTimeMs()
    postKeystroke(char: char)

    // Poll for the character to appear (timeout 2 seconds)
    var appeared = false
    while currentTimeMs() - t0 < 2000.0 {
        if let currentText = getFocusedWindowText(app: app),
           currentText != baselineText {
            appeared = true
            break
        }
        usleep(100) // 0.1ms poll interval
    }

    let t1 = currentTimeMs()
    let latency = t1 - t0

    if appeared {
        if i >= config.warmup {
            latencies.append(latency)
        }
        if i < 5 || i % 20 == 0 {
            fputs("  Keystroke \(i + 1)/\(totalKeystrokes): \(String(format: "%.2f", latency)) ms\n", stderr)
        }
    } else {
        fputs("  Keystroke \(i + 1): TIMEOUT (character did not appear within 2s)\n", stderr)
    }

    // Small delay between keystrokes to avoid flooding
    usleep(50_000) // 50ms
}

// Send Return to clear the line
postKeystroke(char: "\r")

// Compute stats
guard !latencies.isEmpty else {
    fputs("Error: no successful latency measurements\n", stderr)
    exit(1)
}

latencies.sort()
let count = latencies.count
let mean = latencies.reduce(0, +) / Double(count)
let variance = latencies.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(count - 1)
let stddev = sqrt(variance)
let p50 = latencies[Int(Double(count) * 0.50)]
let p95 = latencies[Int(Double(count) * 0.95)]
let p99 = latencies[min(Int(Double(count) * 0.99), count - 1)]

// Build JSON result
let result: [String: Any] = [
    "terminal": config.terminalName,
    "bundle_id": config.bundleId,
    "date": ISO8601DateFormatter().string(from: Date()),
    "benchmark": "latency",
    "unit": "ms",
    "stats": [
        "mean": round(mean * 100) / 100,
        "stddev": round(stddev * 100) / 100,
        "min": round(latencies.first! * 100) / 100,
        "max": round(latencies.last! * 100) / 100,
        "p50": round(p50 * 100) / 100,
        "p95": round(p95 * 100) / 100,
        "p99": round(p99 * 100) / 100,
        "count": count
    ],
    "raw": latencies.map { round($0 * 100) / 100 }
]

let jsonData = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try! jsonData.write(to: URL(fileURLWithPath: config.outputPath))

fputs("Latency results: mean=\(String(format: "%.2f", mean))ms p50=\(String(format: "%.2f", p50))ms p95=\(String(format: "%.2f", p95))ms p99=\(String(format: "%.2f", p99))ms\n", stderr)
