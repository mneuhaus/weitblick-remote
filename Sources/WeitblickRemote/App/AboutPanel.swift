import AppKit

/// The standard About panel, with the open-source notices shipped in the bundle
/// (THIRD_PARTY_NOTICES.md, then the Apache-2.0 LICENSE) as its scrollable credits.
@MainActor
enum AboutPanel {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private static var credits: NSAttributedString {
        let texts = ["THIRD_PARTY_NOTICES.md", "LICENSE"].compactMap { name in
            Bundle.main.url(forResource: name, withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        return NSAttributedString(string: texts.joined(separator: "\n\n"), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ])
    }
}
