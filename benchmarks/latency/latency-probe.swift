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
    var verbose: Bool = false
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
        case "--verbose":
            config.verbose = true
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

/// Roles whose AXValue is likely to contain terminal text content.
private let textBearingRoles: Set<String> = ["AXTextArea", "AXTextField", "AXWebArea", "AXStaticText"]

/// Recursively search the AX tree for a text value, up to `maxDepth` levels deep.
/// Checks AXValue on each element, prioritizing text areas and web areas.
func findTextInElement(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 5) -> String? {
    // Try AXValue on this element
    var value: AnyObject?
    if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
       let str = value as? String, !str.isEmpty {
        return str
    }

    guard depth < maxDepth else { return nil }

    // Recurse into children
    var children: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
          let childArray = children as? [AXUIElement] else {
        return nil
    }

    // Prioritize text-bearing roles
    var priorityChildren: [AXUIElement] = []
    var otherChildren: [AXUIElement] = []

    for child in childArray {
        var role: AnyObject?
        AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
        if let roleStr = role as? String, textBearingRoles.contains(roleStr) {
            priorityChildren.append(child)
        } else {
            otherChildren.append(child)
        }
    }

    for child in priorityChildren + otherChildren {
        if let text = findTextInElement(child, depth: depth + 1, maxDepth: maxDepth) {
            return text
        }
    }

    return nil
}

func getFocusedWindowText(app: AXUIElement) -> String? {
    var focusedWindow: AnyObject?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success else {
        return nil
    }

    // AXUIElement is a CFTypeRef — the cast always succeeds when the API returns .success
    let window = focusedWindow as! AXUIElement
    return findTextInElement(window)
}

/// Dump the AX tree structure for debugging (--verbose mode).
func dumpAXTree(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 4) {
    let indent = String(repeating: "  ", count: depth)

    var role: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    let roleStr = (role as? String) ?? "unknown"

    var desc: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &desc)
    let descStr = (desc as? String) ?? ""

    var value: AnyObject?
    let hasValue = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success
    let valuePreview: String
    if hasValue, let str = value as? String {
        let trimmed = str.prefix(60).replacingOccurrences(of: "\n", with: "\\n")
        valuePreview = " value=\"\(trimmed)\""
    } else {
        valuePreview = ""
    }

    fputs("\(indent)[\(roleStr)] \(descStr)\(valuePreview)\n", stderr)

    guard depth < maxDepth else { return }

    var children: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
          let childArray = children as? [AXUIElement] else {
        return
    }

    for child in childArray {
        dumpAXTree(child, depth: depth + 1, maxDepth: maxDepth)
    }
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

// Verbose: dump AX tree to help debug Tesara's Metal editor or other custom views
if config.verbose {
    fputs("\n=== AX Tree Dump (pid \(config.pid)) ===\n", stderr)
    var focusedWindow: AnyObject?
    if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
        dumpAXTree(focusedWindow as! AXUIElement)
    } else {
        fputs("  (no focused window found)\n", stderr)
    }
    fputs("=== End AX Tree Dump ===\n\n", stderr)

    // Test if we can read text at all
    if let text = getFocusedWindowText(app: app) {
        fputs("Initial text probe succeeded (\(text.count) chars)\n", stderr)
    } else {
        fputs("Warning: initial text probe returned nil — AX may not expose text for this terminal\n", stderr)
        fputs("  Latency results may be unreliable (all timeouts)\n", stderr)
    }
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
