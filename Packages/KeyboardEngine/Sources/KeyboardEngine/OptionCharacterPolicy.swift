/// Decides whether ⌥ + key types a character or becomes Alt + key, per `OptionStrategy`.
enum OptionCharacterPolicy {
    /// What the "Smart" strategy accepts on letter keys: printable ASCII plus typographic characters a
    /// typist actually wants. Everything else on a letter key (ƒ ∂ å ø ≈ …) becomes an Alt accelerator.
    static let usefulOnLetterKeys: Set<Unicode.Scalar> = {
        var set = Set((0x21...0x7E).compactMap(Unicode.Scalar.init))
        for character in "€£¥¢°§¶©®™„“”‚‘’«»‹›–—…•·±×÷≠≤≥¬¡¿µ‰ß".unicodeScalars { set.insert(character) }
        return set
    }()

    /// Smart: `text` is what the layout types for ⌥ (+⇧) + key; `baseCharacter` what the key types alone.
    static func smartAccepts(_ text: String, baseCharacter: Character?) -> Bool {
        guard isPrintable(text) else { return false }
        guard baseCharacter?.isLetter == true else { return true }
        return text.unicodeScalars.allSatisfy(usefulOnLetterKeys.contains)
    }
}
