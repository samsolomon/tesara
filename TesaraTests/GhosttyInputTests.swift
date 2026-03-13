import XCTest
@testable import Tesara

final class GhosttyInputTests: XCTestCase {

    // MARK: - ScrollMods Bit Packing

    func testScrollModsNoPrecisionNoMomentum() {
        let mods = GhosttyInput.ScrollMods(precision: false, momentum: .none)
        XCTAssertEqual(mods.rawValue, 0)
    }

    func testScrollModsPrecisionOnly() {
        let mods = GhosttyInput.ScrollMods(precision: true, momentum: .none)
        XCTAssertEqual(mods.rawValue, 0b0000_0001)
    }

    func testScrollModsMomentumOnly() {
        let mods = GhosttyInput.ScrollMods(precision: false, momentum: .began)
        // Momentum .began = 1, shifted left by 1 → 0b0000_0010
        XCTAssertEqual(mods.rawValue, 0b0000_0010)
    }

    func testScrollModsPrecisionAndMomentum() {
        let mods = GhosttyInput.ScrollMods(precision: true, momentum: .changed)
        // Precision = bit 0, momentum .changed = 3 shifted left by 1 = 0b0000_0110
        XCTAssertEqual(mods.rawValue, 0b0000_0111)
    }

    func testScrollModsCScrollModsMatchesRawValue() {
        let mods = GhosttyInput.ScrollMods(precision: true, momentum: .ended)
        XCTAssertEqual(mods.cScrollMods, mods.rawValue)
    }

    // MARK: - Momentum from NSEvent.Phase

    func testMomentumNoneForEmptyPhase() {
        let m = GhosttyInput.Momentum(NSEvent.Phase(rawValue: 0))
        XCTAssertEqual(m, .none)
    }

    func testMomentumBegan() {
        let m = GhosttyInput.Momentum(.began)
        XCTAssertEqual(m, .began)
    }

    func testMomentumStationary() {
        let m = GhosttyInput.Momentum(.stationary)
        XCTAssertEqual(m, .stationary)
    }

    func testMomentumChanged() {
        let m = GhosttyInput.Momentum(.changed)
        XCTAssertEqual(m, .changed)
    }

    func testMomentumEnded() {
        let m = GhosttyInput.Momentum(.ended)
        XCTAssertEqual(m, .ended)
    }

    func testMomentumCancelled() {
        let m = GhosttyInput.Momentum(.cancelled)
        XCTAssertEqual(m, .cancelled)
    }

    func testMomentumMayBegin() {
        let m = GhosttyInput.Momentum(.mayBegin)
        XCTAssertEqual(m, .mayBegin)
    }

    // MARK: - Mouse Button Mapping

    func testMouseButtonMappingKnown() {
        XCTAssertEqual(GhosttyInput.mouseButton(from: 0), GHOSTTY_MOUSE_LEFT)
        XCTAssertEqual(GhosttyInput.mouseButton(from: 1), GHOSTTY_MOUSE_RIGHT)
        XCTAssertEqual(GhosttyInput.mouseButton(from: 2), GHOSTTY_MOUSE_MIDDLE)
        XCTAssertEqual(GhosttyInput.mouseButton(from: 3), GHOSTTY_MOUSE_FOUR)
        XCTAssertEqual(GhosttyInput.mouseButton(from: 10), GHOSTTY_MOUSE_ELEVEN)
    }

    func testMouseButtonMappingUnknown() {
        XCTAssertEqual(GhosttyInput.mouseButton(from: 11), GHOSTTY_MOUSE_UNKNOWN)
        XCTAssertEqual(GhosttyInput.mouseButton(from: -1), GHOSTTY_MOUSE_UNKNOWN)
        XCTAssertEqual(GhosttyInput.mouseButton(from: 999), GHOSTTY_MOUSE_UNKNOWN)
    }

    // MARK: - Modifier Mapping Round-Trip

    func testGhosttyModsShift() {
        let mods = GhosttyInput.ghosttyMods(.shift)
        XCTAssertNotEqual(mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue, 0)
    }

    func testGhosttyModsControl() {
        let mods = GhosttyInput.ghosttyMods(.control)
        XCTAssertNotEqual(mods.rawValue & GHOSTTY_MODS_CTRL.rawValue, 0)
    }

