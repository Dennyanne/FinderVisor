import ApplicationServices
import Foundation
import OSLog
import VisorCore

/// The Visor as resolved at trigger time.
struct ResolvedVisor {
    /// AX element of the Visor (the selected tab's window).
    let element: AXUIElement
    /// On-screen tab window (CGWindowID == AE id), or `nil` when minimized / Finder hidden / other Space.
    let activeID: UInt32?
    /// Tab window that defines the frame; used for AE reads when no tab is on screen.
    let anchorID: UInt32
    /// CGWindowList bounds of the tab group (global top-left coordinates).
    let frame: CGRect
    /// Every tab window (CGWindowID) of the Visor's tab group.
    let memberIDs: Set<UInt32>
}

enum VisorLocatorError: Error {
    case finderNotRunning
    case windowNotFound(aeID: Int)
}

/// Creates, identifies and re-attaches the Visor.
///
/// Identity is the set of Finder windows forming the Visor's tab group (each tab is its own AE window whose id equals
/// its CGWindowID; the selected tab changes the AX element and CGWindowID). On every trigger the group is re-derived
/// from CGWindowList via `VisorGroupResolver`, then the AX element is the Finder `AXWindows` entry at the group frame.
/// Ambiguity → the Visor is treated as missing and a new one is created; other windows are never touched.
@MainActor
final class VisorWindowLocator {
    private static let recordKey = "visorRecord"
    private static let frameTolerance: CGFloat = 2
    private let logger = Logger(subsystem: "io.github.findervisor.FinderVisor", category: "locator")

    private let scripting: FinderScripting
    private let ax: AXWindowService
    private let windowList: WindowListProvider
    private let activator: AppActivator
    private let defaults: UserDefaults

    private var finderPID: pid_t?
    private var memberIDs: Set<UInt32> = []
    private var element: AXUIElement?
    private var record: StoredVisorRecord?
    /// Set at launch and on Finder relaunch: the next resolve applies the Re-attach rule before giving up.
    private var needsReattach = true
    private var targetRefreshPending = false

    init(scripting: FinderScripting, ax: AXWindowService, windowList: WindowListProvider, activator: AppActivator,
         defaults: UserDefaults = .standard) {
        self.scripting = scripting
        self.ax = ax
        self.windowList = windowList
        self.activator = activator
        self.defaults = defaults
        record = defaults.data(forKey: Self.recordKey).flatMap { try? JSONDecoder().decode(StoredVisorRecord.self, from: $0) }
    }

    // MARK: - Resolution

    /// Re-derives the Visor from live state. `nil` → it does not exist (never created, closed, or not identifiable).
    func resolve() async -> ResolvedVisor? {
        guard let pid = activator.finderPID else {
            forget()
            return nil
        }
        if pid != finderPID {
            finderPID = pid
            forget()
            needsReattach = true
        }
        if memberIDs.isEmpty && needsReattach {
            await reattach(pid: pid)
        }
        guard !memberIDs.isEmpty else { return nil }
        let groupMinimized = element.map { ax.isMinimized($0) == true } ?? false
        guard let group = VisorGroupResolver.resolve(
            memberIDs: memberIDs,
            finderWindows: windowList.windows(ofPID: pid),
            lastFrame: record?.visorFrame,
            allowExpansion: !groupMinimized && !activator.isFinderHidden
        ) else {
            logger.info("Visor closed (no member window left)")
            forget()
            return nil
        }
        memberIDs = group.memberIDs
        guard let match = await axElement(pid: pid, group: group) else {
            logger.notice("Visor AX window ambiguous or missing; treating as closed")
            forget()
            return nil
        }
        element = match
        persist()
        return ResolvedVisor(element: match, activeID: group.activeID, anchorID: group.anchorID, frame: group.frame,
                             memberIDs: group.memberIDs)
    }

    /// Whether `window` is the Visor (used by focus return).
    func isVisor(_ window: AXUIElement) -> Bool {
        if let element, CFEqual(element, window) { return true }
        guard !memberIDs.isEmpty, let frame = record?.visorFrame, let live = ax.frame(of: window) else { return false }
        return Self.approximately(live, frame)
    }

    private func axElement(pid: pid_t, group: VisorGroupResolution) async -> AXUIElement? {
        let atFrame = windows(ofApp: pid, at: group.frame)
        if atFrame.count == 1 { return atFrame[0] }
        if let element, atFrame.contains(where: { CFEqual($0, element) }) { return element }
        if atFrame.count > 1,
           let name = try? await scripting.name(ofWindow: Int(group.activeID ?? group.anchorID)) {
            let byTitle = atFrame.filter { ax.title(of: $0) == name }
            if byTitle.count == 1 { return byTitle[0] }
        }
        if atFrame.isEmpty, let element, ax.isValid(element) { return element }
        return nil
    }

    /// Finder AX windows at `frame`. Reads each window's position first and its size only on a position match, to
    /// keep main-thread AX round trips per toggle low.
    private func windows(ofApp pid: pid_t, at frame: CGRect, among candidates: [AXUIElement]? = nil) -> [AXUIElement] {
        (candidates ?? ax.windows(ofApp: pid)).filter { window in
            guard let origin = ax.position(of: window),
                  abs(origin.x - frame.minX) <= Self.frameTolerance, abs(origin.y - frame.minY) <= Self.frameTolerance,
                  let live = ax.frame(of: window) else { return false }
            return Self.approximately(live, frame)
        }
    }

