import AppKit
import EmberCore
import ServiceManagement

/// Owns what's on screen: the schedule's look, or a look you're holding.
///
/// A hold beats the schedule until the schedule's next change, then hands back.
/// Switching between looks fades over `fadeSeconds`; dragging a slider is instant.
/// Turning it off shows true color for a while, over whichever of those is in effect.
@MainActor
public final class Controller: ObservableObject {
    enum Mode: Codable, Equatable {
        case schedule
        case hold(Look, since: Date)
    }

    public static let presets: [(name: String, look: Look)] = [
        ("Daylight", .neutral),
        ("Evening", Look(kelvin: 3400, brightness: 1)),
        ("Night", Look(kelvin: 2300, brightness: 0.85)),
        ("Cave", Look(kelvin: 1700, brightness: 0.6)),
    ]

    /// How long to show true color for.
    public enum OffDuration: CaseIterable {
        case fifteenMinutes, hour, morning, untilTurnedOn
    }

    static let fadeRange = 0...120
    private static let quickFadeSeconds: TimeInterval = 0.6
    private static let fluxBundleID = "org.herf.Flux"

    @Published public var schedule: Schedule { didSet { persist(schedule, "schedule"); update() } }
    @Published public var location: Coordinate? { didSet { persist(location, "location"); update() } }
    @Published public var fadeSeconds: Int { didSet { defaults.set(fadeSeconds, forKey: "fadeSeconds") } }
    @Published private(set) var mode: Mode
    @Published private(set) var state: ScheduleState
    @Published private(set) var previewing: Phase?
    /// When true color ends; `.distantFuture` means when it's turned back on.
    @Published private(set) var offUntil: Date?
    @Published private(set) var fluxRunning = false
    @Published private(set) var locating = false
    @Published private(set) var message: String?

    private struct Fade {
        let from: Look
        let start: Date
        let seconds: TimeInterval
    }

    private let tint: ScreenTint
    private let defaults: UserDefaults
    private let now: () -> Date
    private let locator = LocationProvider()
    private var applied: Look?
    private var timer: Timer?
    private var fade: Fade?
    private var fadeTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// `now` is injectable so checks can drive time; the app uses the real clock.
    public init(tint: ScreenTint, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.tint = tint
        self.defaults = defaults
        self.now = now
        let schedule = Self.load(Schedule.self, "schedule", defaults) ?? .default
        let location = Self.load(Coordinate.self, "location", defaults)
        self.schedule = schedule
        self.location = location
        fadeSeconds = defaults.object(forKey: "fadeSeconds") as? Int ?? 30
        mode = Self.load(Mode.self, "mode", defaults) ?? .schedule
        offUntil = defaults.object(forKey: "offUntil") as? Date
        state = schedule.state(at: now(), location: location)
    }

    /// The look Ember is aiming for right now.
    var target: Look {
        if let previewing { return schedule[previewing].look }
        if off { return .neutral }
        if case .hold(let look, _) = mode { return look }
        return state.look
    }

    var holding: Bool { mode != .schedule }

    var holdSince: Date? {
        if case .hold(_, let since) = mode { return since }
        return nil
    }

    /// The schedule change that ends the current hold.
    var holdEnd: Event? {
        guard let since = holdSince else { return nil }
        return schedule.events(around: since, location: location).first { $0.time > since }
    }

    public var off: Bool { offUntil != nil }

    /// When true color ends, or nil if it lasts until turned back on.
    public var offEnd: Date? { offUntil == .distantFuture ? nil : offUntil }

    /// The next time the Day phase starts.
    public var nextMorning: Date {
        let now = now()
        return schedule.events(around: now, location: location).first { $0.phase == .day && $0.time > now }?.time
            ?? now.addingTimeInterval(24 * 3600)
    }

    var holdName: String {
        Self.presets.first { $0.look == target }?.name ?? "Custom"
    }

