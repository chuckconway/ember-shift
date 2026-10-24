import EmberCore
import SwiftUI

public struct ScheduleWindow: View {
    @ObservedObject var controller: Controller

    public init(controller: Controller) { self.controller = controller }

    public var body: some View {
        ScrollView { ScheduleContent(controller: controller) }
            .frame(width: 620)
            .frame(minHeight: 560, idealHeight: 1000)
            .background(Theme.windowGround)
            .environment(\.colorScheme, .dark)
    }
}

/// The window's content, separate from its ScrollView so it can be snapshotted at full height.
public struct ScheduleContent: View {
    @ObservedObject var controller: Controller

    public init(controller: Controller) { self.controller = controller }

    public var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Schedule").font(.system(size: 22, weight: .bold))
                DayTimeline(schedule: controller.schedule, location: controller.location, now: now, height: 34, markerBorder: Theme.windowGround)
                HStack {
                    ForEach(Array(["12 AM", "6 AM", "12 PM", "6 PM", "12 AM"].enumerated()), id: \.offset) { index, hour in
                        if index > 0 { Spacer() }
                        Text(hour)
                    }
                }
                .hourLabels()
                Text("Drag any slider below to preview that look on screen. Release to go back.")
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(Phase.allCases, id: \.self) { phase in
                PhaseCard(controller: controller, phase: phase, now: now)
            }
            GeneralCard(controller: controller)
        }
        .padding(24)
        .frame(width: 620, alignment: .leading)
        .background(Theme.windowGround)
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
    }
}

private extension View {
    func hourLabels() -> some View {
        self.font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.tertiary)
    }
}

struct PhaseCard: View {
    @ObservedObject var controller: Controller
    let phase: Phase
    let now: Date

    private var setting: PhaseSetting { controller.schedule[phase] }
    private var current: Bool { !controller.holding && controller.state.phase == phase }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: phase.symbol).foregroundStyle(Theme.accent).font(.system(size: 15, weight: .semibold))
                Text(phase.name).font(.system(size: 15, weight: .semibold))
                if current { Text("· now").font(.caption).foregroundStyle(Theme.accent) }
                Spacer()
                Text("Today \(controller.schedule.time(of: setting.start, onDayOf: now, location: controller.location).shortTime)")
                    .foregroundStyle(Theme.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    label("Starts")
                    AnchorControls(anchor: $controller.schedule[phase].start, sunName: phase == .day ? "Sunrise" : "Sunset")
                }
                GridRow {
                    label("Eases in")
                    StepperField(
                        text: setting.easeMinutes == 0 ? "Instantly" : "over \(setting.easeMinutes) min",
                        decrementLabel: "Shorter", incrementLabel: "Longer",
                        decrement: { adjustEase(-5) }, increment: { adjustEase(5) }
                    )
                }
                GridRow {
                    label("Warmth")
                    lookSlider(
                        value: Binding(
                            get: { setting.look.warmth },
                            set: { controller.schedule[phase].look = Look(kelvin: Look.kelvin(atWarmth: $0), brightness: setting.look.brightness) }
                        ),
                        colors: Look.warmthColors, title: "\(phase.name) warmth",
                        text: "\(Int((setting.look.kelvin / 50).rounded() * 50))K"
                    )
                }
                GridRow {
                    label("Brightness")
                    lookSlider(
                        value: Binding(
                            get: { setting.look.brightnessFraction },
                            set: { controller.schedule[phase].look = Look(kelvin: setting.look.kelvin, brightness: Look.brightness(atFraction: $0)) }
                        ),
                        colors: setting.look.brightnessColors, title: "\(phase.name) brightness",
                        text: "\(Int((setting.look.brightness * 100).rounded()))%"
                    )
                }
            }
        }
        .padding(16)
        .background(Theme.windowCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(current ? Theme.accent.opacity(0.35) : .clear))
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.secondary).frame(width: 80, alignment: .leading)
    }

    private func adjustEase(_ delta: Int) {
        let range = PhaseSetting.easeRange
        controller.schedule[phase].easeMinutes = min(max(setting.easeMinutes + delta, range.lowerBound), range.upperBound)
    }

    private func lookSlider(value: Binding<Double>, colors: [Color], title: String, text: String) -> some View {
        HStack(spacing: 12) {
            GradientSlider(value: value, colors: colors, label: title, valueText: text) { editing in
                editing ? controller.beginPreview(phase) : controller.endPreview()
            }
            Text(text).monospacedDigit().foregroundStyle(Theme.secondary).frame(width: 52, alignment: .trailing)
        }
    }
}

