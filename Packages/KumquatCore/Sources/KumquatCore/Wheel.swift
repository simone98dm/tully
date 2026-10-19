import AppKit

/// Radial menu hit testing. Segment 0 is centered at 12 o'clock; indices increase clockwise.
public struct WheelGeometry: Sendable {
    public let count: Int
    public let innerRadius: CGFloat
    public let outerRadius: CGFloat

    public init(count: Int, innerRadius: CGFloat, outerRadius: CGFloat) {
        self.count = count; self.innerRadius = innerRadius; self.outerRadius = outerRadius
    }

    public var sweep: CGFloat { count > 0 ? 2 * .pi / CGFloat(count) : 0 }

    /// `offset` from the wheel center in a y-up coordinate space. nil = hub (cancel) or outside.
    public func segment(at offset: CGPoint) -> Int? {
        let distance = hypot(offset.x, offset.y)
        guard count > 0, distance >= innerRadius, distance <= outerRadius * 1.6 else { return nil }
        // Angle measured clockwise from 12 o'clock.
        var angle = atan2(offset.x, offset.y)
        if angle < 0 { angle += 2 * .pi }
        return Int((angle + sweep / 2) / sweep) % count
    }

    /// Angle in standard math orientation (radians, counter-clockwise from 3 o'clock) of a segment's center.
    public func centerAngle(of index: Int) -> CGFloat { .pi / 2 - CGFloat(index) * sweep }

    /// Keyboard navigation: arrow keys move around the ring.
    public func step(from index: Int?, by delta: Int) -> Int {
        guard count > 0 else { return 0 }
        guard let index else { return delta >= 0 ? 0 : count - 1 }
        return ((index + delta) % count + count) % count
    }
}

public enum WheelKind: String, CaseIterable, Codable, Sendable {
    case convert, tools, actions
    public var title: String { self == .convert ? "Convert" : self == .tools ? "Tools" : "Actions" }
}

/// Decides which wheel (if any) a modifier state opens. Pure so it can be tested.
public struct ModifierBinding: Codable, Equatable, Sendable {
    public var convert: UInt
    public var tools: UInt
    public var actions: UInt

    public static let `default` = ModifierBinding(convert: NSEvent.ModifierFlags.shift.rawValue,
                                                  tools: NSEvent.ModifierFlags.command.rawValue,
                                                  actions: NSEvent.ModifierFlags.control.rawValue)
    public static let choices: [(String, NSEvent.ModifierFlags)] = [("⇧ Shift", .shift), ("⌘ Command", .command),
                                                                    ("⌃ Control", .control), ("⌥ Option", .option)]

    /// The most specific match wins (e.g. Option+Shift beats Shift).
    public func kind(for flags: NSEvent.ModifierFlags) -> WheelKind? {
        let pressed = flags.intersection([.shift, .command, .control, .option]).rawValue
        guard pressed != 0 else { return nil }
        let bindings: [(WheelKind, UInt)] = [(.convert, convert), (.tools, tools), (.actions, actions)]
        return bindings.filter { $0.1 != 0 && pressed & $0.1 == $0.1 }
            .max { $0.1.nonzeroBitCount < $1.1.nonzeroBitCount }?.0
    }
}

/// Mid-drag state machine: a file drag starts, a modifier is tapped, the wheel opens and stays until mouse-up.
public struct DragSession: Sendable {
    public private(set) var isDraggingFiles = false
    public private(set) var visibleWheel: WheelKind?
    private var pasteboardBaseline = 0
    private var dismissed = false

    public init() {}

    public mutating func mouseDown(pasteboardChangeCount: Int) {
        pasteboardBaseline = pasteboardChangeCount
        isDraggingFiles = false
        visibleWheel = nil
        dismissed = false
    }

    /// Call on drag/poll ticks. Returns the wheel to show if it changed.
    public mutating func update(pasteboardChangeCount: Int, hasFiles: Bool, flags: NSEvent.ModifierFlags,
                                binding: ModifierBinding) -> WheelKind? {
        if pasteboardChangeCount != pasteboardBaseline && hasFiles { isDraggingFiles = true }
        guard isDraggingFiles, !dismissed, let kind = binding.kind(for: flags), kind != visibleWheel else { return nil }
        visibleWheel = kind
        return kind
    }

    /// Wheel used or cancelled (Escape/Return) mid-drag: stay closed until the next drag.
    public mutating func dismiss() {
        visibleWheel = nil
        dismissed = true
    }

    public mutating func mouseUp() {
        isDraggingFiles = false
        visibleWheel = nil
    }
}

/// Turns polled "keys currently down" into presses, so a held key counts once. Polling needs no Accessibility access.
public struct KeyPresses: Sendable {
    private var down: Set<UInt16> = []

    public init() {}

    public mutating func update(down now: Set<UInt16>) -> Set<UInt16> {
        defer { down = now }
        return now.subtracting(down)
    }
}
