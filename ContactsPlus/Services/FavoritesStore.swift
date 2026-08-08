import Foundation
import Observation

/// Our own favourites list.
///
/// The Phone app's favourites are not exposed by any public API, so these can't
/// mirror them — this is a separate list that lives with this app.
@MainActor
@Observable
final class FavoritesStore {
    private static let key = "favorites.ids"

    private(set) var ids: Set<String>

    init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        UserDefaults.standard.set(Array(ids), forKey: Self.key)
    }
}
