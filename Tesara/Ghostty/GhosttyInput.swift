import AppKit
import Carbon

/// Input helpers for translating macOS events to ghostty's input types.
///
/// Ported from Ghostty's `Ghostty.Input.swift`, `NSEvent+Extension.swift`,
/// `KeyboardLayout.swift`, `Array+Extension.swift`, and `Optional+Extension.swift`.
enum GhosttyInput {

    // MARK: - Modifier Mapping

    /// NSEvent.ModifierFlags → ghostty_input_mods_e
    static func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue

        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }

        // Sided modifiers via IOKit raw device masks
        let rawFlags = flags.rawValue
        if rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }

        return ghostty_input_mods_e(mods)
    }

    /// ghostty_input_mods_e → NSEvent.ModifierFlags
    static func eventModifierFlags(mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags(rawValue: 0)
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        return flags
    }

    // MARK: - Mouse Button Mapping

    /// Maps NSEvent.buttonNumber to ghostty_input_mouse_button_e
    static func mouseButton(from buttonNumber: Int) -> ghostty_input_mouse_button_e {
        switch buttonNumber {
        case 0: return GHOSTTY_MOUSE_LEFT
        case 1: return GHOSTTY_MOUSE_RIGHT
        case 2: return GHOSTTY_MOUSE_MIDDLE
        case 3: return GHOSTTY_MOUSE_FOUR
        case 4: return GHOSTTY_MOUSE_FIVE
        case 5: return GHOSTTY_MOUSE_SIX
        case 6: return GHOSTTY_MOUSE_SEVEN
        case 7: return GHOSTTY_MOUSE_EIGHT
        case 8: return GHOSTTY_MOUSE_NINE
        case 9: return GHOSTTY_MOUSE_TEN
        case 10: return GHOSTTY_MOUSE_ELEVEN
        default: return GHOSTTY_MOUSE_UNKNOWN
        }
    }

    // MARK: - ScrollMods

    /// Packed bitmask matching ghostty's `ScrollMods` packed struct.
    /// Bit 0 = precision (trackpad), bits 1–3 = Momentum enum.
    struct ScrollMods {
        let rawValue: Int32

        init(precision: Bool = false, momentum: Momentum = .none) {
            var value: Int32 = 0
            if precision { value |= 0b0000_0001 }
            value |= Int32(momentum.rawValue) << 1
            self.rawValue = value
        }

        var cScrollMods: ghostty_input_scroll_mods_t {
            rawValue
        }
    }

    /// Momentum phase for scroll events
    enum Momentum: UInt8 {
        case none = 0
        case began = 1
        case stationary = 2
        case changed = 3
        case ended = 4
        case cancelled = 5
        case mayBegin = 6

        init(_ phase: NSEvent.Phase) {
            switch phase {
            case .began: self = .began
            case .stationary: self = .stationary
            case .changed: self = .changed
            case .ended: self = .ended
            case .cancelled: self = .cancelled
            case .mayBegin: self = .mayBegin
            default: self = .none
            }
        }
    }
}

// MARK: - KeyboardLayout

/// Queries the current keyboard input source ID via Carbon TIS API.
enum KeyboardLayout {
    static var id: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let sourceIdPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(sourceIdPointer).takeUnretainedValue() as String
    }
}

// MARK: - NSEvent Key Event Extension

extension NSEvent {
    /// Create a ghostty_input_key_s from this NSEvent.
    /// Does NOT set `text` or `composing` — caller must handle those.
    func ghosttyKeyEvent(
        _ action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags? = nil
    ) -> ghostty_input_key_s {
        var key_ev = ghostty_input_key_s()
        key_ev.action = action
        key_ev.keycode = UInt32(keyCode)
        key_ev.text = nil
        key_ev.composing = false

        key_ev.mods = GhosttyInput.ghosttyMods(modifierFlags)
        // Control and command never contribute to text translation
        key_ev.consumed_mods = GhosttyInput.ghosttyMods(
            (translationMods ?? modifierFlags)
                .subtracting([.control, .command])
        )

        key_ev.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp {
            if let chars = characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                key_ev.unshifted_codepoint = codepoint.value
            }
        }

        return key_ev
    }

    /// Returns text suitable for ghostty key events, filtering control chars and PUA function keys.
    var ghosttyCharacters: String? {
        guard let characters else { return nil }

        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            // Control chars < 0x20: re-apply mods without control to get the base character
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }

            // PUA function key range — don't send to ghostty
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }
}

// MARK: - Array withCStrings

extension Array where Element == String {
    /// Execute a closure with an array of C string pointers whose lifetimes are
    /// guaranteed for the closure's duration.
    func withCStrings<T>(_ body: ([UnsafePointer<Int8>?]) throws -> T) rethrows -> T {
        if isEmpty {
            return try body([])
        }

        func helper(
            index: Int,
            accumulated: [UnsafePointer<Int8>?],
            body: ([UnsafePointer<Int8>?]) throws -> T
        ) rethrows -> T {
            if index == count {
                return try body(accumulated)
            }
            return try self[index].withCString { cStr in
                var acc = accumulated
                acc.append(cStr)
                return try helper(index: index + 1, accumulated: acc, body: body)
            }
        }

        return try helper(index: 0, accumulated: [], body: body)
    }
}

// MARK: - Optional<String> withCString

extension Optional where Wrapped == String {
    /// Execute closure with C string pointer, passing nil for .none.
    func withCString<T>(_ body: (UnsafePointer<Int8>?) throws -> T) rethrows -> T {
        if let string = self {
            return try string.withCString(body)
        } else {
            return try body(nil)
        }
    }
}
