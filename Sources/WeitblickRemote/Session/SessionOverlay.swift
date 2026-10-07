import SwiftUI

/// What lies over the remote desktop while there is no usable connection.
enum SessionOverlayPhase: Equatable {
    case hidden
    case connecting(host: String)
    case reconnecting(attempt: Int)
    case failed(message: String)
    /// Not signed in (sign-in cancelled): offers the sign-in sheet again.
    case signedOut(message: String)
}

/// Buttons of the overlay, wired by the session window.
struct SessionOverlayActions {
    var retry: () -> Void
    var signIn: () -> Void
    var closeTab: () -> Void
}

struct SessionOverlay: View {
    let phase: SessionOverlayPhase
    let actions: SessionOverlayActions

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.55))
            card
                .padding(28)
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 20)
                .padding(40)
        }
    }

    @ViewBuilder private var card: some View {
        switch phase {
        case .hidden:
            EmptyView()
        case .connecting(let host):
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Connecting to \(host)…").font(.headline)
                Button("Cancel", action: actions.closeTab).keyboardShortcut(.cancelAction)
            }
        case .reconnecting(let attempt):
            VStack(spacing: 10) {
                ProgressView().controlSize(.large)
                Text("Connection lost").font(.headline)
                Text("Reconnecting, attempt \(attempt)…").foregroundStyle(.secondary)
                Button("Close Tab", action: actions.closeTab).padding(.top, 4)
            }
        case .failed(let message):
            notice(symbol: "bolt.horizontal.circle", title: "Disconnected", text: message) {
                Button("Close Tab", action: actions.closeTab).keyboardShortcut(.cancelAction)
                Button("Reconnect", action: actions.retry).keyboardShortcut(.defaultAction)
            }
        case .signedOut(let message):
            notice(symbol: "person.crop.circle.badge.questionmark", title: "Not signed in", text: message) {
                Button("Close Tab", action: actions.closeTab).keyboardShortcut(.cancelAction)
                Button("Sign In…", action: actions.signIn).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func notice(symbol: String, title: LocalizedStringKey, text: String,
                         @ViewBuilder buttons: () -> some View) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary).textSelection(.enabled)
            HStack(spacing: 10) { buttons() }.padding(.top, 6)
        }
    }
}
