import AppKit
import EmberCore
import SwiftUI

public struct MenuBarIcon: View {
    @ObservedObject var controller: Controller

    public init(controller: Controller) { self.controller = controller }

    public var body: some View {
        Image(systemName: controller.off ? "circle.slash" : controller.holding ? "flame.fill" : controller.state.phase.symbol + ".fill")
    }
}

/// The menu bar panel: what's on screen, how to change it, and where the day is headed.
public struct MenuView: View {
    @ObservedObject var controller: Controller
    @Environment(\.openWindow) private var openWindow

    public init(controller: Controller) { self.controller = controller }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if controller.fluxRunning { fluxBanner }
            if controller.off { offCard } else if controller.holding { holdCard } else { scheduleHeader }
            adjust
            presets
            today
            footer
        }
        .padding(18)
        .frame(width: 360)
        .background(Theme.ground)
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    private func badge(_ symbol: String) -> some View {
        Circle()
            .fill(controller.target.swatch)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
            .overlay(Image(systemName: symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(controller.target.ink))
            .frame(width: 52, height: 52)
    }

    private var scheduleHeader: some View {
        HStack(spacing: 14) {
            badge(controller.state.phase.symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(controller.state.phase.name).font(.system(size: 17, weight: .semibold))
                Text(scheduleSubtitle).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var scheduleSubtitle: String {
        let lead = controller.state.transitioning ? "Easing in" : "On schedule"
        guard let next = controller.state.next else { return lead }
        return "\(lead) · \(next.phase.name) at \(next.time.shortTime)"
    }

    private var holdCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                badge("flame")
                VStack(alignment: .leading, spacing: 3) {
                    Text("Holding · \(controller.holdName)").font(.system(size: 17, weight: .semibold))
                    if let end = controller.holdEnd {
                        Text("Until \(end.phase.name) at \(end.time.shortTime)").foregroundStyle(Theme.holdSecondary)
                    }
                }
            }
            HStack(spacing: 8) {
                Button("Resume schedule") { controller.resume() }
                    .buttonStyle(PillButtonStyle(kind: .primary, height: 36, fullWidth: true))
                Menu {
                    ForEach(Phase.allCases, id: \.self) { phase in
                        Button("Save as \(phase.name) look") { controller.save(as: phase) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Save to schedule")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(14)
        .background(Theme.holdCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.35)))
    }

    private var offCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                badge("circle.slash")
                VStack(alignment: .leading, spacing: 3) {
                    Text("Off · true color").font(.system(size: 17, weight: .semibold))
                    Text(controller.offEnd.map { "Until \($0.shortTime)" } ?? "Until you turn it back on")
                        .foregroundStyle(Theme.secondary)
                }
            }
            Button("Turn back on") { controller.turnOn() }
                .buttonStyle(PillButtonStyle(kind: .primary, height: 36, fullWidth: true))
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var fluxBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("f.lux is running and will fight Ember Shift.").font(.callout)
            Spacer()
            Button("Quit f.lux") { controller.quitFlux() }
                .buttonStyle(PillButtonStyle(kind: .secondary, height: 26))
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Controls

    private var adjust: some View {
        let look = controller.target
        return VStack(alignment: .leading, spacing: 14) {
            sliderRow("Warmth", value: "\(Int((look.kelvin / 50).rounded() * 50))K") {
                GradientSlider(
                    value: Binding(
                        get: { controller.target.warmth },
                        set: { controller.hold(Look(kelvin: Look.kelvin(atWarmth: $0), brightness: controller.target.brightness)) }
                    ),
                    colors: Look.warmthColors,
                    label: "Warmth",
                    valueText: "\(Int(look.kelvin)) kelvin"
                )
            }
            sliderRow("Brightness", value: "\(Int((look.brightness * 100).rounded()))%") {
                GradientSlider(
                    value: Binding(
                        get: { controller.target.brightnessFraction },
                        set: { controller.hold(Look(kelvin: controller.target.kelvin, brightness: Look.brightness(atFraction: $0))) }
                    ),
                    colors: look.brightnessColors,
                    label: "Brightness",
                    valueText: "\(Int((look.brightness * 100).rounded())) percent"
                )
            }
            if controller.off || !controller.holding {
                Text(controller.off ? "Adjusting turns Ember Shift back on." : "Adjusting holds your look until the next change.")
                    .font(.caption).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func sliderRow(_ title: String, value: String, @ViewBuilder slider: () -> some View) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).fontWeight(.medium)
                Spacer()
                Text(value).monospacedDigit().foregroundStyle(Theme.secondary)
            }
            slider()
        }
    }

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(Controller.presets, id: \.name) { preset in
                let selected = controller.holding && !controller.off && controller.target == preset.look
                Button {
                    controller.hold(preset.look, fades: true)
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(preset.look.swatch)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
                            .frame(width: 34, height: 34)
                            .padding(3)
                            .overlay(Circle().strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2))
                        Text(preset.name).font(.caption).fontWeight(selected ? .semibold : .regular)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(selected ? Theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: Today

    private var today: some View {
        let now = Date()
        let hold = controller.holdSince.map { since in
            (look: controller.target, from: since, to: controller.holdEnd?.time ?? now)
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY").fontWeight(.semibold).tracking(0.5)
                Spacer()
                Text(controller.holdSince.map { "Held since \($0.shortTime)" } ?? "Now \(now.shortTime)")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondary)
            DayTimeline(schedule: controller.schedule, location: controller.location, now: now, hold: hold)
            HStack(alignment: .top, spacing: 8) {
                ForEach(Phase.allCases, id: \.self) { phase in
                    let current = !controller.holding && controller.state.phase == phase
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current ? "\(phase.name) · now" : phase.name)
                            .fontWeight(current ? .semibold : .regular)
                            .foregroundStyle(current ? Theme.accent : Theme.secondary)
                        Text(controller.schedule.time(of: controller.schedule[phase].start, onDayOf: now, location: controller.location).shortTime)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.caption)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = controller.message {
                Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                iconButton("gearshape", help: "Schedule & settings", window: "settings")
                iconButton("info.circle", help: "About Ember Shift", window: "about")
                offMenu
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(PillButtonStyle(kind: .quiet))
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }

    @ViewBuilder private var offMenu: some View {
        if controller.off {
            Button {
                controller.turnOn()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power").font(.system(size: 13))
                    Text("Turn on")
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .help("Turn Ember Shift back on")
        } else {
            turnOffMenu
        }
    }

    private var turnOffMenu: some View {
        Menu {
            Section("Turn off") {
                ForEach(Controller.OffDuration.allCases, id: \.self) { duration in
                    Button(StatusMenu.title(duration, controller)) { controller.turnOff(duration) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "circle.slash").font(.system(size: 13))
                Text("Turn off")
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Show true color for a while")
    }

    private func iconButton(_ symbol: String, help: String, window: String) -> some View {
        Button {
            openWindow(id: window)
            NSApp.activate()
        } label: {
            Image(systemName: symbol).font(.system(size: 15)).frame(width: 20)
        }
        .buttonStyle(PillButtonStyle(kind: .secondary, height: 32))
        .help(help)
        .accessibilityLabel(help)
    }
}
