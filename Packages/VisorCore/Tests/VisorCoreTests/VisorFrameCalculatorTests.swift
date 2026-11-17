import CoreGraphics
import Testing
@testable import VisorCore

/// 1440x900 primary screen, menu bar 25 pt.
private let primaryBottomDock = ScreenGeometry(
    frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
    visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805)
)
private let primaryLeftDock = ScreenGeometry(
    frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
    visibleFrame: CGRect(x: 80, y: 0, width: 1360, height: 875)
)
private let secondaryLeft = ScreenGeometry(
    frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055)
)
private let secondaryAbove = ScreenGeometry(
    frame: CGRect(x: 0, y: 900, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 0, y: 900, width: 1920, height: 1055)
)

@Suite struct VisorFrameCalculatorTests {
    @Test func singleScreenBottomDock40() {
        let frame = VisorFrameCalculator.visorFrame(
            screens: [primaryBottomDock], primaryScreenHeight: 900, mouse: CGPoint(x: 500, y: 500), heightPercent: 40)
        // h = round(805 * 0.4) = 322; y = 900 - 70 - 322 = 508
        #expect(frame == CGRect(x: 0, y: 508, width: 1440, height: 322))
    }

    @Test func singleScreenBottomDock90() {
        let frame = VisorFrameCalculator.visorFrame(
            screens: [primaryBottomDock], primaryScreenHeight: 900, mouse: CGPoint(x: 500, y: 500), heightPercent: 90)
        // h = round(805 * 0.9) = 725 (724.5 rounds away from zero); y = 900 - 70 - 725 = 105
        #expect(frame == CGRect(x: 0, y: 105, width: 1440, height: 725))
    }

    @Test func singleScreenLeftDock() {
        let frame = VisorFrameCalculator.visorFrame(
            screens: [primaryLeftDock], primaryScreenHeight: 900, mouse: CGPoint(x: 500, y: 500), heightPercent: 40)
        // h = round(875 * 0.4) = 350; y = 900 - 0 - 350 = 550
        #expect(frame == CGRect(x: 80, y: 550, width: 1360, height: 350))
    }

    @Test func secondaryLeftOfPrimaryHasNegativeX() {
        let frame = VisorFrameCalculator.visorFrame(
            screens: [primaryBottomDock, secondaryLeft], primaryScreenHeight: 900,
            mouse: CGPoint(x: -100, y: 300), heightPercent: 40)
        // h = 422; y = 900 - 0 - 422 = 478
        #expect(frame == CGRect(x: -1920, y: 478, width: 1920, height: 422))
    }

    @Test func secondaryAbovePrimaryHasNegativeY() {
        let frame = VisorFrameCalculator.visorFrame(
            screens: [primaryBottomDock, secondaryAbove], primaryScreenHeight: 900,
            mouse: CGPoint(x: 100, y: 1500), heightPercent: 90)
        // h = round(1055 * 0.9) = 950 (949.5); y = 900 - 900 - 950 = -950
        #expect(frame == CGRect(x: 0, y: -950, width: 1920, height: 950))
    }

    @Test func mouseOutsideAllScreensUsesNearest() {
        let screen = VisorFrameCalculator.screen(
            for: CGPoint(x: -2500, y: 200), in: [primaryBottomDock, secondaryLeft])
        #expect(screen == secondaryLeft)
    }

    @Test func mouseOnTopEdgeBelongsToScreen() {
        let screen = VisorFrameCalculator.screen(for: CGPoint(x: 700, y: 900), in: [secondaryLeft, primaryBottomDock])
        #expect(screen == primaryBottomDock)
    }

    @Test func invalidHeightIsClamped() {
        let frame = VisorFrameCalculator.visorFrame(
            screens: [primaryBottomDock], primaryScreenHeight: 900, mouse: .zero, heightPercent: 150)
        #expect(frame?.height == 725)
    }

    @Test func noScreensGivesNil() {
        #expect(VisorFrameCalculator.visorFrame(screens: [], primaryScreenHeight: 900, mouse: .zero, heightPercent: 40) == nil)
    }
}
