import CoreGraphics
import Foundation
import Testing
@testable import VisorCore

private let visorFrame = CGRect(x: 0, y: 508, width: 1440, height: 322)
private let docs = URL(fileURLWithPath: "/Users/test/Documents")
private let downloads = URL(fileURLWithPath: "/Users/test/Downloads")
private let stored = StoredVisorRecord(visorFrame: visorFrame, lastTargetURL: docs, finderPID: 42, memberIDs: [7, 9])

private func candidate(_ id: Int, _ frame: CGRect, _ target: URL? = nil) -> FinderWindowCandidate {
    FinderWindowCandidate(aeID: id, frame: frame, targetURL: target)
}

private let unrelated = CGRect(x: 100, y: 100, width: 800, height: 500)

@Suite struct ReattachMatcherTests {
    @Test func zeroCandidates() {
        #expect(ReattachMatcher.match(candidates: [], stored: stored) == nil)
        #expect(ReattachMatcher.match(candidates: [candidate(1, unrelated, docs)], stored: stored) == nil)
    }

    @Test func oneCandidateAtVisorFrame() {
        let result = ReattachMatcher.match(
            candidates: [candidate(1, unrelated), candidate(2, visorFrame.offsetBy(dx: 3, dy: -3))], stored: stored)
        #expect(result == [2])
    }

    @Test func sizeMismatchRejects() {
        let wrongSize = CGRect(origin: visorFrame.origin, size: CGSize(width: 1440, height: 330))
        #expect(ReattachMatcher.match(candidates: [candidate(1, wrongSize, docs)], stored: stored) == nil)
    }

    @Test func positionMismatchRejects() {
        let elsewhere = CGRect(origin: CGPoint(x: 0, y: 100), size: visorFrame.size)
        #expect(ReattachMatcher.match(candidates: [candidate(1, elsewhere, docs)], stored: stored) == nil)
    }

    @Test func singleMatchAdoptedEvenWhenTargetDiffers() {
        #expect(ReattachMatcher.match(candidates: [candidate(1, visorFrame, downloads)], stored: stored) == [1])
    }

    @Test func tabsOfOneWindowAdoptedTogether() {
        let result = ReattachMatcher.match(
            candidates: [candidate(5, visorFrame, downloads), candidate(3, visorFrame, nil), candidate(1, unrelated)],
            stored: stored)
        #expect(result == [3, 5])
    }

    @Test func twoGroupsResolvedByTarget() {
        let result = ReattachMatcher.match(
            candidates: [
                candidate(1, visorFrame, downloads),
                candidate(2, visorFrame.offsetBy(dx: 4, dy: 0), downloads),
                candidate(3, visorFrame.offsetBy(dx: 4, dy: 0), docs),
            ],
            stored: stored)
        #expect(result == [2, 3])
    }

    @Test func twoGroupsWithSameTargetAdoptNone() {
        let result = ReattachMatcher.match(
            candidates: [candidate(1, visorFrame, docs), candidate(2, visorFrame.offsetBy(dx: 4, dy: 0), docs)],
            stored: stored)
        #expect(result == nil)
    }

    @Test func twoGroupsWithoutTargetAdoptNone() {
        let candidates = [candidate(1, visorFrame), candidate(2, visorFrame.offsetBy(dx: 0, dy: 4))]
        #expect(ReattachMatcher.match(candidates: candidates, stored: stored) == nil)
        var noStoredTarget = stored
        noStoredTarget.lastTargetURL = nil
        let withTargets = [candidate(1, visorFrame, docs), candidate(2, visorFrame.offsetBy(dx: 0, dy: 4), docs)]
        #expect(ReattachMatcher.match(candidates: withTargets, stored: noStoredTarget) == nil)
    }

    @Test func targetComparisonIgnoresTrailingSlash() {
        let slashed = URL(fileURLWithPath: "/Users/test/Documents/", isDirectory: true)
        let result = ReattachMatcher.match(
            candidates: [candidate(1, visorFrame, downloads), candidate(2, visorFrame.offsetBy(dx: 4, dy: 4), slashed)],
            stored: stored)
        #expect(result == [2])
    }

    @Test func storedRecordCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(stored)
        #expect(try JSONDecoder().decode(StoredVisorRecord.self, from: data) == stored)
    }
}
