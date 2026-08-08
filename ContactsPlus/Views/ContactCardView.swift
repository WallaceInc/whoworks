import Contacts
import ContactsUI
import SwiftUI

/// The system contact card — the same one Phone and Contacts present. Using it
/// rather than a hand-rolled sheet means every action (each phone number,
/// message, FaceTime, mail, edit, share) behaves exactly as expected.
struct ContactCardView: UIViewControllerRepresentable {
    let contact: CNContact
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(for: contact)
        controller.contactStore = CNContactStore()
        controller.allowsEditing = true
        controller.allowsActions = true
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { _ in onDone() }
        )
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    /// `CNContactViewController` throws unless the contact was fetched with its
    /// own descriptor, which is far broader than what the list needs — so the
    /// full record is only pulled at the moment a row is tapped.
    static func fetch(id: String) -> CNContact? {
        let store = CNContactStore()
        let keys = [CNContactViewController.descriptorForRequiredKeys()]
        return try? store.unifiedContact(withIdentifier: id, keysToFetch: keys)
    }
}

/// Wrapper so a fetched contact can drive `.sheet(item:)`.
struct ContactCard: Identifiable {
    let id: String
    let contact: CNContact
}
