import AppKit
import EmberCore
import EmberKit
import SwiftUI

// Usage: EmberSnapshot <output-dir>
// Renders the panel (on schedule, holding) and the schedule window to PNGs. Nothing touches the real display.

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
_ = NSApplication.shared

@MainActor
func render(_ view: some View, width: CGFloat, to name: String) {
    let host = NSHostingView(rootView: view)
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = CGRect(x: 0, y: 0, width: width, height: 10)
    host.frame.size = host.fittingSize
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return print("no bitmap for \(name)") }
    host.cacheDisplay(in: host.bounds, to: rep)
    let url = outputDirectory.appendingPathComponent(name)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
    print("\(url.path) \(Int(host.bounds.width))x\(Int(host.bounds.height))")
}

MainActor.assumeIsolated {
    let suite = "com.cconway.ember.snapshot"
    UserDefaults().removePersistentDomain(forName: suite)
    let controller = Controller(tint: NoTint(), defaults: UserDefaults(suiteName: suite)!)
    controller.location = Coordinate(latitude: 37.7749, longitude: -122.4194)  // San Francisco
    controller.schedule.evening.start = .sunset(offsetMinutes: -60)

    render(MenuView(controller: controller), width: 360, to: "panel-schedule.png")
    controller.hold(Controller.presets[3].look)
    render(MenuView(controller: controller), width: 360, to: "panel-hold.png")
    controller.resume()
    controller.turnOff(.hour)
    render(MenuView(controller: controller), width: 360, to: "panel-off.png")
    controller.turnOn()
    render(ScheduleContent(controller: controller), width: 620, to: "schedule-window.png")
    render(AboutView(), width: 380, to: "about.png")
}
