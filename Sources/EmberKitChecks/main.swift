@testable import EmberKit
import EmberCore
import Foundation

// Controller checks: holds, fades, previews, persistence and tint repair, driven by a fake clock
// and observed through what gets written to a fake display.
//
// With no location the schedule uses its fallback sun times, so the default schedule here is
// Day 07:00, Evening 19:00, Night 22:30, each easing in over 30 minutes.

var failures = 0

func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}

func near(_ a: RGB?, _ b: RGB, _ tolerance: Double = 0.002) -> Bool {
    guard let a else { return false }
    return abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
}

func at(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 23) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m, second: s))!
}

@MainActor
final class RecordingTint: ScreenTint {
    var writes: [RGB] = []
    var refreshes = 0
    var intact = true
    var last: RGB? { writes.last }

    func apply(_ multipliers: RGB) { writes.append(multipliers) }
    func refresh() {
        refreshes += 1
        intact = true
    }
    func isIntact() -> Bool { intact }
    func restore() {}
}

final class Clock {
    var time: Date
    init(_ time: Date) { self.time = time }
    func advance(_ seconds: TimeInterval) { time = time.addingTimeInterval(seconds) }
}

var suiteCounter = 0

@MainActor
func fresh(at time: Date, defaults existing: UserDefaults? = nil) -> (Controller, RecordingTint, Clock, UserDefaults) {
    let defaults: UserDefaults
    if let existing {
        defaults = existing
    } else {
        suiteCounter += 1
        let name = "com.cconway.ember.checks.\(suiteCounter)"
        UserDefaults().removePersistentDomain(forName: name)
        defaults = UserDefaults(suiteName: name)!
    }
    let tint = RecordingTint()
    let clock = Clock(time)
    return (Controller(tint: tint, defaults: defaults, now: { clock.time }), tint, clock, defaults)
}

let schedule = Schedule.default
let day = schedule.day.look, evening = schedule.evening.look, night = schedule.night.look
let custom = Look(kelvin: 2000, brightness: 0.7)

