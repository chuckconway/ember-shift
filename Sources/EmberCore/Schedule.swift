import Foundation

/// When a phase begins: relative to the sun, or at a fixed clock time.
public enum Anchor: Codable, Equatable, Sendable {
    case sunrise(offsetMinutes: Int)
    case sunset(offsetMinutes: Int)
    case clock(minutes: Int)  // minutes after local midnight
}

public enum Phase: String, Codable, CaseIterable, Sendable {
    case day, evening, night

    public var name: String { rawValue.capitalized }
}

public struct PhaseSetting: Codable, Equatable, Sendable {
    public static let easeRange = 0...180

    public var start: Anchor
    public var look: Look
    /// The change into this phase starts at `start` and eases over this many minutes.
    public var easeMinutes: Int

    public init(start: Anchor, look: Look, easeMinutes: Int) {
        self.start = start
        self.look = look
        self.easeMinutes = easeMinutes
    }
}

public struct Event: Equatable, Sendable {
    public let time: Date
    public let phase: Phase

    public init(time: Date, phase: Phase) {
        self.time = time
        self.phase = phase
    }
}

public struct ScheduleState: Equatable, Sendable {
    public let look: Look
    public let phase: Phase
    public let transitioning: Bool
    public let next: Event?

    public init(look: Look, phase: Phase, transitioning: Bool, next: Event?) {
        self.look = look
        self.phase = phase
        self.transitioning = transitioning
        self.next = next
    }
}

public struct Schedule: Codable, Equatable, Sendable {
    /// Used when no location is known or the sun doesn't rise or set (polar day/night).
    public static let fallbackSunrise = 7 * 60
    public static let fallbackSunset = 19 * 60

    public var day: PhaseSetting
    public var evening: PhaseSetting
    public var night: PhaseSetting

    public init(day: PhaseSetting, evening: PhaseSetting, night: PhaseSetting) {
        self.day = day
        self.evening = evening
        self.night = night
    }

    public static let `default` = Schedule(
        day: PhaseSetting(start: .sunrise(offsetMinutes: 0), look: .neutral, easeMinutes: 30),
        evening: PhaseSetting(start: .sunset(offsetMinutes: 0), look: Look(kelvin: 3400, brightness: 1), easeMinutes: 30),
        night: PhaseSetting(start: .clock(minutes: 22 * 60 + 30), look: Look(kelvin: 2300, brightness: 0.85), easeMinutes: 30)
    )

    public subscript(phase: Phase) -> PhaseSetting {
        get {
            switch phase {
            case .day: day
            case .evening: evening
            case .night: night
            }
        }
        set {
            switch phase {
            case .day: day = newValue
            case .evening: evening = newValue
            case .night: night = newValue
            }
        }
    }

    public func time(of anchor: Anchor, onDayOf date: Date, location: Coordinate?, calendar: Calendar = .current) -> Date {
        func clock(_ minutes: Int) -> Date {
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date) ?? date
        }
        let sun = location.flatMap { Solar.sunTimes(on: date, at: $0, calendar: calendar) }
        switch anchor {
        case .clock(let minutes): return clock(minutes)
        case .sunrise(let offset): return (sun?.sunrise ?? clock(Self.fallbackSunrise)).addingTimeInterval(Double(offset) * 60)
        case .sunset(let offset): return (sun?.sunset ?? clock(Self.fallbackSunset)).addingTimeInterval(Double(offset) * 60)
        }
    }

    /// Phase starts from two days before `date` to two days after, in time order.
    public func events(around date: Date, location: Coordinate?, calendar: Calendar = .current) -> [Event] {
        (-2...2).flatMap { offset -> [Event] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { return [] }
            return Phase.allCases.map { Event(time: time(of: self[$0].start, onDayOf: day, location: location, calendar: calendar), phase: $0) }
        }
        .sorted { $0.time < $1.time }
    }

    public func nextStart(of phase: Phase, after date: Date, location: Coordinate?, calendar: Calendar = .current) -> Date? {
        events(around: date, location: location, calendar: calendar).first { $0.phase == phase && $0.time > date }?.time
    }

    public func state(at date: Date, location: Coordinate?, calendar: Calendar = .current) -> ScheduleState {
        let events = events(around: date, location: location, calendar: calendar)
        guard let current = events.lastIndex(where: { $0.time <= date }) else {
            return ScheduleState(look: self[.night].look, phase: .night, transitioning: false, next: events.first)
        }

        // Walk forward from a settled point so a change that starts mid-transition begins from the real on-screen look.
        var startLook = self[events[0].phase].look
        for i in stride(from: 1, through: current, by: 1) {
            startLook = startLook.blended(to: self[events[i - 1].phase].look, progress: progress(into: events[i - 1].phase, after: events[i].time.timeIntervalSince(events[i - 1].time)))
        }
        let p = progress(into: events[current].phase, after: date.timeIntervalSince(events[current].time))
        return ScheduleState(
            look: startLook.blended(to: self[events[current].phase].look, progress: p),
            phase: events[current].phase,
            transitioning: p < 1,
            next: events.indices.contains(current + 1) ? events[current + 1] : nil
        )
    }

    private func progress(into phase: Phase, after elapsed: TimeInterval) -> Double {
        let minutes = self[phase].easeMinutes
        return minutes <= 0 ? 1 : (elapsed / (Double(minutes) * 60)).clamped(to: 0...1)
    }
}
