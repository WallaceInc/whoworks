import Contacts
import ContactsUI
import SwiftUI

/// The system contact card — the same one Phone and Contacts present. Using it
/// rather than a hand-rolled sheet means every action (each phone number,
/// message, FaceTime, mail, edit, delete, share) behaves exactly as expected.
struct ContactCardView: UIViewControllerRepresentable {
    let contact: CNContact
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(for: contact)
        controller.contactStore = CNContactStore()
        controller.allowsEditing = true
        controller.allowsActions = true
        controller.delegate = context.coordinator

        // `CNContactViewController` is meant to be *pushed*. As the root of a
        // presented navigation controller it drops "Delete Contact" from the
        // edit screen, so it gets pushed onto a placeholder instead.
        //
        // The placeholder is never seen — the card sits on top of it from the
        // start. Its only job is to close the sheet if the user taps back,
        // because CNContactViewController replaces any button we put there.
        let placeholder = DismissOnAppearController(onAppear: context.coordinator.onDone)
        let navigation = UINavigationController(rootViewController: placeholder)
        navigation.setViewControllers([placeholder, controller], animated: false)
        return navigation
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    /// Closes the sheet the moment it becomes visible, which only happens if
    /// the card above it is popped.
    final class DismissOnAppearController: UIViewController {
        private let onAppear: () -> Void

        init(onAppear: @escaping () -> Void) {
            self.onAppear = onAppear
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onAppear()
        }
    }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func contactViewController(
            _ viewController: CNContactViewController,
            didCompleteWith contact: CNContact?
        ) {
            // A nil contact means it was deleted — there's nothing left to show.
            if contact == nil { onDone() }
        }
    }

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
