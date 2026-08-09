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

    /// Refetches without flipping back to `.loading`, so the list stays on
    /// screen. Used after the contact card is dismissed, since the user may
    /// have edited or deleted someone while it was open.
    func reload() async {
        guard state == .ready else { return }
        guard let refreshed = try? await Task.detached(priority: .userInitiated, operation: {
            try ContactRepository.fetchAll()
        }).value else { return }
        people = refreshed
    }

    /// Deletes a contact from the address book.
    ///
    /// Apple does not expose "Delete Contact" through `CNContactViewController`
    /// — it only exists in the Contacts app itself — so the app provides its
    /// own. Returns false if the contact had already gone.
    func delete(id: String) async -> Bool {
        let removed = await Task.detached(priority: .userInitiated) {
            ContactRepository.performDelete(id: id)
        }.value
        if removed { await reload() }
        return removed
    }

    nonisolated private static func performDelete(id: String) -> Bool {
        let store = CNContactStore()
        let keys = [CNContactIdentifierKey as CNKeyDescriptor]
        guard let contact = try? store.unifiedContact(withIdentifier: id, keysToFetch: keys),
              let mutable = contact.mutableCopy() as? CNMutableContact
        else { return false }

        let request = CNSaveRequest()
        request.delete(mutable)
        do {
            try store.execute(request)
            return true
        } catch {
            print("[contacts] delete failed: \(error)")
            return false
        }
    }

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

        let t0 = CFAbsoluteTimeGetCurrent()
        var results: [Person] = []
        results.reserveCapacity(1024)
        try store.enumerateContacts(with: request) { contact, _ in
            results.append(Person(contact: contact, sortOrder: sortOrder))
        }
        let enumerated = CFAbsoluteTimeGetCurrent()
        let withPhotos = results.count { $0.thumbnail != nil }
        #if DEBUG
        print(String(format: "[perf] enumerate %.0fms  %d contacts  %d with photos",
                     (enumerated - t0) * 1000, results.count, withPhotos))
        #endif

        // `.userDefault` already sorts, but sectioning depends on `sortKey`
        // agreeing with the visual order, so re-sort on the same key.
        results.sort { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
        #if DEBUG
        print(String(format: "[perf] sort %.0fms", (CFAbsoluteTimeGetCurrent() - enumerated) * 1000))
        #endif
        return results
    }
}
