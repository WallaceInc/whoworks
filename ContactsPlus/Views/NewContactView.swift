import Contacts
import ContactsUI
import SwiftUI

/// The system "New Contact" form — the same one Contacts and Phone present,
/// including its own Cancel and Done buttons.
///
/// Unlike the card, this one genuinely must live in a `UINavigationController`;
/// it puts its buttons in the navigation bar and has nowhere to draw them
/// otherwise.
struct NewContactView: UIViewControllerRepresentable {
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(forNewContact: nil)
        controller.contactStore = CNContactStore()
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        /// Called for both outcomes — a contact when saved, nil when cancelled.
        /// Either way the sheet is ours to dismiss.
        func contactViewController(
            _ viewController: CNContactViewController,
            didCompleteWith contact: CNContact?
        ) {
            onFinish()
        }
    }
}