    public func start() {
        tint.refresh()  // also clears any tint left behind by a crash
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.periodic() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for (center, name) in [
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.screensDidWakeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.tint.refresh()
                    self?.update()
                }
            }
            observers.append((center, token))
        }
        if location == nil { useCurrentLocation() }
    }

    public func shutdown() {
        timer?.invalidate()
        fadeTimer?.invalidate()
        observers.forEach { $0.0.removeObserver($0.1) }
        tint.restore()
    }

    // MARK: Actions

    /// Holds `look` until the schedule's next change. `fades` is for discrete picks; slider drags pass false.
    public func hold(_ look: Look, fades: Bool = false) {
        setMode(.hold(look, since: holdSince ?? now()), fades: fades)
    }

    public func resume() { setMode(.schedule, fades: true) }

    /// Shows true color until `duration` runs out. Any later look change turns Ember back on.
    public func turnOff(_ duration: OffDuration) {
        let now = now()
        switch duration {
        case .fifteenMinutes: setOff(until: now.addingTimeInterval(15 * 60))
        case .hour: setOff(until: now.addingTimeInterval(3600))
        case .morning: setOff(until: nextMorning)
        case .untilTurnedOn: setOff(until: .distantFuture)
        }
        show(target, over: Self.quickFadeSeconds)
    }

    public func turnOn() {
        setOff(until: nil)
        update(fades: true)
    }

    /// Saves what's on screen as a phase's look.
    func save(as phase: Phase) { schedule[phase].look = target }

    /// Shows a phase's look on screen while its sliders are being dragged.
    func beginPreview(_ phase: Phase) {
        previewing = phase
        show(target, over: 0)
    }

    func endPreview() {
        previewing = nil
        show(target, over: Self.quickFadeSeconds)
    }

    func useCurrentLocation() {
        locating = true
        locator.request { [weak self] result in
            guard let self else { return }
            locating = false
            switch result {
            case .success(let coordinate):
                location = coordinate
                message = nil
            case .failure(let error):
                message = error.localizedDescription
            }
        }
    }

    func quitFlux() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.fluxBundleID).forEach { $0.terminate() }
        // f.lux resets gamma as it exits; the next periodic check notices and re-applies.
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                try setLoginItem(newValue)
                message = nil
            } catch {
                message = "Open at login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }

    private static let loginRegisteredPathKey = "login.registeredPath"

    private func setLoginItem(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
            defaults.set(Bundle.main.bundlePath, forKey: Self.loginRegisteredPathKey)
        } else {
            try SMAppService.mainApp.unregister()
            defaults.removeObject(forKey: Self.loginRegisteredPathKey)
        }
    }

    /// macOS remembers a login item by the path it was registered from, so after the app moves
    /// (the install into /Applications) the entry points at nothing. Called at launch: a login item
    /// registered from somewhere else is registered again from here.
    public func followLoginItemMove() {
        guard SMAppService.mainApp.status == .enabled,
              defaults.string(forKey: Self.loginRegisteredPathKey) != Bundle.main.bundlePath else { return }
        try? SMAppService.mainApp.unregister()
        try? setLoginItem(true)
    }

    // MARK: Updating the screen

    private func setMode(_ newMode: Mode, fades: Bool) {
        setOff(until: nil)
        mode = newMode
        persist(mode, "mode")
        update(fades: fades)
    }

    private func setOff(until date: Date?) {
        offUntil = date
        defaults.set(date, forKey: "offUntil")
    }

    func update(fades: Bool = false) {
        let expired = [expireHold(), expireOff()].contains(true)
        state = schedule.state(at: now(), location: location)
        show(target, over: fades || expired ? TimeInterval(fadeSeconds) : 0)
    }

    /// The 3-second heartbeat: ends holds, follows the schedule, and repairs a reset tint.
    func periodic() {
        fluxRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.fluxBundleID).isEmpty
        let expired = [expireHold(), expireOff()].contains(true)
        state = schedule.state(at: now(), location: location)
        if expired { return show(target, over: TimeInterval(fadeSeconds)) }
        guard fade == nil, previewing == nil else { return }
        if !tint.isIntact() { tint.refresh() }
        show(target, over: 0)
    }

    /// Ends the hold once the schedule reaches its next change. Returns true if it just ended.
    private func expireHold() -> Bool {
        guard let end = holdEnd, end.time <= now() else { return false }
        mode = .schedule
        persist(mode, "mode")
        return true
    }

    /// Turns Ember back on once true color runs out. Returns true if it just did.
    private func expireOff() -> Bool {
        guard let offUntil, offUntil <= now() else { return false }
        setOff(until: nil)
        return true
    }

    private func show(_ look: Look, over seconds: TimeInterval) {
        fadeTimer?.invalidate()
        fadeTimer = nil
        fade = nil
        guard seconds > 0, let from = applied, from != look else { return apply(look) }
        fade = Fade(from: from, start: now(), seconds: seconds)
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepFade() }
        }
    }

    /// Moves an in-progress fade to the current time.
    func stepFade() {
        guard let fade else { return }
        let p = min(now().timeIntervalSince(fade.start) / fade.seconds, 1)
        // Chase the live target so a schedule that is itself easing is met without a jump.
        apply(fade.from.blended(to: target, progress: p * p * (3 - 2 * p)))
        if p >= 1 {
            fadeTimer?.invalidate()
            fadeTimer = nil
            self.fade = nil
        }
    }

    var fading: Bool { fade != nil }

    private func apply(_ look: Look) {
        guard look != applied else { return }
        applied = look
        tint.apply(look.multipliers)
    }

    // MARK: Persistence

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
