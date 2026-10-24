import EmberCore
import Foundation

var failures = 0

func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}

func near(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool { abs(a - b) <= tolerance }

func calendar(_ tz: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!
    return c
}

func at(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

func minutesApart(_ a: Date, _ b: Date) -> Double { abs(a.timeIntervalSince(b)) / 60 }

// MARK: Color temperature

let neutral = ColorTemperature.multipliers(kelvin: 6500)
check(near(neutral.r, 1, 1e-9) && near(neutral.g, 1, 1e-9) && near(neutral.b, 1, 1e-9), "6500K is neutral, got \(neutral)")
let warm = ColorTemperature.multipliers(kelvin: 2000)
check(warm.r == 1 && warm.g < 0.7 && warm.b < 0.3, "2000K is warm, got \(warm)")
check(ColorTemperature.multipliers(kelvin: 1200).b == 0, "1200K has no blue")

let mid = Look(kelvin: 6500, brightness: 1).blended(to: Look(kelvin: 2000, brightness: 0.5), progress: 0.5)
check(near(mid.kelvin, 1e6 / ((1e6 / 6500 + 1e6 / 2000) / 2), 0.5), "blend is mired-linear, got \(mid.kelvin)")
check(near(mid.brightness, 0.75, 1e-9), "brightness blends linearly")
check(Look.neutral.warmth == 0 && near(Look(kelvin: 1200, brightness: 1).warmth, 1, 1e-9), "warmth spans the range")
check(near(Look.kelvin(atWarmth: Look(kelvin: 2300, brightness: 1).warmth), 2300, 1e-6), "warmth round-trips")
check(Look(kelvin: 99999, brightness: 0).kelvin == 6500 && Look(kelvin: 0, brightness: 0).brightness == 0.2, "looks clamp")

// MARK: Solar (reference times from timeanddate.com)

let la = calendar("America/Los_Angeles")
let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
if let sun = Solar.sunTimes(on: at(la, 2026, 6, 21, 9, 0), at: sf, calendar: la) {
    check(minutesApart(sun.sunrise, at(la, 2026, 6, 21, 5, 48)) < 3, "SF solstice sunrise, got \(sun.sunrise)")
    check(minutesApart(sun.sunset, at(la, 2026, 6, 21, 20, 35)) < 3, "SF solstice sunset, got \(sun.sunset)")
} else {
    check(false, "SF has sun times")
}

let ny = calendar("America/New_York")
let nyc = Coordinate(latitude: 40.7128, longitude: -74.0060)
if let sun = Solar.sunTimes(on: at(ny, 2026, 12, 21, 23, 30), at: nyc, calendar: ny) {
    check(minutesApart(sun.sunrise, at(ny, 2026, 12, 21, 7, 17)) < 3, "NYC winter sunrise, got \(sun.sunrise)")
    check(minutesApart(sun.sunset, at(ny, 2026, 12, 21, 16, 32)) < 3, "NYC winter sunset, got \(sun.sunset)")
} else {
    check(false, "NYC has sun times")
}

let tokyo = calendar("Asia/Tokyo")
if let sun = Solar.sunTimes(on: at(tokyo, 2026, 3, 20, 1, 0), at: Coordinate(latitude: 35.6762, longitude: 139.6503), calendar: tokyo) {
    check(minutesApart(sun.sunrise, at(tokyo, 2026, 3, 20, 5, 45)) < 3, "Tokyo equinox sunrise, got \(sun.sunrise)")
    check(minutesApart(sun.sunset, at(tokyo, 2026, 3, 20, 17, 53)) < 3, "Tokyo equinox sunset, got \(sun.sunset)")
} else {
    check(false, "Tokyo has sun times")
}

let oslo = calendar("Europe/Oslo")
check(Solar.sunTimes(on: at(oslo, 2026, 12, 21, 12, 0), at: Coordinate(latitude: 69.6492, longitude: 18.9553), calendar: oslo) == nil, "Tromsø polar night")

// MARK: Schedule (no location → 07:00 sunrise / 19:00 sunset fallback)

let utc = calendar("UTC")
var schedule = Schedule.default
schedule.evening.start = .sunset(offsetMinutes: -60)  // 18:00
schedule.night.start = .clock(minutes: 22 * 60)
for phase in Phase.allCases { schedule[phase].easeMinutes = 30 }
let day = schedule.day.look, evening = schedule.evening.look, night = schedule.night.look

func state(_ h: Int, _ m: Int) -> ScheduleState { schedule.state(at: at(utc, 2026, 10, 23, h, m), location: nil, calendar: utc) }

check(state(12, 0) == ScheduleState(look: day, phase: .day, transitioning: false, next: Event(time: at(utc, 2026, 10, 23, 18, 0), phase: .evening)), "midday is day, next is evening at 18:00")
check(state(18, 15).transitioning && state(18, 15).phase == .evening, "18:15 is mid evening transition")
check(near(state(18, 15).look.kelvin, day.blended(to: evening, progress: 0.5).kelvin, 0.5), "18:15 is halfway to evening")
check(state(18, 45).look == evening && !state(18, 45).transitioning, "18:45 is settled evening")
check(state(22, 10).transitioning && state(22, 10).phase == .night, "22:10 is mid night transition")
check(state(3, 0).look == night, "03:00 is night")
check(state(7, 40).look == day, "07:40 is day")
check(schedule.nextStart(of: .day, after: at(utc, 2026, 10, 23, 23, 0), location: nil, calendar: utc) == at(utc, 2026, 10, 24, 7, 0), "next morning is tomorrow 07:00")

// Each phase eases at its own pace.
schedule.night.easeMinutes = 60
check(near(state(22, 30).look.kelvin, evening.blended(to: night, progress: 0.5).kelvin, 0.5), "night eases over its own 60 min")
check(state(22, 45).transitioning, "22:45 still easing into night")
check(state(18, 45).look == evening, "evening still eases over 30 min")

// Overlapping transitions stay continuous: night starts before the evening ease finishes.
schedule.evening.easeMinutes = 120
schedule.night.start = .clock(minutes: 19 * 60)
let before = schedule.state(at: at(utc, 2026, 10, 23, 19, 0).addingTimeInterval(-1), location: nil, calendar: utc).look
let after = schedule.state(at: at(utc, 2026, 10, 23, 19, 0).addingTimeInterval(1), location: nil, calendar: utc).look
check(near(before.kelvin, after.kelvin, 2) && near(before.brightness, after.brightness, 0.001), "no jump when transitions overlap: \(before) vs \(after)")

// Zero-length transitions snap.
schedule.evening.easeMinutes = 0
check(schedule.state(at: at(utc, 2026, 10, 23, 18, 0), location: nil, calendar: utc).look == evening, "zero transition snaps")

// Round-trips through persistence.
let decoded = try JSONDecoder().decode(Schedule.self, from: JSONEncoder().encode(schedule))
check(decoded == schedule, "schedule round-trips through JSON")

print(failures == 0 ? "All checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
