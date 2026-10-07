@testable import KeyboardEngine
import Testing

/// Random typing, chording, focus changes and lost events. Whatever happens, once every physical key
/// is up the remote side must hold nothing, never get a break without a make, and agree on Caps Lock.
struct StuckKeyFuzzTests {
    struct Scenario: CustomTestStringConvertible, Sendable {
        let name: String
        let config: KeyboardConfig
        var testDescription: String { name }
    }

    static let scenarios: [Scenario] = {
        func config(_ mode: KeyboardConfig.Mode, _ strategy: KeyboardConfig.OptionStrategy, unicode: Bool = false) -> KeyboardConfig {
            KeyboardConfig(mode: mode, optionStrategy: strategy, unicodeTextInput: unicode)
        }
        return [
            Scenario(name: "mac smart", config: config(.macShortcuts, .smart)),
            Scenario(name: "mac jump", config: config(.macShortcuts, .jumpStyle)),
            Scenario(name: "mac alt", config: config(.macShortcuts, .alwaysAlt)),
            Scenario(name: "mac characters", config: config(.macShortcuts, .alwaysCharacters)),
            Scenario(name: "mac smart unicode", config: config(.macShortcuts, .smart, unicode: true)),
            Scenario(name: "direct", config: config(.windowsDirect, .smart)),
            Scenario(name: "direct unicode", config: config(.windowsDirect, .smart, unicode: true)),
        ]
    }()

    static let keys: [UInt16] = [
        K.a, K.c, K.v, K.l, K.n, K.u, K.q, K.f, K.e, K.ansiY, K.seven, K.equal, K.isoSection, K.grave,
        K.space, K.tab, K.returnKey, K.backspace, K.forwardDelete, K.escape, K.left, K.up,
        K.f4, K.f14, K.f15, K.keypad1, K.keypadEquals, K.keypadClear,
    ]

    @Test(arguments: scenarios)
    func randomSessionsLeaveNothingStuck(scenario: Scenario) {
        var random = SplitMix64(seed: 0x5EED)
        for run in 0..<1500 {
            var h = Harness(Layouts.german, config: scenario.config)
            var remote = RemoteSimulator()
            var heldKeys: [UInt16] = []
            var focused = true
            var log: [String] = []

            func flush(_ h: inout Harness) { remote.apply(h.take()) }

            for _ in 0..<80 {
                let roll = random.next(100)
                let releasedModifiers = Mod.allCases.filter { !h.flags.contains($0.flag) }
                let heldModifiers = Mod.allCases.filter { h.flags.contains($0.flag) }
                switch roll {
                case 0..<30 where !releasedModifiers.isEmpty:
                    let modifier = releasedModifiers[random.next(releasedModifiers.count)]
                    log.append("press \(modifier)")
                    if focused { h.press(modifier) } else { h.flags.insert(modifier.flag) }
                case 30..<55 where !heldModifiers.isEmpty:
                    let modifier = heldModifiers[random.next(heldModifiers.count)]
                    log.append("release \(modifier)")
                    if focused, random.next(20) != 0 { h.release(modifier) } else { h.flags.remove(modifier.flag) }
                case 55..<75:
                    let key = Self.keys[random.next(Self.keys.count)]
                    guard !heldKeys.contains(key) else { continue }
                    heldKeys.append(key)
                    log.append("down \(key)")
                    if focused { h.down(key) }
                case 75..<88 where !heldKeys.isEmpty:
                    let key = heldKeys.remove(at: random.next(heldKeys.count))
                    log.append("up \(key)")
                    if focused { h.up(key) }
                case 88..<93 where !heldKeys.isEmpty && focused:
                    let key = heldKeys[random.next(heldKeys.count)]
                    log.append("repeat \(key)")
                    h.down(key, isRepeat: true)
                case 93..<95 where focused:
                    log.append("caps")
                    h.toggleCapsLock()
                case 95..<97 where focused:
                    log.append("pointer")
                    h.pointer()
                case 97..<100:
                    log.append(focused ? "focus lost" : "focus gained")
                    if focused {
                        h.focusLost()
                        flush(&h)
                        #expect(remote.held.isEmpty, "run \(run): held after focus loss: \(remote.held)\n\(log.joined(separator: ", "))")
                    } else {
                        h.focusGained()
                    }
                    focused.toggle()
                    if !focused, random.next(2) == 0, h.flags.contains(.capsLock) == false {
                        h.flags.insert(.capsLock) // toggled while away
                    }
                default:
                    continue
                }
                h.wait(Double(random.next(4)) * 0.2)
                flush(&h)
            }

            // Let go of everything.
            if !focused { h.focusGained() }
            for key in heldKeys { h.up(key) }
            for modifier in Mod.allCases where h.flags.contains(modifier.flag) { h.release(modifier) }
            flush(&h)

            #expect(remote.violations.isEmpty, "run \(run): \(remote.violations)\n\(log.joined(separator: ", "))")
            #expect(remote.held.isEmpty, "run \(run): still held \(remote.held)\n\(log.joined(separator: ", "))")
            #expect(remote.capsLock == h.flags.contains(.capsLock), "run \(run): caps lock out of sync\n\(log.joined(separator: ", "))")
        }
    }
}

/// Small deterministic PRNG so failures reproduce.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next(_ upperBound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Int(z % UInt64(upperBound))
    }
}
