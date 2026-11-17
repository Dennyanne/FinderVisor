import CoreGraphics
import Testing
@testable import VisorCore

private let visorID: UInt32 = 100
private let ownPID: Int32 = 500
private let finderPID: Int32 = 300
private let otherPID: Int32 = 400
private let visor = CGRect(x: 0, y: 500, width: 1440, height: 400)

private func window(
    _ bounds: CGRect, id: UInt32 = 1, pid: Int32 = otherPID, layer: Int = 0, alpha: Double = 1
) -> WindowInfo {
    WindowInfo(windowID: id, ownerPID: pid, layer: layer, alpha: alpha, bounds: bounds)
}

private func covered(_ above: [WindowInfo]) -> Bool {
    CoverageCalculator.isFullyCovered(visorRect: visor, windowsAbove: above, visorWindowID: visorID, ownPID: ownPID)
}

@Suite struct CoverageCalculatorTests {
    @Test func uncovered() {
        #expect(covered([]) == false)
        #expect(covered([window(CGRect(x: 0, y: 0, width: 1440, height: 400))]) == false)
    }

    @Test func partiallyCovered() {
        #expect(covered([window(CGRect(x: 0, y: 500, width: 700, height: 400))]) == false)
    }

    @Test func fullyCoveredByOneWindow() {
        #expect(covered([window(CGRect(x: -10, y: 450, width: 1500, height: 500))]) == true)
    }

    @Test func fullyCoveredByUnionOfTwo() {
        #expect(covered([
            window(CGRect(x: 0, y: 500, width: 800, height: 400), id: 1),
            window(CGRect(x: 700, y: 480, width: 800, height: 450), id: 2, pid: 401),
        ]) == true)
    }

    @Test func otherFinderWindowCounts() {
        #expect(covered([window(visor, id: 7, pid: finderPID)]) == true)
    }

    @Test func onePointSliverCountsAsCovered() {
        #expect(covered([window(CGRect(x: 1, y: 500, width: 1439, height: 400))]) == true)
        #expect(covered([window(CGRect(x: 0, y: 501, width: 1440, height: 399))]) == true)
    }

    @Test func threePointStripIsNotCovered() {
        #expect(covered([window(CGRect(x: 3, y: 500, width: 1437, height: 400))]) == false)
    }

    @Test func layer25Ignored() {
        #expect(covered([window(visor, layer: 25)]) == false)
    }

    @Test func alphaZeroIgnored() {
        #expect(covered([window(visor, alpha: 0)]) == false)
    }

    @Test func visorOwnIDIgnored() {
        #expect(covered([window(visor, id: visorID, pid: finderPID)]) == false)
    }

    @Test func ownPIDIgnored() {
        #expect(covered([window(visor, id: 9, pid: ownPID)]) == false)
    }

    @Test func degenerateWindowsIgnored() {
        let rects = CoverageCalculator.coveringRects(
            windowsAbove: [window(CGRect(x: 0, y: 0, width: 1, height: 2000))], visorWindowID: visorID, ownPID: ownPID)
        #expect(rects.isEmpty)
    }

    @Test func subtractProducesDisjointPieces() {
        let pieces = CoverageCalculator.subtract(CGRect(x: 10, y: 10, width: 10, height: 10),
                                                 from: CGRect(x: 0, y: 0, width: 30, height: 30))
        #expect(pieces.count == 4)
        let area: CGFloat = pieces.reduce(0) { $0 + $1.width * $1.height }
        #expect(area == 800)
        for (i, a) in pieces.enumerated() {
            for b in pieces[(i + 1)...] {
                let overlap = a.intersection(b)
                #expect(overlap.isNull || overlap.width * overlap.height == 0)
            }
        }
    }

    @Test func subtractNonOverlappingReturnsOriginal() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(CoverageCalculator.subtract(CGRect(x: 10, y: 0, width: 5, height: 5), from: rect) == [rect])
    }
}