struct AnchorControls: View {
    @Binding var anchor: EmberCore.Anchor
    let sunName: String

    private var usesSun: Binding<Bool> {
        Binding(
            get: { if case .clock = anchor { false } else { true } },
            set: { anchor = $0 ? solar(0) : .clock(minutes: sunName == "Sunrise" ? 7 * 60 : 19 * 60) }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Picker("Starts", selection: usesSun) {
                Text(sunName).tag(true)
                Text("Clock time").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            switch anchor {
            case .clock(let minutes):
                DatePicker("Start time", selection: Binding(
                    get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(minutes) * 60) },
                    set: {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                        anchor = .clock(minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0))
                    }
                ), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .fixedSize()
            case .sunrise(let offset), .sunset(let offset):
                StepperField(
                    text: offsetText(offset), decrementLabel: "Earlier", incrementLabel: "Later",
                    decrement: { anchor = solar(max(offset - 15, -240)) },
                    increment: { anchor = solar(min(offset + 15, 240)) }
                )
            }
        }
    }

    private func solar(_ offset: Int) -> EmberCore.Anchor {
        sunName == "Sunrise" ? .sunrise(offsetMinutes: offset) : .sunset(offsetMinutes: offset)
    }

    private func offsetText(_ offset: Int) -> String {
        if offset == 0 { return "At \(sunName.lowercased())" }
        let h = abs(offset) / 60, m = abs(offset) % 60
        let amount = h > 0 ? (m > 0 ? "\(h)h \(m)m" : "\(h)h") : "\(m)m"
        return "\(amount) \(offset < 0 ? "before" : "after")"
    }
}

struct GeneralCard: View {
    @ObservedObject var controller: Controller
    @State private var manual = false
    @State private var latitude = ""
    @State private var longitude = ""

    var body: some View {
        VStack(spacing: 0) {
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fade when switching looks")
                    Text("Presets, Resume, and a hold ending").font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                StepperField(
                    text: controller.fadeSeconds == 0 ? "Instantly" : "\(controller.fadeSeconds) s",
                    decrementLabel: "Faster", incrementLabel: "Slower", minWidth: 64,
                    decrement: { controller.fadeSeconds = max(controller.fadeSeconds - 5, Controller.fadeRange.lowerBound) },
                    increment: { controller.fadeSeconds = min(controller.fadeSeconds + 5, Controller.fadeRange.upperBound) }
                )
            }
            divider
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location for sun times")
                    Text(locationText).font(.caption).monospacedDigit().foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("Enter manually") { manual.toggle() }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                Button {
                    controller.useCurrentLocation()
                } label: {
                    Label(controller.locating ? "Locating…" : "Update", systemImage: "location")
                }
                .buttonStyle(PillButtonStyle(kind: .secondary, height: 28))
                .disabled(controller.locating)
            }
            if manual {
                HStack(spacing: 8) {
                    TextField("Latitude", text: $latitude).frame(width: 110)
                    TextField("Longitude", text: $longitude).frame(width: 110)
                    Button("Set") {
                        if let lat = Double(latitude), let lon = Double(longitude), (-90...90).contains(lat), (-180...180).contains(lon) {
                            controller.location = Coordinate(latitude: lat, longitude: lon)
                            manual = false
                        }
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary, height: 28))
                    .disabled(Double(latitude) == nil || Double(longitude) == nil)
                    Spacer()
                }
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            divider
            row {
                Toggle("Open Ember Shift at login", isOn: Binding(get: { controller.launchAtLogin }, set: { controller.launchAtLogin = $0 }))
                    .toggleStyle(.checkbox)
                Spacer()
            }
            if let message = controller.message {
                Text(message).font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .bottom], 16)
            }
        }
        .background(Theme.windowCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private var locationText: String {
        guard let c = controller.location else { return "Not set · assuming 7:00 AM sunrise, 7:00 PM sunset" }
        return String(format: "%.2f, %.2f", c.latitude, c.longitude)
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }

    private func row(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 12, content: content).padding(.horizontal, 16).frame(minHeight: 56)
    }
}
