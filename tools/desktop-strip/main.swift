import AppKit

// Companion access to real applications; never closes or captures their windows.
final class DesktopStrip: NSObject, NSApplicationDelegate {
    struct Target {
        let title: String
        let bundle: String
    }
    let targets = [Target(title: "Claude", bundle: "com.anthropic.claudefordesktop"),
                   Target(title: "Codex", bundle: "com.openai.codex"),
                   Target(title: "Muse", bundle: "com.t3tools.t3code")]
    var panel: NSPanel!
    var buttons: [NSButton] = []
    var observer: NSObjectProtocol?
    var status: NSStatusItem!
    let feedback = NSTextField(labelWithString: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NSPanel(contentRect: NSRect(x: 180, y: 180, width: 310, height: 46),
                        styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        panel.title = "Work Strip"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("TerminalKitDesktopStrip")
        panel.minSize = panel.frame.size
        panel.maxSize = panel.frame.size
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        for (index, target) in targets.enumerated() {
            let button = NSButton(title: target.title, target: self, action: #selector(selectTarget(_:)))
            button.tag = index
            button.bezelStyle = .recessed
            button.setButtonType(.pushOnPushOff)
            button.toolTip = "Bring \(target.title) forward; existing conversations stay in their app"
            button.setAccessibilityLabel("Show \(target.title)")
            buttons.append(button)
            row.addArrangedSubview(button)
        }
        let hide = NSButton(title: "×", target: self, action: #selector(hideStrip))
        hide.bezelStyle = .recessed
        hide.toolTip = "Hide strip; restore from the menu bar"
        hide.setAccessibilityLabel("Hide Work Strip")
        row.addArrangedSubview(hide)
        let content = panel.contentView!
        content.addSubview(row)
        feedback.font = .systemFont(ofSize: 10)
        feedback.textColor = .secondaryLabelColor
        feedback.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(feedback)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: content.topAnchor, constant: 1),
            row.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            feedback.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            feedback.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -2)
        ])
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "▱"
        status.button?.toolTip = "Terminal Kit Work Strip"
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Work Strip", action: #selector(showStrip), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Work Strip", action: #selector(quitStrip), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notice in
            let app = notice.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateSelection(app?.bundleIdentifier)
        }
        updateSelection(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        panel.orderFrontRegardless()
    }

    func updateSelection(_ bundle: String?) {
        for (index, button) in buttons.enumerated() {
            button.state = targets[index].bundle == bundle ? .on : .off
        }
    }

    @objc func selectTarget(_ sender: NSButton) {
        let target = targets[sender.tag]
        updateSelection(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundle).first {
            feedback.stringValue = running.activate(options: []) ? "" : "Could not activate \(target.title)"
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundle) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
                DispatchQueue.main.async { self?.feedback.stringValue = error == nil ? "" : "Could not open \(target.title)" }
            }
        } else {
            feedback.stringValue = "\(target.title) is not installed"
        }
    }
    @objc func hideStrip() { panel.orderOut(nil) }
    @objc func showStrip() { panel.orderFrontRegardless() }
    @objc func quitStrip() { NSApp.terminate(nil) }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = DesktopStrip()
app.delegate = delegate
app.run()
