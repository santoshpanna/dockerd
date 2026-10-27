import AppKit
import DockerdCore

final class OnboardingWindowController: NSWindowController {
    private let permissions: PermissionController
    private let headline = NSTextField(labelWithString: "")
    private let body = NSTextField(wrappingLabelWithString: "")

    init(permissions: PermissionController) {
        self.permissions = permissions
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "Dockerd needs Accessibility access"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present(for state: AccessibilityPermission) {
        switch state {
        case .revoked:
            headline.stringValue = "Accessibility access was turned off"
            body.stringValue = """
            Dockerd can still show running apps and pinned apps, but it can no longer list or switch individual windows.

            Turn Dockerd back on in System Settings › Privacy & Security › Accessibility. If it is already on, remove it with the minus button and add it again; macOS keys the permission to the app's signature, so a rebuilt copy needs to be re-added.
            """
        default:
            headline.stringValue = "Allow Dockerd to see your windows"
            body.stringValue = """
            Dockerd uses the macOS Accessibility API to list each app's windows, read their titles, and raise, minimize or restore the one you click.

            It never captures your screen, reads document contents, or sends anything over the network. Without access, Dockerd still shows running and pinned apps.
            """
        }
        window?.center()
        AppActivation.bringSelfForward()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        guard let content = window?.contentView else { return }
        let icon = NSImageView(image: NSImage(systemSymbolName: "hand.raised.circle", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 40, weight: .regular)
        icon.contentTintColor = .controlAccentColor
        headline.font = .systemFont(ofSize: 17, weight: .semibold)
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = 400

        let grant = NSButton(title: "Grant Access…", target: self, action: #selector(grant))
        grant.keyEquivalent = "\r"
        grant.bezelColor = .controlAccentColor
        let open = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        let later = NSButton(title: "Not Now", target: self, action: #selector(dismiss))
        let buttons = NSStackView(views: [later, NSView(), open, grant])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [icon, headline, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
        ])
    }

    @objc private func grant() {
        permissions.requestAccess()
        permissions.openSystemSettings()
    }

    @objc private func openSettings() {
        permissions.openSystemSettings()
    }

    @objc private func dismiss() {
        close()
    }
}
