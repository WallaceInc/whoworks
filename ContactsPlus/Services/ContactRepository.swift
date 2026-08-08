import Contacts
import Foundation
import Observation

/// Loads the system address book once and hands the UI plain value types.
@MainActor
@Observable
final class ContactRepository {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case denied
        case failed(String)
    }

    private(set) var people: [Person] = []
    private(set) var state: LoadState = .idle

    /// True when the user granted only a hand-picked subset (iOS 18+), which
    /// is worth surfacing — otherwise a half-empty list looks like a bug.
    private(set) var isLimitedAccess = false

    func load() async {
        guard state != .loading else { return }
        state = .loading

        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            let store = CNContactStore()
            let granted = (try? await store.requestAccess(for: .contacts)) ?? false
            guard granted else {
                state = .denied
                return
            }
        case .denied, .restricted:
            state = .denied
            return
        case .limited:
            isLimitedAccess = true
        case .authorized:
            break
        @unknown default:
            break
        }

        do {
            let fetched = try await Task.detached(priority: .userInitiated) {
                #if DEBUG
                DebugSeed.seedIfRequested()
                #endif
                return try ContactRepository.fetchAll()
            }.value
            people = fetched
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Runs off the main actor. `CNContactStore` is created inside so nothing
    /// non-`Sendable` crosses the boundary.
    nonisolated private static func fetchAll() throws -> [Person] {
        let store = CNContactStore()
        let keys = [
            CNContactIdentifierKey,
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactJobTitleKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactThumbnailImageDataKey,
        ] as [CNKeyDescriptor]

        let sortOrder = CNContactsUserDefaults.shared().sortOrder
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        request.unifyResults = true

        var results: [Person] = []
        results.reserveCapacity(1024)
        try store.enumerateContacts(with: request) { contact, _ in
            results.append(Person(contact: contact, sortOrder: sortOrder))
        }

        // `.userDefault` already sorts, but sectioning depends on `sortKey`
        // agreeing with the visual order, so re-sort on the same key.
        results.sort { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
        return results
    }
}
