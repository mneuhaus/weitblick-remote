import Foundation
import KeyboardEngine
import KeyboardEngineCarbon
import SprungKit

/// Plays a German ISO Mac keyboard into the KeyboardEngine, the way AppKit would deliver the keys,
/// and sends the engine's output to the session. Text is typed as the key presses a person would
/// use on that layout (⇧, ⌥ and dead keys), found by asking the layout itself.
@MainActor
final class KeyboardDriver {
    enum Modifier: CaseIterable {
        case shift, option, command

        var keyCode: UInt16 {
            switch self {
            case .shift: 0x38
            case .option: 0x3A
            case .command: 0x37
            }
        }

        var flag: ModifierFlags {
            switch self {
            case .shift: .leftShift
            case .option: .leftOption
            case .command: .leftCommand
            }
        }
    }

    /// One key press with the modifiers it needs.
    struct Stroke: Hashable {
        var keyCode: UInt16
        var modifiers: [Modifier] = []
    }

    static let returnKey: UInt16 = 0x24
    static let backspace: UInt16 = 0x33
    static let leftArrow: UInt16 = 0x7B
    static let rightArrow: UInt16 = 0x7C

    private var engine: KeyboardEngine
    private unowned let remote: RemoteKeyboard
    private let layout: UCKeyTranslateLayoutProvider
    private let strokes: [Character: [Stroke]]
    private var flags: ModifierFlags = []
    private var clock: Double = 1000
    /// Pause per key event: a fast human typist. At 4 ms (250 events/s) the WinUI Notepad lost or
    /// misplaced Shift around letters and dead keys (it reads modifier state asynchronously).
    private let pace: Duration = .milliseconds(25)

    init(remote: RemoteKeyboard) throws {
        guard let german = UCKeyTranslateLayoutProvider(inputSourceID: "com.apple.keylayout.German", keyboardTypeCode: 41) else {
            throw E2EFailure("German keyboard layout not installed")
        }
        layout = german
        self.remote = remote
        engine = KeyboardEngine(config: KeyboardConfig(), layout: german)
        strokes = Self.strokeTable(german)
    }

    /// The session got focus (as when the window becomes key).
    func focusGained() {
        remote.send(engine.focusGained(modifiers: []))
    }

    /// Types `text` key by key; fails for characters the German layout cannot type.
    func type(_ text: String) async throws {
        for character in text {
            if character == "\n" {
                try await press(Stroke(keyCode: Self.returnKey))
                continue
            }
            guard let sequence = strokes[character] else { throw E2EFailure("cannot type \(character) on German") }
            for stroke in sequence { try await press(stroke) }
        }
    }

    /// ⌘C etc.: modifiers down in order, the key, modifiers up in reverse.
    func press(_ stroke: Stroke) async throws {
        for modifier in stroke.modifiers { try await change(modifier, down: true) }
        try await send(.down, stroke.keyCode)
        try await send(.up, stroke.keyCode)
        for modifier in stroke.modifiers.reversed() { try await change(modifier, down: false) }
    }

    /// A shortcut by the character on its key, e.g. `shortcut([.command], "a")`.
    func shortcut(_ modifiers: [Modifier], _ character: Character) async throws {
        guard let base = strokes[character]?.first, strokes[character]?.count == 1, base.modifiers.isEmpty else {
            throw E2EFailure("no unmodified key for \(character)")
        }
        try await press(Stroke(keyCode: base.keyCode, modifiers: modifiers))
    }

    /// A Windows chord the Mac keyboard cannot express in Mac-shortcut mode (Win+R).
    func tap(_ chord: String) async throws {
        remote.send(engine.tap(try WindowsChord(chord)))
        try await Task.sleep(for: pace)
    }

    private func change(_ modifier: Modifier, down: Bool) async throws {
        if down { flags.insert(modifier.flag) } else { flags.remove(modifier.flag) }
        try await send(.flagsChanged, modifier.keyCode)
    }

    private func send(_ kind: KeyEvent.Kind, _ keyCode: UInt16) async throws {
        clock += 0.03
        let event = KeyEvent(kind: kind, keyCode: keyCode, modifiers: flags, timestamp: clock, keyboardType: .iso)
        let output = engine.handle(event)
        guard !output.passToApp else { throw E2EFailure("engine kept key \(keyCode) for the app") }
        remote.send(output.actions)
        try await Task.sleep(for: pace)
    }

    /// Character -> key presses, from the layout: plain, ⇧, ⌥ and ⇧⌥ keys first, then dead keys
    /// followed by a second key (^ e = ê, ⌥N n = ñ, ´ space = ´).
    private static func strokeTable(_ layout: UCKeyTranslateLayoutProvider) -> [Character: [Stroke]] {
        let keys: [UInt16] = Array(0x00...0x32).filter { $0 != 0x24 && $0 != 0x30 && $0 != 0x33 }
        let layers: [[Modifier]] = [[], [.shift], [.option], [.shift, .option]]
        func mods(_ layer: [Modifier]) -> LayoutModifiers {
            var result: LayoutModifiers = []
            if layer.contains(.shift) { result.insert(.shift) }
            if layer.contains(.option) { result.insert(.option) }
            return result
        }
        var table: [Character: [Stroke]] = [:]
        var deadKeys: [(Stroke, UInt32)] = []
        for layer in layers {
            for key in keys {
                var state: UInt32 = 0
                let text = layout.translate(keyCode: key, modifiers: mods(layer), deadKeyState: &state)
                if text.isEmpty, state != 0 {
                    deadKeys.append((Stroke(keyCode: key, modifiers: layer), state))
                } else if text.count == 1, let character = text.first, table[character] == nil {
                    table[character] = [Stroke(keyCode: key, modifiers: layer)]
                }
            }
        }
        // A second dead key also "types" the first accent but leaves itself pending; people type the
        // bare accent with space.
        let deadStrokes = Set(deadKeys.map(\.0))
        for (dead, state) in deadKeys {
            for layer in layers {
                for key in keys where !deadStrokes.contains(Stroke(keyCode: key, modifiers: layer)) {
                    var composed = state
                    let text = layout.translate(keyCode: key, modifiers: mods(layer), deadKeyState: &composed)
                    if text.count == 1, let character = text.first, table[character] == nil {
                        table[character] = [dead, Stroke(keyCode: key, modifiers: layer)]
                    }
                }
            }
        }
        return table
    }
}
