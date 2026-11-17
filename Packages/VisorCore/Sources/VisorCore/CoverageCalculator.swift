import CoreGraphics

/// One CGWindowList entry (bounds in global top-left coordinates). Only public, non-Screen-Recording keys.
public struct WindowInfo: Equatable, Sendable {
    public var windowID: UInt32
    public var ownerPID: Int32
    public var layer: Int
    public var alpha: Double
    public var bounds: CGRect

    public init(windowID: UInt32, ownerPID: Int32, layer: Int, alpha: Double, bounds: CGRect) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
    }
}

/// Decides whether the Visor is fully covered by the windows above it (rule 3 of the toggle semantics).
///
/// A window counts as covering if its layer is in `0..<20` (below the Dock), alpha > 0, width and height > 1, it is
/// not the Visor itself and not owned by FinderVisor. Other Finder windows count. Windows are treated as opaque
/// rectangles. Uncovered remnants no larger than `sliverTolerance` in width or height are ignored.
public enum CoverageCalculator {
    public static let coveringLayers = 0..<20
    public static let sliverTolerance: CGFloat = 2

    public static func coveringRects(windowsAbove: [WindowInfo], visorWindowID: UInt32, ownPID: Int32) -> [CGRect] {
        windowsAbove.filter { window in
            coveringLayers.contains(window.layer)
                && window.alpha > 0
                && window.bounds.width > 1 && window.bounds.height > 1
                && window.windowID != visorWindowID
                && window.ownerPID != ownPID
        }.map(\.bounds)
    }

    /// Parts of `visor` not covered by any of `covers`.
    public static func uncoveredRegions(of visor: CGRect, covers: [CGRect]) -> [CGRect] {
        covers.reduce([visor]) { remaining, cover in
            remaining.flatMap { subtract(cover, from: $0) }
        }
    }

    public static func isFullyCovered(
        visorRect: CGRect,
        windowsAbove: [WindowInfo],
        visorWindowID: UInt32,
        ownPID: Int32
    ) -> Bool {
        let covers = coveringRects(windowsAbove: windowsAbove, visorWindowID: visorWindowID, ownPID: ownPID)
        return !uncoveredRegions(of: visorRect, covers: covers).contains {
            $0.width > sliverTolerance && $0.height > sliverTolerance
        }
    }

    /// `rect` minus `cover`, as at most 4 non-overlapping rects.
    public static func subtract(_ cover: CGRect, from rect: CGRect) -> [CGRect] {
        let overlap = rect.intersection(cover)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return [rect] }
        var pieces: [CGRect] = []
        // Full-width bands above and below the overlap.
        if overlap.minY > rect.minY {
            pieces.append(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY))
        }
        if overlap.maxY < rect.maxY {
            pieces.append(CGRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY))
        }
        // Left and right pieces beside the overlap.
        if overlap.minX > rect.minX {
            pieces.append(CGRect(x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX, height: overlap.height))
        }
        if overlap.maxX < rect.maxX {
            pieces.append(CGRect(x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX, height: overlap.height))
        }
        return pieces
    }
}
