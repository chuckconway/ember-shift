import AppKit
import EmberCore

/// The menu that opens when you right-click the menu bar icon: turn Ember off for a while, or back on.
///
/// MenuBarExtra has no right-click hook, so this watches the app's own right-clicks and
/// claims the ones that land on its status item.
@MainActor
public final class StatusMenu: NSObject {
    private let controller: Controller
    private var monitor: Any?

    public init(controller: Controller) {
        self.controller = controller
    }

    public func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            let claimed = MainActor.assumeIsolated { self?.popUp(for: event) ?? false }
            return claimed ? nil : event
        }
    }

    private func popUp(for event: NSEvent) -> Bool {
        guard let window = event.window, window.className.contains("NSStatusBarWindow"),
              let view = window.contentView else { return false }
        NSMenu.popUpContextMenu(menu(), with: event, for: view)
        return true
    }

    func menu() -> NSMenu {
        let menu = NSMenu()
        if controller.off {
            let status = NSMenuItem(title: Self.offStatus(controller), action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(item("Turn back on") { $0.turnOn() })
            menu.addItem(.separator())
        }
        menu.addItem(.sectionHeader(title: controller.off ? "Stay off" : "Turn off"))
        for duration in Controller.OffDuration.allCases {
            menu.addItem(item(Self.title(duration, controller)) { $0.turnOff(duration) })
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ember Shift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    static func title(_ duration: Controller.OffDuration, _ controller: Controller) -> String {
        switch duration {
        case .fifteenMinutes: "For 15 minutes"
        case .hour: "For an hour"
        case .morning: "Until morning (\(controller.nextMorning.shortTime))"
        case .untilTurnedOn: "Until I turn it back on"
        }
    }

    static func offStatus(_ controller: Controller) -> String {
        controller.offEnd.map { "Off until \($0.shortTime)" } ?? "Off until you turn it back on"
    }

    private func item(_ title: String, _ action: @escaping (Controller) -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title) { [controller] in action(controller) }
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
