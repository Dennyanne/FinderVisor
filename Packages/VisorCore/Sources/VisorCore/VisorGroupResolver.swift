import CoreGraphics

/// One Finder layer-0 window from the CGWindowList (all Spaces). `id` is the CGWindowID (== Finder AE window id).
public struct ListedWindow: Equatable, Sendable {
    public var id: UInt32
    public var bounds: CGRect
    public var isOnscreen: Bool

    public init(id: UInt32, bounds: CGRect, isOnscreen: Bool) {
        self.id = id
        self.bounds = bounds
        self.isOnscreen = isOnscreen
    }
}

/// The Visor's tab group as re-derived from the live window list.
public struct VisorGroupResolution: Equatable, Sendable {
    /// All windows (tabs) currently considered part of the Visor.
    public var memberIDs: Set<UInt32>
    /// The member whose frame defines the Visor frame.
    public var anchorID: UInt32
    /// The on-screen member (the selected tab), or `nil` when no member is on screen (minimized, app hidden, other
    /// Space).
    public var activeID: UInt32?
    public var frame: CGRect
}

/// Tracks the Visor's identity across Finder tabs. Each tab is a separate window with its own id; only the selected
/// tab is on screen and all tabs share one frame. Re-derived on every trigger from the known member ids:
///
/// 1. Live members = known ids still present. None → the Visor was closed (`nil`).
/// 2. Anchor = on-screen member at `lastFrame`, else the only on-screen member, else a member at `lastFrame`, else the
///    lowest id.
/// 3. New tabs: a window at the anchor frame ±2 pt joins the group only when all hold: `allowExpansion` (the group
///    is not minimized and Finder not hidden); it is on screen (a new tab is selected when created); its id is newer
///    than every known member (window ids increase, so older windows were never Visor tabs); and at most one window
///    at that frame is on screen (two on-screen windows at one frame cannot be tabs of one group → ambiguous).
///    Minimized or other-Space windows therefore never join.
/// 4. On-screen members away from the anchor frame (a tab dragged out into its own window) leave the group;
///    off-screen members are kept (inactive tabs).
public enum VisorGroupResolver {
    public static let frameTolerance: CGFloat = 2

    public static func resolve(
        memberIDs: Set<UInt32>,
        finderWindows: [ListedWindow],
        lastFrame: CGRect?,
        allowExpansion: Bool
    ) -> VisorGroupResolution? {
        let live = finderWindows.filter { memberIDs.contains($0.id) }
        guard let lowest = live.min(by: { $0.id < $1.id }) else { return nil }
        let onscreen = live.filter(\.isOnscreen)
        func atLastFrame(_ window: ListedWindow) -> Bool {
            lastFrame.map { window.bounds.isApproximately($0, tolerance: frameTolerance) } ?? false
        }
        let anchor = onscreen.first(where: atLastFrame)
            ?? (onscreen.count == 1 ? onscreen[0] : nil)
            ?? live.first(where: atLastFrame)
            ?? lowest
        let frame = anchor.bounds
        let sameFrame = finderWindows.filter { $0.bounds.isApproximately(frame, tolerance: frameTolerance) }
        let canExpand = allowExpansion && sameFrame.filter(\.isOnscreen).count <= 1
        let newestKnown = memberIDs.max() ?? 0
        var members = Set(sameFrame.filter { window in
            memberIDs.contains(window.id) || (canExpand && window.isOnscreen && window.id > newestKnown)
        }.map(\.id))
        members.formUnion(live.filter { !$0.isOnscreen }.map(\.id))
        let active = sameFrame.first { $0.isOnscreen && members.contains($0.id) }
        return VisorGroupResolution(memberIDs: members, anchorID: anchor.id, activeID: active?.id, frame: frame)
    }
}
