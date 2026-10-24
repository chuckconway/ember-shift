import CoreGraphics
import EmberCore

/// Where a look ends up. `DisplayGamma` in the app; `NoTint` for snapshots.
@MainActor
public protocol ScreenTint: AnyObject {
    func apply(_ multipliers: RGB)
    /// Re-reads display baselines and re-applies the current tint.
    func refresh()
    /// False when something (macOS, another app) has overwritten the tint.
    func isIntact() -> Bool
    func restore()
}

@MainActor
public final class NoTint: ScreenTint {
    public init() {}
    public func apply(_ multipliers: RGB) {}
    public func refresh() {}
    public func isIntact() -> Bool { true }
    public func restore() {}
}

/// Tints every online display by scaling its ColorSync gamma table.
///
/// macOS silently resets gamma on sleep/wake, display changes, and when other apps
/// (f.lux, Night Shift) touch it. `isIntact()` detects that so the caller can re-apply.
@MainActor
public final class DisplayGamma: ScreenTint {
    private struct Table {
        var r: [CGGammaValue]
        var g: [CGGammaValue]
        var b: [CGGammaValue]
    }

    /// Each display's untinted table, captured right after a ColorSync restore.
    private var baselines: [CGDirectDisplayID: Table] = [:]
    private var current: RGB?

    public init() {}

    public func apply(_ multipliers: RGB) {
        current = multipliers
        if Set(onlineDisplays()) != Set(baselines.keys) {
            refresh()
        } else {
            write(multipliers)
        }
    }

    /// Resets to ColorSync, recaptures baselines (picking up new displays), and re-applies the tint.
    public func refresh() {
        CGDisplayRestoreColorSyncSettings()
        baselines = [:]
        for id in onlineDisplays() {
            let capacity = Int(CGDisplayGammaTableCapacity(id))
            var table = Table(r: .init(repeating: 0, count: capacity), g: .init(repeating: 0, count: capacity), b: .init(repeating: 0, count: capacity))
            var count: UInt32 = 0
            guard CGGetDisplayTransferByTable(id, UInt32(capacity), &table.r, &table.g, &table.b, &count) == .success, count > 0 else { continue }
            table.r.removeLast(capacity - Int(count))
            table.g.removeLast(capacity - Int(count))
            table.b.removeLast(capacity - Int(count))
            baselines[id] = table
        }
        if let current { write(current) }
    }

    public func isIntact() -> Bool {
        guard let current else { return true }
        guard Set(onlineDisplays()) == Set(baselines.keys) else { return false }
        for (id, base) in baselines {
            let n = base.r.count
            var r = [CGGammaValue](repeating: 0, count: n), g = r, b = r
            var count: UInt32 = 0
            guard CGGetDisplayTransferByTable(id, UInt32(n), &r, &g, &b, &count) == .success, Int(count) == n else { return false }
            let expected = scaled(base, by: current)
            if abs(r[n - 1] - expected.r[n - 1]) > 0.01 || abs(g[n - 1] - expected.g[n - 1]) > 0.01 || abs(b[n - 1] - expected.b[n - 1]) > 0.01 {
                return false
            }
        }
        return true
    }

    public func restore() {
        current = nil
        CGDisplayRestoreColorSyncSettings()
    }

    private func write(_ multipliers: RGB) {
        for (id, base) in baselines {
            let t = scaled(base, by: multipliers)
            CGSetDisplayTransferByTable(id, UInt32(t.r.count), t.r, t.g, t.b)
        }
    }

    private func scaled(_ base: Table, by m: RGB) -> Table {
        Table(r: base.r.map { $0 * CGGammaValue(m.r) }, g: base.g.map { $0 * CGGammaValue(m.g) }, b: base.b.map { $0 * CGGammaValue(m.b) })
    }

    private func onlineDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }
}
