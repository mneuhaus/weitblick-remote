import Foundation
import ConnectionStore

@main
struct ConnectionStoreDryRun {
    static func main() async {
        do { try await run() }
        catch {
            // Do not interpolate parser errors: source values should stay in the local report only.
            print("Dry run failed (\(type(of: error))). No Jump settings or credentials were modified.")
            exit(1)
        }
    }

    private static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 2 else {
            print("Usage: connection-store-dry-run <preview-store.json> <report.txt>")
            return
        }
        let storeURL = URL(fileURLWithPath: args[0])
        let reportURL = URL(fileURLWithPath: args[1])
        // The CLI is an evidence runner, not an import command. Keep all possible output under build/.
        let buildPath = storeURL.deletingLastPathComponent().path
        guard buildPath.hasSuffix("/weitblick-remote/build"), reportURL.path.hasPrefix(buildPath + "/") else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let store = ConnectionStore(fileURL: storeURL)
        let existing = try await store.load()
        let importer = JumpImporter()
        let plan = try importer.plan(existing: existing)
        let profiles = try JumpInputProfileImporter().read()
        let rdpCount = plan.entries.filter { $0.connection.protocol == .rdp }.count
        let vncCount = plan.entries.count - rdpCount
        let simulated = existing.filter { old in !plan.entries.contains { $0.connection.id == old.id } }
            + plan.entries.map(\.connection)
        let secondPlan = try importer.plan(existing: simulated)
        let mappingCount = profiles.profiles.reduce(0) { $0 + $1.mappings.count }
        let builtInCount = profiles.profiles.flatMap(\.mappings).filter { $0.classification == .builtIn }.count
        let summary = """
        LOCAL DRY RUN. No connections attempted, no Jump files or Keychain items modified.
        Store path (not saved): \(storeURL.path)
        Connections: \(plan.entries.count) (RDP \(rdpCount), VNC \(vncCount))
        Plan: create \(plan.createCount), update \(plan.updateCount), unchanged \(plan.unchangedCount)
        Simulated reimport: create \(secondPlan.createCount), update \(secondPlan.updateCount), unchanged \(secondPlan.unchangedCount)
        Input profiles: \(profiles.profiles.count), mappings: \(mappingCount), built-in: \(builtInCount)
        Connection warnings: \(plan.report.warningCount)
        Profile warnings: \(profiles.warnings.count + profiles.profiles.reduce(0) { $0 + $1.warnings.count })

        """
        let text = summary + plan.report.humanReadable + "\n" + profiles.humanReadable
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: reportURL, options: .atomic)
        print(summary)
        print("Evidence saved: \(reportURL.path)")
    }
}