    // MARK: - Creation

    /// AE `make new Finder window to home` at `frame`, then correlates the new AX window (D2).
    func create(frame: CGRect) async throws -> ResolvedVisor {
        guard let pid = activator.finderPID else { throw VisorLocatorError.finderNotRunning }
        let before = ax.windows(ofApp: pid)
        let aeID = try await scripting.createWindow(frame: frame)
        // Adopt the new window before correlating, so a failed correlation never orphans it: the next trigger
        // re-resolves it from CGWindowList instead of creating yet another window.
        finderPID = pid
        memberIDs = [UInt32(aeID)]
        element = nil
        needsReattach = false
        record = StoredVisorRecord(visorFrame: frame, lastTargetURL: record?.lastTargetURL)
        persist()
        var found: AXUIElement?
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(1)
        while found == nil {
            let fresh = ax.windows(ofApp: pid).filter { window in !before.contains { CFEqual($0, window) } }
            found = windows(ofApp: pid, at: frame, among: fresh).first
            if found == nil, clock.now >= deadline {
                found = fresh.count == 1 ? fresh[0] : nil
                break
            }
            if found == nil { try? await Task.sleep(for: .milliseconds(50)) }
        }
        guard let found else { throw VisorLocatorError.windowNotFound(aeID: aeID) }
        element = found
        return ResolvedVisor(element: found, activeID: UInt32(aeID), anchorID: UInt32(aeID), frame: frame,
                             memberIDs: [UInt32(aeID)])
    }

    // MARK: - Persistence / refresh

    /// Records the frame the Visor was shown at (or had when hidden), for re-attach.
    func noteFrame(_ frame: CGRect) {
        if record == nil {
            record = StoredVisorRecord(visorFrame: frame)
        } else {
            record?.visorFrame = frame
        }
        persist()
    }

    /// Refreshes the stored target folder (re-attach tie-breaker). Skipped while a read is pending.
    func refreshTarget(of visor: ResolvedVisor) {
        refreshTarget(windowID: visor.activeID ?? visor.anchorID)
    }

    private func refreshTarget(windowID: UInt32) {
        guard !targetRefreshPending else { return }
        targetRefreshPending = true
        let id = Int(windowID)
        Task {
            defer { targetRefreshPending = false }
            guard let url = try? await scripting.targetURL(ofWindow: id), record != nil else { return }
            record?.lastTargetURL = url
            persist()
        }
    }

    /// Re-reads the target of the current Visor without a full resolve (5 s background refresh while shown).
    func refreshTargetIfShown() {
        guard let pid = finderPID, !memberIDs.isEmpty else { return }
        let onscreen = windowList.windows(ofPID: pid).first { memberIDs.contains($0.id) && $0.isOnscreen }
        guard let onscreen else { return }
        refreshTarget(windowID: onscreen.id)
    }

    private func persist() {
        guard var record else { return }
        record.finderPID = finderPID
        record.memberIDs = memberIDs.sorted()
        self.record = record
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: Self.recordKey) }
    }

    // MARK: - Finder lifecycle / re-attach

    func finderTerminated() {
        finderPID = nil
        forget()
        needsReattach = true
    }

    /// Finder restores its windows a moment after launch: retry the Re-attach rule a few times.
    func finderLaunched(pid: pid_t) {
        finderPID = pid
        forget()
        needsReattach = true
        Task {
            let delays = [1, 3, 6]
            for (index, delay) in delays.enumerated() {
                try? await Task.sleep(for: .seconds(delay))
                guard finderPID == pid, memberIDs.isEmpty, needsReattach else { return }
                await reattach(pid: pid, isFinalAttempt: index == delays.count - 1)
            }
        }
    }

    /// Re-attach rule. Same Finder process as recorded → stored ids are still valid. Otherwise match Finder's windows
    /// (minimized or on screen) against the stored Visor frame; the target folder breaks ties; 0 or ≥2 → none.
    /// `needsReattach` stays set after a miss (Finder may still be restoring windows) unless this is the final
    /// scheduled attempt; a trigger that finds nothing creates a new Visor, which clears it.
    private func reattach(pid: pid_t, isFinalAttempt: Bool = false) async {
        guard let record else {
            needsReattach = false
            return
        }
        if record.finderPID == pid, !record.memberIDs.isEmpty {
            memberIDs = Set(record.memberIDs)
            needsReattach = false
            return
        }
        do {
            let candidates = try await scripting.allWindows()
            guard let ids = ReattachMatcher.match(candidates: candidates, stored: record) else {
                if isFinalAttempt { needsReattach = false }
                logger.info("Re-attach: no unique former Visor among \(candidates.count) Finder windows")
                return
            }
            needsReattach = false
            memberIDs = Set(ids.map { UInt32($0) })
            persist()
            logger.info("Re-attach: adopted Finder windows \(ids)")
        } catch {
            if isFinalAttempt { needsReattach = false }
            logger.error("Re-attach failed: \(String(describing: error))")
        }
    }

    private func forget() {
        memberIDs = []
        element = nil
    }

    private static func approximately(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= frameTolerance && abs(a.minY - b.minY) <= frameTolerance
            && abs(a.width - b.width) <= frameTolerance && abs(a.height - b.height) <= frameTolerance
    }
}
