import CoreGraphics
import Foundation

/// A Finder window considered for re-attach. `aeID` is Finder's AE window id (== CGWindowID); each Finder tab is a
/// separate window. `frame` is in global top-left coordinates; `targetURL` is the window's AE `target` as a file URL,
/// if it could be read. Minimized windows report their restored frame.
public struct FinderWindowCandidate: Equatable, Sendable {
    public var aeID: Int
    public var frame: CGRect
    public var targetURL: URL?

    public init(aeID: Int, frame: CGRect, targetURL: URL?) {
        self.aeID = aeID
        self.frame = frame
        self.targetURL = targetURL
    }
}

/// Persisted facts about the last known Visor, used after a Finder or FinderVisor relaunch.
public struct StoredVisorRecord: Codable, Equatable, Sendable {
    /// Last frame the Visor had while shown (global top-left coordinates).
    public var visorFrame: CGRect
    public var lastTargetURL: URL?
    /// Finder pid the member ids belong to; ids are invalid in any other Finder process.
    public var finderPID: Int32?
    /// AE ids (== CGWindowIDs) of the Visor's tab windows in `finderPID`.
    public var memberIDs: [UInt32]

    public init(visorFrame: CGRect, lastTargetURL: URL? = nil, finderPID: Int32? = nil, memberIDs: [UInt32] = []) {
        self.visorFrame = visorFrame
        self.lastTargetURL = lastTargetURL
        self.finderPID = finderPID
        self.memberIDs = memberIDs
    }
}

func sameTarget(_ a: URL?, _ b: URL?) -> Bool {
    guard let a, let b else { return false }
    return a.standardizedFileURL.path == b.standardizedFileURL.path
}

/// Re-attach rule (plan D2 as revised by the P3 spike decision). A candidate matches when its size equals the stored
/// Visor size ±4 pt and its frame is at the stored Visor frame ±4 pt (minimized or on-screen alike). Matches are
/// grouped into tab groups (windows sharing one frame ±2 pt). Exactly one group → adopt all its windows. Several
/// groups → the target tie-breaker keeps the groups containing a window whose target equals `lastTargetURL`; a
/// unique survivor is adopted. Otherwise (zero or still ambiguous) adopt none, so the next trigger creates a new Visor.
public enum ReattachMatcher {
    public static let tolerance: CGFloat = 4
    public static let tabGroupTolerance: CGFloat = 2

    /// AE ids of the adopted tab group (sorted), or `nil` to adopt none.
    public static func match(candidates: [FinderWindowCandidate], stored: StoredVisorRecord) -> [Int]? {
        let matches = candidates.filter { $0.frame.isApproximately(stored.visorFrame, tolerance: tolerance) }
        var groups: [[FinderWindowCandidate]] = []
        for candidate in matches {
            if let index = groups.firstIndex(where: {
                $0[0].frame.isApproximately(candidate.frame, tolerance: tabGroupTolerance)
            }) {
                groups[index].append(candidate)
            } else {
                groups.append([candidate])
            }
        }
        if groups.count > 1 {
            groups = groups.filter { group in group.contains { sameTarget($0.targetURL, stored.lastTargetURL) } }
        }
        guard groups.count == 1 else { return nil }
        return groups[0].map(\.aeID).sorted()
    }
}
