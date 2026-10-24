import Foundation

/// Per-channel gamma multipliers.
public struct RGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// What the screen looks like: a color temperature plus a brightness scale.
public struct Look: Codable, Equatable, Sendable {
    public static let kelvinRange: ClosedRange<Double> = 1200...6500
    public static let brightnessRange: ClosedRange<Double> = 0.2...1

    public var kelvin: Double
    public var brightness: Double

    public init(kelvin: Double, brightness: Double) {
        self.kelvin = kelvin.clamped(to: Self.kelvinRange)
        self.brightness = brightness.clamped(to: Self.brightnessRange)
    }

    public static let neutral = Look(kelvin: 6500, brightness: 1)

    /// Slider position from coolest (0) to warmest (1), linear in mired so equal travel looks like equal change.
    public var warmth: Double {
        let cool = 1e6 / Self.kelvinRange.upperBound, warm = 1e6 / Self.kelvinRange.lowerBound
        return (1e6 / kelvin - cool) / (warm - cool)
    }

    public static func kelvin(atWarmth warmth: Double) -> Double {
        let cool = 1e6 / kelvinRange.upperBound, warm = 1e6 / kelvinRange.lowerBound
        return 1e6 / (cool + (warm - cool) * warmth.clamped(to: 0...1))
    }

    public var multipliers: RGB {
        let m = ColorTemperature.multipliers(kelvin: kelvin)
        return RGB(r: m.r * brightness, g: m.g * brightness, b: m.b * brightness)
    }

    /// Interpolates temperature in mired space (1e6 / K), which changes at a perceptually even rate.
    public func blended(to other: Look, progress: Double) -> Look {
        let p = progress.clamped(to: 0...1)
        if p == 0 { return self }
        if p == 1 { return other }
        let mired = (1e6 / kelvin) + ((1e6 / other.kelvin) - (1e6 / kelvin)) * p
        return Look(kelvin: 1e6 / mired, brightness: brightness + (other.brightness - brightness) * p)
    }
}

public enum ColorTemperature {
    /// Tanner Helland's blackbody approximation, normalized so 6500K is (1, 1, 1).
    public static func multipliers(kelvin: Double) -> RGB {
        let raw = helland(kelvin.clamped(to: Look.kelvinRange))
        let ref = helland(6500)
        return RGB(r: min(raw.r / ref.r, 1), g: min(raw.g / ref.g, 1), b: min(raw.b / ref.b, 1))
    }

    static func helland(_ kelvin: Double) -> RGB {
        let t = kelvin / 100
        let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        return RGB(r: r.clamped(to: 0...255) / 255, g: g.clamped(to: 0...255) / 255, b: b.clamped(to: 0...255) / 255)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
