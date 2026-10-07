import ConnectionStore
import Foundation
import Observation

/// State of the connection list: search, order and selection.
@MainActor @Observable
final class OverviewModel {
    let library: ConnectionLibrary
    let activity: SessionActivity
    var searchText = ""
    var selection: Set<UUID> = []
    var sortOrder: ConnectionSortOrder {
        didSet { UserDefaults.standard.set(sortOrder == .recent ? "recent" : "name", forKey: AppSettings.overviewSortKey) }
    }

    init(library: ConnectionLibrary, activity: SessionActivity) {
        self.library = library
        self.activity = activity
        sortOrder = UserDefaults.standard.string(forKey: AppSettings.overviewSortKey) == "recent" ? .recent : .name
    }

    var visibleConnections: [Connection] {
        ConnectionStore.filter(library.connections, matching: searchText, sortedBy: sortOrder)
    }

    /// Selected connections in list order (selection of hidden rows is ignored).
    var selectedConnections: [Connection] {
        visibleConnections.filter { selection.contains($0.id) }
    }
}
