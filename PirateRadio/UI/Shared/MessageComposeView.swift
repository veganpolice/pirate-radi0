import MessageUI
import SwiftUI

/// Wraps MFMessageComposeViewController for SwiftUI using a trampoline pattern.
/// MFMessageComposeViewController must be presented via UIKit's present(_:animated:),
/// not embedded directly as a UIViewControllerRepresentable child.
struct MessageComposeView: UIViewControllerRepresentable {
    let messageBody: String
    let onFinished: () -> Void

    func makeUIViewController(context: Context) -> MessageComposeHostController {
        MessageComposeHostController(messageBody: messageBody, onFinished: onFinished)
    }

    func updateUIViewController(_ uiViewController: MessageComposeHostController, context: Context) {}
}

class MessageComposeHostController: UIViewController, MFMessageComposeViewControllerDelegate {
    private let messageBody: String
    private let onFinished: () -> Void
    private var hasPresented = false

    init(messageBody: String, onFinished: @escaping () -> Void) {
        self.messageBody = messageBody
        self.onFinished = onFinished
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasPresented, MFMessageComposeViewController.canSendText() else { return }
        hasPresented = true
        let composer = MFMessageComposeViewController()
        composer.body = messageBody
        composer.messageComposeDelegate = self
        present(composer, animated: true)
    }

    func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        controller.dismiss(animated: true) {
            self.onFinished()
        }
    }
}
