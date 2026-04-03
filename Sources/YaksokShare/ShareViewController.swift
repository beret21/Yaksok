import Cocoa
import UniformTypeIdentifiers

class ShareViewController: NSViewController {
    override func loadView() {
        self.view = NSView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachment = item.attachments?.first else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let textType = UTType.plainText.identifier

        if attachment.hasItemConformingToTypeIdentifier(textType) {
            attachment.loadItem(forTypeIdentifier: textType) { [weak self] data, _ in
                guard let text = data as? String, !text.isEmpty else {
                    DispatchQueue.main.async {
                        self?.extensionContext?.completeRequest(returningItems: nil)
                    }
                    return
                }

                let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "yaksok://extract?text=\(encoded)") {
                    NSWorkspace.shared.open(url)
                }

                DispatchQueue.main.async {
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        } else {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