MainActor.assumeIsolated {
    let cave = Controller.presets[3].look

    // Follows the schedule.
    do {
        let (c, tint, _, _) = fresh(at: at(12, 0))
        c.update()
        check(near(tint.last, day.multipliers), "noon shows the day look")
        check(!c.holding, "starts on the schedule")
    }

    // A slider drag holds instantly.
    do {
        let (c, tint, _, _) = fresh(at: at(12, 0))
        c.update()
        c.hold(custom)
        check(near(tint.last, custom.multipliers), "slider hold applies at once")
        check(c.holding && !c.fading, "slider hold doesn't fade")
    }

    // A preset fades in over fadeSeconds.
    do {
        let (c, tint, clock, _) = fresh(at: at(12, 0))
        c.update()
        c.hold(cave, fades: true)
        check(near(tint.last, day.multipliers) && c.fading, "preset starts a fade from the current look")
        clock.advance(15)
        c.stepFade()
        let mid = tint.last!
        check(mid.r < 1 && mid.r > cave.multipliers.r && !near(mid, cave.multipliers), "halfway through the fade is between the looks: \(mid)")
        clock.advance(15)
        c.stepFade()
        check(near(tint.last, cave.multipliers) && !c.fading, "fade lands on the preset after 30 s")
    }

    // A hold ends at the schedule's next change, then fades back.
    do {
        let (c, tint, clock, _) = fresh(at: at(12, 0))
        c.update()
        c.hold(cave)
        check(c.holdEnd == Event(time: at(19, 0), phase: .evening), "noon hold ends when Evening starts, got \(String(describing: c.holdEnd))")
        clock.time = at(18, 59)
        c.periodic()
        check(c.holding && near(tint.last, cave.multipliers), "still holding a minute before")
        clock.time = at(19, 0, 1)
        c.periodic()
        check(!c.holding && c.fading, "hold ends at Evening and fades")
        let target = schedule.state(at: at(19, 0, 1), location: nil).look
        clock.advance(30)
        c.stepFade()
        check(near(tint.last, target.multipliers), "fade lands on the schedule's look")
    }

    // An evening hold runs until Night.
    do {
        let (c, _, _, _) = fresh(at: at(20, 0))
        c.hold(cave)
        check(c.holdEnd == Event(time: at(22, 30), phase: .night), "8 PM hold ends at Night 10:30 PM")
    }

    // Adjusting a hold keeps its start, so it still ends at the same change.
    do {
        let (c, _, clock, _) = fresh(at: at(12, 0))
        c.hold(cave)
        clock.time = at(18, 30)
        c.hold(custom)
        check(c.holdEnd?.time == at(19, 0), "adjusted hold still ends at 7 PM")
    }

    // Resume fades back to the schedule.
    do {
        let (c, tint, clock, _) = fresh(at: at(12, 0))
        c.update()
        c.hold(cave)
        c.resume()
        check(!c.holding && c.fading, "resume returns to the schedule with a fade")
        clock.advance(30)
        c.stepFade()
        check(near(tint.last, day.multipliers), "resume lands on the day look")
    }

    // A zero fade is instant.
    do {
        let (c, tint, _, _) = fresh(at: at(12, 0))
        c.update()
        c.fadeSeconds = 0
        c.hold(cave, fades: true)
        check(near(tint.last, cave.multipliers) && !c.fading, "fadeSeconds 0 switches at once")
    }

    // Previewing a phase shows its look, follows edits, and returns quickly.
    do {
        let (c, tint, clock, _) = fresh(at: at(12, 0))
        c.update()
        c.beginPreview(.night)
        check(near(tint.last, night.multipliers), "preview shows the Night look at once")
        c.schedule.night.look = custom
        check(near(tint.last, custom.multipliers), "preview follows slider edits")
        c.endPreview()
        check(c.fading, "ending a preview fades back")
        clock.advance(1)
        c.stepFade()
        check(near(tint.last, day.multipliers), "preview returns to the day look within a second")
    }

    // Save to schedule.
    do {
        let (c, _, _, _) = fresh(at: at(12, 0))
        c.hold(custom)
        c.save(as: .evening)
        check(c.schedule.evening.look == custom, "Save as Evening stores the held look")
    }

    // A hold survives a relaunch.
    do {
        let (first, _, _, defaults) = fresh(at: at(12, 0))
        first.hold(cave)
        let (second, tint, _, _) = fresh(at: at(12, 5), defaults: defaults)
        second.update()
        check(second.holding && near(tint.last, cave.multipliers), "relaunch restores the hold")
    }

    // A hold that ended while the app was closed doesn't come back.
    do {
        let (first, _, _, defaults) = fresh(at: at(12, 0))
        first.hold(cave)
        let (second, tint, _, _) = fresh(at: at(19, 45), defaults: defaults)
        second.update()
        check(!second.holding && near(tint.last, evening.multipliers), "relaunch after the change follows the schedule")
    }

    // Settings saved by an older build are ignored rather than crashing.
    do {
        let (_, _, _, defaults) = fresh(at: at(12, 0))
        defaults.set(Data(#"{"hold":{"_0":{"kelvin":6500,"brightness":1}}}"#.utf8), forKey: "mode")
        let (c, _, _, _) = fresh(at: at(12, 0), defaults: defaults)
        check(!c.holding, "old hold format falls back to the schedule")
    }

    // A reset tint gets repaired, but not mid-fade.
    do {
        let (c, tint, _, _) = fresh(at: at(12, 0))
        c.update()
        tint.intact = false
        c.periodic()
        check(tint.refreshes == 1, "heartbeat repairs a reset tint")

        c.hold(cave, fades: true)
        tint.intact = false
        c.periodic()
        check(tint.refreshes == 1, "heartbeat leaves the display alone during a fade")
    }

    // Fresh holds after one ends pick up the next change.
    do {
        let (c, _, clock, _) = fresh(at: at(12, 0))
        c.hold(cave)
        clock.time = at(19, 1)
        c.periodic()
        c.hold(custom)
        check(c.holdEnd?.time == at(22, 30), "a new hold after 7 PM ends at Night")
    }

    // Turning off shows true color for the chosen time, then fades back to the schedule.
    do {
        let (c, tint, clock, _) = fresh(at: at(20, 0))
        c.update()
        c.turnOff(.hour)
        check(c.off && c.offEnd == at(21, 0), "off for an hour ends at 9 PM, got \(String(describing: c.offEnd))")
        clock.advance(1)
        c.stepFade()
        check(near(tint.last, Look.neutral.multipliers), "off shows true color within a second")
        clock.time = at(20, 59)
        c.periodic()
        check(c.off && near(tint.last, Look.neutral.multipliers), "still off a minute before")
        clock.time = at(21, 0, 1)
        c.periodic()
        check(!c.off && c.fading, "turns back on at 9 PM with a fade")
        clock.advance(30)
        c.stepFade()
        check(near(tint.last, evening.multipliers), "lands on the evening look")
    }

    // Off until morning lasts until Day starts; off until turned on lasts.
    do {
        let (c, _, clock, _) = fresh(at: at(20, 0))
        c.turnOff(.fifteenMinutes)
        check(c.offEnd == at(20, 15), "15 minutes ends at 8:15 PM")
        c.turnOff(.morning)
        check(c.offEnd == at(7, 0, day: 24), "until morning ends at Day tomorrow, got \(String(describing: c.offEnd))")
        c.turnOff(.untilTurnedOn)
        clock.time = at(12, 0, day: 30)
        c.periodic()
        check(c.off && c.offEnd == nil, "until turned on survives a week")
        c.turnOn()
        check(!c.off, "turn back on")
    }

    // Changing the look while off turns Ember back on; previews still show.
    do {
        let (c, tint, _, _) = fresh(at: at(20, 0))
        c.update()
        c.turnOff(.untilTurnedOn)
        c.beginPreview(.night)
        check(near(tint.last, night.multipliers), "preview shows while off")
        c.endPreview()
        check(c.off, "preview doesn't turn it on")
        c.hold(custom)
        check(!c.off && near(tint.last, custom.multipliers), "a slider drag turns it back on")
        c.turnOff(.hour)
        c.hold(cave, fades: true)
        check(!c.off, "a preset turns it back on")
        c.turnOff(.hour)
        c.resume()
        check(!c.off, "resume turns it back on")
    }

    // Off survives a relaunch, and a relaunch after it ran out follows the schedule.
    do {
        let (first, _, _, defaults) = fresh(at: at(20, 0))
        first.turnOff(.hour)
        let (second, tint, _, _) = fresh(at: at(20, 30), defaults: defaults)
        second.update()
        check(second.off && near(tint.last, Look.neutral.multipliers), "relaunch stays off")
        let (third, tint3, _, _) = fresh(at: at(21, 30), defaults: defaults)
        third.update()
        check(!third.off && near(tint3.last, evening.multipliers), "relaunch after it ran out follows the schedule")
    }

    // The right-click menu offers the durations, and turning back on when off.
    do {
        let (c, _, _, _) = fresh(at: at(20, 0))
        let titles = { StatusMenu(controller: c).menu().items.map(\.title) }
        check(titles().contains("For an hour") && !titles().contains("Turn back on"), "menu when on: \(titles())")
        c.turnOff(.hour)
        check(titles().first == "Off until \(at(21, 0).shortTime)" && titles().contains("Turn back on"), "menu when off: \(titles())")
    }
}

print(failures == 0 ? "All controller checks passed" : "\(failures) controller check(s) failed")
exit(failures == 0 ? 0 : 1)
