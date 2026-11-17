import CoreGraphics

/// One display, in Cocoa coordinates (origin bottom-left of the primary screen, y up).
public struct ScreenGeometry: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// Computes the Visor frame: full visible width, docked to the bottom of the visible frame of the screen under the
/// mouse, height = percentage of the visible height. Output is in AX/global coordinates (origin top-left of the
/// primary screen, y down).
public enum VisorFrameCalculator {
    /// The screen containing `mouse` (edges inclusive), or the screen whose frame is nearest to it.
    public static func screen(for mouse: CGPoint, in screens: [ScreenGeometry]) -> ScreenGeometry? {
        screens.min { $0.frame.distance(to: mouse) < $1.frame.distance(to: mouse) }
    }

    /// - Parameters:
    ///   - screens: all screens in Cocoa coordinates.
    ///   - primaryScreenHeight: height (= maxY) of the primary screen's frame, used for Cocoa→AX conversion.
    ///   - mouse: mouse location in Cocoa coordinates.
    ///   - heightPercent: Visor height as a percentage of the visible frame height; validated via `VisorSettings`.
    public static func visorFrame(
        screens: [ScreenGeometry],
        primaryScreenHeight: CGFloat,
        mouse: CGPoint,
        heightPercent: Int
    ) -> CGRect? {
        guard let screen = screen(for: mouse, in: screens) else { return nil }
        let vf = screen.visibleFrame
        let pct = CGFloat(VisorSettings.validatedHeightPercent(heightPercent))
        let height = (vf.height * pct / 100).rounded()
        let top = primaryScreenHeight - vf.minY - height
        return CGRect(x: vf.minX, y: top, width: vf.width, height: height)
    }
}