    func testGhosttyModsOption() {
        let mods = GhosttyInput.ghosttyMods(.option)
        XCTAssertNotEqual(mods.rawValue & GHOSTTY_MODS_ALT.rawValue, 0)
    }

    func testGhosttyModsCommand() {
        let mods = GhosttyInput.ghosttyMods(.command)
        XCTAssertNotEqual(mods.rawValue & GHOSTTY_MODS_SUPER.rawValue, 0)
    }

    func testGhosttyModsCapsLock() {
        let mods = GhosttyInput.ghosttyMods(.capsLock)
        XCTAssertNotEqual(mods.rawValue & GHOSTTY_MODS_CAPS.rawValue, 0)
    }

    func testGhosttyModsNone() {
        let mods = GhosttyInput.ghosttyMods(NSEvent.ModifierFlags(rawValue: 0))
        XCTAssertEqual(mods.rawValue, GHOSTTY_MODS_NONE.rawValue)
    }

    func testEventModifierFlagsRoundTrip() {
        // ghostty mods → NSEvent flags → ghostty mods should preserve standard modifiers
        let original: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let ghostty = GhosttyInput.ghosttyMods(original)
        let restored = GhosttyInput.eventModifierFlags(mods: ghostty)
        XCTAssertTrue(restored.contains(.shift))
        XCTAssertTrue(restored.contains(.control))
        XCTAssertTrue(restored.contains(.option))
        XCTAssertTrue(restored.contains(.command))
    }

    func testEventModifierFlagsEmptyRoundTrip() {
        let ghostty = GhosttyInput.ghosttyMods(NSEvent.ModifierFlags(rawValue: 0))
        let restored = GhosttyInput.eventModifierFlags(mods: ghostty)
        XCTAssertTrue(restored.isEmpty)
    }

    // MARK: - KeyboardLayout

    func testKeyboardLayoutIdReturnsString() {
        // Should return a non-nil string on macOS with a keyboard
        let layoutID = KeyboardLayout.id
        XCTAssertNotNil(layoutID)
        // Typical format: "com.apple.keylayout.US" or similar
        if let id = layoutID {
            XCTAssertFalse(id.isEmpty)
        }
    }

    // MARK: - Array.withCStrings

    func testWithCStringsEmpty() {
        let strings: [String] = []
        let result = strings.withCStrings { ptrs in
            ptrs.count
        }
        XCTAssertEqual(result, 0)
    }

    func testWithCStringsMultiple() {
        let strings = ["hello", "world", "test"]
        let result = strings.withCStrings { ptrs in
            XCTAssertEqual(ptrs.count, 3)
            // Verify strings are accessible
            for (i, ptr) in ptrs.enumerated() {
                XCTAssertNotNil(ptr)
                if let ptr {
                    XCTAssertEqual(String(cString: ptr), strings[i])
                }
            }
            return ptrs.count
        }
        XCTAssertEqual(result, 3)
    }

    func testWithCStringsSingle() {
        let strings = ["only"]
        strings.withCStrings { ptrs in
            XCTAssertEqual(ptrs.count, 1)
            if let ptr = ptrs[0] {
                XCTAssertEqual(String(cString: ptr), "only")
            }
        }
    }

    // MARK: - Optional<String>.withCString

    func testOptionalWithCStringNil() {
        let opt: String? = nil
        opt.withCString { ptr in
            XCTAssertNil(ptr)
        }
    }

    func testOptionalWithCStringSome() {
        let opt: String? = "hello"
        opt.withCString { ptr in
            XCTAssertNotNil(ptr)
            if let ptr {
                XCTAssertEqual(String(cString: ptr), "hello")
            }
        }
    }

    // MARK: - NSEvent.ghosttyCharacters

    func testGhosttyCharactersNormalText() {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: 0
        ) else {
            XCTFail("Failed to create NSEvent")
            return
        }
        XCTAssertEqual(event.ghosttyCharacters, "a")
    }

    func testGhosttyCharactersPUAFiltered() {
        // PUA function key range 0xF700-0xF8FF should return nil
        let puaChar = String(UnicodeScalar(0xF700)!)
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: puaChar, charactersIgnoringModifiers: puaChar,
            isARepeat: false, keyCode: 0
        ) else {
            XCTFail("Failed to create NSEvent")
            return
        }
        XCTAssertNil(event.ghosttyCharacters)
    }
}
