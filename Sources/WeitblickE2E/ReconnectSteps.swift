import Foundation

/// Auto-reconnect: the VM's network adapter is unplugged (prlctl, the Mac's own networking is not
/// touched) until the session notices, then plugged back in; the session must come back into the
/// same Windows session with keyboard and clipboard working.
extension Scenario {
    func reconnectAfterNetworkDrop() async throws {
        let notepad = try vm.notepadProcessID()
        let attempts = probe.reconnectAttempts.count
        let reconnects = probe.reconnects
        let announcements = clipboard.acceptedAnnouncements
        let unplugged = Date()
        try vm.setNetwork(connected: false)
        do {
            try await probe.wait("connection loss", timeout: 120) { self.probe.reconnectAttempts.count > attempts }
            log(String(format: "network unplugged: loss noticed after %.1f s", Date().timeIntervalSince(unplugged)))
            try await Task.sleep(for: .seconds(5))
        } catch {
            try? vm.setNetwork(connected: true)
            throw error
        }
        try vm.setNetwork(connected: true)
        let plugged = Date()
        try await probe.wait("reconnect", timeout: 180) { self.probe.reconnects > reconnects }
        log(String(format: "network back: reconnected %.1f s later after %d attempts", Date().timeIntervalSince(plugged),
                   probe.reconnectAttempts.count - attempts))
        check("reconnect: same Windows session (Notepad still running)", try vm.notepadProcessID() == notepad, "Notepad changed")

        try await probe.wait("clipboard after reconnect", timeout: 30) { self.clipboard.acceptedAnnouncements > announcements }
        try await probe.waitForSettledFrame()
        keyboard.focusGained()
        try await clearNotepad()
        let text = "Nach dem Wiederverbinden: Grüße"
        try await keyboard.type(text)
        check("reconnect: keyboard and clipboard work again", try await copyAll(), equals: text)
    }
}
