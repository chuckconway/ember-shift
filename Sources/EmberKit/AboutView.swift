import EmberCore
import SwiftUI

public struct AboutView: View {
    public init() {}

    private var version: String {
        guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return "Development build" }
        return "Version \(short)"
    }

    public var body: some View {
        VStack(spacing: 18) {
            Circle()
                .fill(LinearGradient(colors: Controller.presets.map(\.look.swatch), startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
                .overlay(Image(systemName: "flame").font(.system(size: 34, weight: .medium)).foregroundStyle(Color(hex: 0xFFE3C7)).shadow(radius: 2))
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Ember Shift").font(.system(size: 22, weight: .bold))
                Text(version).foregroundStyle(Theme.secondary).monospacedDigit()
            }
            Text("Warms and dims your screen as the day winds down, and lets you take over whenever you want. A look you hold stays until the schedule's next change.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                credit("Color", "Tanner Helland's blackbody approximation, blended in mired space")
                credit("Sun times", "NOAA sunrise equation")
                credit("Display", "Per-display gamma tables, re-applied if macOS resets them")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.windowCard, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(28)
        .frame(width: 380)
        .background(Theme.windowGround)
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
    }

    private func credit(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).foregroundStyle(Theme.secondary).frame(width: 70, alignment: .leading)
            Text(detail).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
