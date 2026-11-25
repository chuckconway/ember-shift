import EmberCore
import SwiftUI

enum Theme {
    static let ground = Color(hex: 0x232020)
    static let card = Color(hex: 0x2C2826)
    static let raised = Color(hex: 0x3A3532)
    static let inset = Color(hex: 0x1C1A19)
    static let segmentOn = Color(hex: 0x4A4440)
    static let holdCard = Color(hex: 0x33241A)
    static let windowGround = Color(hex: 0x1C1A19)
    static let windowCard = Color(hex: 0x262322)
    static let text = Color(hex: 0xF3EEE8)
    static let secondary = Color(hex: 0xABA49C)
    static let tertiary = Color(hex: 0x978F88)
    static let holdSecondary = Color(hex: 0xC9BBAE)
    static let accent = Color(hex: 0xF28C38)
    static let onAccent = Color(hex: 0x1E1410)
    static let hairline = Color.white.opacity(0.08)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Look {
    /// How white looks under this tint.
    var swatch: Color {
        let m = multipliers
        return Color(red: m.r, green: m.g, blue: m.b)
    }

    /// Icon color that stays legible on this look's swatch.
    var ink: Color {
        let m = multipliers
        return 0.2126 * m.r + 0.7152 * m.g + 0.0722 * m.b > 0.55 ? Color(hex: 0x5A2E0C) : Color(hex: 0xFFE3C7)
    }

    var summary: String { "\(Int((kelvin / 50).rounded() * 50))K · \(Int((brightness * 100).rounded()))%" }

    static let warmthColors = (0...8).map { Look(kelvin: Look.kelvin(atWarmth: Double($0) / 8), brightness: 1).swatch }

    var brightnessColors: [Color] { [Look(kelvin: kelvin, brightness: Look.brightnessRange.lowerBound).swatch, Look(kelvin: kelvin, brightness: 1).swatch] }

    var brightnessFraction: Double {
        (brightness - Look.brightnessRange.lowerBound) / (Look.brightnessRange.upperBound - Look.brightnessRange.lowerBound)
    }

    static func brightness(atFraction f: Double) -> Double {
        brightnessRange.lowerBound + (brightnessRange.upperBound - brightnessRange.lowerBound) * f
    }
}

extension Phase {
    var symbol: String {
        switch self {
        case .day: "sun.max"
        case .evening: "sunset"
        case .night: "lamp.table"
        }
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

/// A slider whose track shows the colors it moves through.
struct GradientSlider: View {
    @Binding var value: Double  // 0...1
    let colors: [Color]
    let label: String
    let valueText: String
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragging = false
    private let thumb: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - thumb, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
                    .frame(height: 8)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.15)))
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                    .frame(width: thumb, height: thumb)
                    .offset(x: travel * value.clampedUnit)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging {
                            dragging = true
                            onEditingChanged(true)
                        }
                        value = ((g.location.x - thumb / 2) / travel).clampedUnit
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: thumb)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = (value + 0.05).clampedUnit
            case .decrement: value = (value - 0.05).clampedUnit
            @unknown default: break
            }
        }
    }
}

private extension Double {
    var clampedUnit: Double { Swift.min(Swift.max(self, 0), 1) }
}

/// Today's 24 hours as the colors the screen will be, with a "now" marker and an optional hold band.
struct DayTimeline: View {
    let schedule: Schedule
    let location: Coordinate?
    let now: Date
    var hold: (look: Look, from: Date, to: Date)?
    var height: CGFloat = 22
    var markerBorder: Color = Theme.card

    var body: some View {
        let day = Calendar.current.startOfDay(for: now)
        let length = (Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)).timeIntervalSince(day)
        let stops = (0...96).map { i in
            Gradient.Stop(color: schedule.state(at: day.addingTimeInterval(length * Double(i) / 96), location: location).look.swatch, location: Double(i) / 96)
        }
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (date: Date) in CGFloat(min(max(date.timeIntervalSince(day) / length, 0), 1)) * width }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.12)))
                    .opacity(hold == nil ? 1 : 0.45)
                if let hold {
                    Hatch(color: hold.look.swatch)
                        .frame(width: max(x(hold.to) - x(hold.from), 2), height: height)
                        .offset(x: x(hold.from))
                }
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.text)
                    .frame(width: 3, height: height + 8)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(markerBorder, lineWidth: 1.5))
                    .offset(x: x(now) - 1.5)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct Hatch: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
            var stripes = Path()
            var x = -size.height
            while x < size.width {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 8
            }
            context.stroke(stripes, with: .color(.black.opacity(0.22)), lineWidth: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.accent.opacity(0.7)))
    }
}

/// − value + in a recessed pill.
struct StepperField: View {
    let text: String
    let decrementLabel: String
    let incrementLabel: String
    var minWidth: CGFloat = 92
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: decrement) { Text("−").frame(width: 28, height: 26).contentShape(Rectangle()) }
                .accessibilityLabel(decrementLabel)
            Text(text).monospacedDigit().frame(minWidth: minWidth)
            Button(action: increment) { Text("+").frame(width: 28, height: 26).contentShape(Rectangle()) }
                .accessibilityLabel(incrementLabel)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .padding(2)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .secondary
    var height: CGFloat = 32
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .primary ? .body.weight(.semibold) : .body)
            .foregroundStyle(kind == .primary ? Theme.onAccent : kind == .quiet ? Theme.secondary : Theme.text)
            .padding(.horizontal, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.accent
        case .secondary: Theme.raised
        case .quiet: .clear
        }
    }
}
