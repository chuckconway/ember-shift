import Foundation

public struct Coordinate: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double  // east positive

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Sunrise equation (NOAA / Meeus simplification), accurate to about a minute at mid latitudes.
public enum Solar {
    /// Sunrise and sunset on the calendar day containing `date`. Nil during polar day or night.
    public static func sunTimes(on date: Date, at coordinate: Coordinate, calendar: Calendar = .current) -> (sunrise: Date, sunset: Date)? {
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) else { return nil }
        let base = (julianDay(noon) - 2451545.0).rounded()

        // Pick the solar transit nearest local noon; this sidesteps day-boundary bookkeeping for any longitude.
        let candidates = [base - 1, base, base + 1].map { transit(cycle: $0, coordinate: coordinate) }
        guard let best = candidates.min(by: { abs(fromJulian($0.jd).timeIntervalSince(noon)) < abs(fromJulian($1.jd).timeIntervalSince(noon)) })
        else { return nil }

        let phi = radians(coordinate.latitude)
        let cosOmega = (sin(radians(-0.833)) - sin(phi) * sin(best.declination)) / (cos(phi) * cos(best.declination))
        guard (-1...1).contains(cosOmega) else { return nil }
        let halfDay = degrees(acos(cosOmega)) / 360
        return (fromJulian(best.jd - halfDay), fromJulian(best.jd + halfDay))
    }

    private static func transit(cycle n: Double, coordinate: Coordinate) -> (jd: Double, declination: Double) {
        let jStar = n - coordinate.longitude / 360
        let m = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360)
        let mr = radians(m)
        let c = 1.9148 * sin(mr) + 0.0200 * sin(2 * mr) + 0.0003 * sin(3 * mr)
        let lambda = radians((m + c + 180 + 102.9372).truncatingRemainder(dividingBy: 360))
        let jd = 2451545.0 + jStar + 0.0053 * sin(mr) - 0.0069 * sin(2 * lambda)
        return (jd, asin(sin(lambda) * sin(radians(23.4397))))
    }

    private static func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / 86400 + 2440587.5 }
    private static func fromJulian(_ jd: Double) -> Date { Date(timeIntervalSince1970: (jd - 2440587.5) * 86400) }
    private static func radians(_ d: Double) -> Double { d * .pi / 180 }
    private static func degrees(_ r: Double) -> Double { r * 180 / .pi }
}
