import Testing
@testable import VisorCore

private let leftOption: UInt16 = 58
private let rightOption: UInt16 = 61
private let leftShift: UInt16 = 56

/// Builds a timeline of events with injected timestamps and runs them through a detector.
private struct Script {
    var events: [KeyInput] = []

    mutating func flags(_ mods: ModifierSet, key: UInt16 = leftOption, at t: Double) {
        events.append(.flagsChanged(modifiers: mods, keyCode: key, timestamp: t))
    }

    mutating func tap(_ mods: ModifierSet = .option, key: UInt16 = leftOption, down: Double, up: Double) {
        flags(mods, key: key, at: down)
        flags([], key: key, at: up)
    }

    func fireCount(modifier: ModifierKey? = .option) -> Int {
        var detector = DoubleTapDetector(modifier: modifier)
        return events.filter { detector.process($0) }.count
    }
}

@Suite struct DoubleTapDetectorTests {
    @Test func gapOf020Fires() {
        var s = Script()
        s.tap(down: 0.00, up: 0.05)
        s.tap(down: 0.25, up: 0.30)
        #expect(s.fireCount() == 1)
    }

    @Test func gapOf035DoesNotFire() {
        var s = Script()
        s.tap(down: 0.00, up: 0.05)
        s.tap(down: 0.40, up: 0.45)
        #expect(s.fireCount() == 0)
    }

    @Test func holdOf040DoesNotFire() {
        var s = Script()
        s.tap(down: 0.00, up: 0.40)
        s.tap(down: 0.50, up: 0.55)
        #expect(s.fireCount() == 0)

        var secondHeld = Script()
        secondHeld.tap(down: 0.00, up: 0.05)
        secondHeld.tap(down: 0.15, up: 0.55)
        #expect(secondHeld.fireCount() == 0)
    }

    @Test func optionShiftOptionDoesNotFire() {
        var s = Script()
        s.tap(down: 0.00, up: 0.05)
        s.tap(.shift, key: leftShift, down: 0.10, up: 0.15)
        s.tap(down: 0.20, up: 0.25)
        #expect(s.fireCount() == 0)
    }

    @Test func otherModifierHeldDoesNotFire() {
        var s = Script()
        s.flags(.command, key: 55, at: 0.00)
        s.flags([.command, .option], at: 0.01)
        s.flags(.command, at: 0.05)
        s.flags([.command, .option], at: 0.10)
        s.flags(.command, at: 0.15)
        #expect(s.fireCount() == 0)
    }

    @Test func keyDownBetweenTapsDoesNotFire() {
        var s = Script()
        s.tap(down: 0.00, up: 0.05)
        s.events.append(.keyDown(keyCode: 0, modifiers: [], isRepeat: false, timestamp: 0.08))
        s.events.append(.keyUp(keyCode: 0, modifiers: [], timestamp: 0.09))
        s.tap(down: 0.12, up: 0.17)
        #expect(s.fireCount() == 0)
    }

    @Test func keyDownWhileOptionHeldDoesNotFire() {
        var s = Script()
        s.flags(.option, at: 0.00)
        s.events.append(.keyDown(keyCode: 0, modifiers: .option, isRepeat: false, timestamp: 0.02))
        s.flags([], at: 0.05)
        s.tap(down: 0.10, up: 0.15)
        #expect(s.fireCount() == 0)
    }

    @Test func leftThenRightFires() {
        var s = Script()
        s.tap(key: leftOption, down: 0.00, up: 0.05)
        s.tap(key: rightOption, down: 0.20, up: 0.25)
        #expect(s.fireCount() == 1)
    }

    @Test func offNeverFires() {
        var s = Script()
        s.tap(down: 0.00, up: 0.05)
        s.tap(down: 0.10, up: 0.15)
        #expect(s.fireCount(modifier: nil) == 0)
    }

    @Test func tripleTapFiresOnce() {
        var s = Script()
        s.tap(down: 0.00, up: 0.05)
        s.tap(down: 0.10, up: 0.15)
        s.tap(down: 0.20, up: 0.25)
        #expect(s.fireCount() == 1)
    }

    @Test func fourTapsFireTwice() {
        var s = Script()
        for i in 0..<4 {
            let t = Double(i) * 0.10
            s.tap(down: t, up: t + 0.05)
        }
        #expect(s.fireCount() == 2)
    }

    @Test func lateSecondTapStartsNewPair() {
        var s = Script()
        s.tap(down: 0.00, up: 0.05)
        s.tap(down: 0.50, up: 0.55)  // too late: becomes the first tap of a new pair
        s.tap(down: 0.70, up: 0.75)
        #expect(s.fireCount() == 1)
    }

    @Test func otherConfiguredModifierWorks() {
        var s = Script()
        s.tap(.control, key: 59, down: 0.00, up: 0.05)
        s.tap(.control, key: 59, down: 0.20, up: 0.25)
        #expect(s.fireCount(modifier: .control) == 1)
        #expect(s.fireCount(modifier: .option) == 0)
    }

    @Test func changingModifierResetsState() {
        var detector = DoubleTapDetector(modifier: .option)
        _ = detector.process(.flagsChanged(modifiers: .option, keyCode: leftOption, timestamp: 0.00))
        _ = detector.process(.flagsChanged(modifiers: [], keyCode: leftOption, timestamp: 0.05))
        detector.modifier = .control
        detector.modifier = .option
        _ = detector.process(.flagsChanged(modifiers: .option, keyCode: leftOption, timestamp: 0.10))
        #expect(detector.process(.flagsChanged(modifiers: [], keyCode: leftOption, timestamp: 0.15)) == false)
    }
}
