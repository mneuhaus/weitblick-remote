import AppKit

/// The small status mark in a session's tab: spinner while connecting, a dot when connected,
/// circling arrows while reconnecting, a gray slashed dot when disconnected.
@MainActor
final class SessionStatusIndicator: NSView {
    private let image = NSImageView()
    private let spinner = NSProgressIndicator()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        for view in [image, spinner] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: centerXAnchor), view.centerYAnchor.constraint(equalTo: centerYAnchor),
                view.widthAnchor.constraint(equalToConstant: 12), view.heightAnchor.constraint(equalToConstant: 12),
            ])
        }
        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isDisplayedWhenStopped = false
        image.imageScaling = .scaleProportionallyDown
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 14), heightAnchor.constraint(equalToConstant: 14)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ status: SessionStatus) {
        toolTip = status.label
        switch status {
        case .connecting:
            image.isHidden = true
            spinner.startAnimation(nil)
        case .connected:
            spinner.stopAnimation(nil)
            setSymbol("circle.fill", color: .systemGreen, pointSize: 7)
        case .reconnecting:
            spinner.stopAnimation(nil)
            setSymbol("arrow.triangle.2.circlepath", color: .systemOrange, pointSize: 10)
        case .disconnected:
            spinner.stopAnimation(nil)
            setSymbol("circle.slash", color: .secondaryLabelColor, pointSize: 10)
        }
    }

    private func setSymbol(_ name: String, color: NSColor, pointSize: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        image.image = NSImage(systemSymbolName: name, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(configuration)
        image.isHidden = false
    }
}
