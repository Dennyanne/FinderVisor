import Foundation
import Testing
@testable import VisorCore

private let kF: UInt16 = 3

@Suite struct KeyComboTests {
    @Test func exactMatchFires() {
        var matcher = ComboMatcher(combo: .defaultCombo)
        #expect(matcher.process(.keyDown(keyCode: kF, modifiers: .option, isRepeat: false, timestamp: 0)) == .fire)
    }

    @Test func extraShiftDoesNotMatch() {
        var matcher = ComboMatcher(combo: .defaultCombo)
        let result = matcher.process(.keyDown(keyCode: kF, modifiers: [.option, .shift], isRepeat: false, timestamp: 0))
        #expect(result == .passThrough)
    }

    @Test func missingModifierOrOtherKeyDoesNotMatch() {
        var matcher = ComboMatcher(combo: .defaultCombo)
        #expect(matcher.process(.keyDown(keyCode: kF, modifiers: [], isRepeat: false, timestamp: 0)) == .passThrough)
        #expect(matcher.process(.keyDown(keyCode: 0, modifiers: .option, isRepeat: false, timestamp: 0)) == .passThrough)
    }

    @Test func functionModifierIsIgnored() {
        var matcher = ComboMatcher(combo: .defaultCombo)
        let result = matcher.process(.keyDown(keyCode: kF, modifiers: [.option, .function], isRepeat: false, timestamp: 0))
        #expect(result == .fire)
    }

    @Test func autorepeatAndKeyUpAreSwallowedNotRefired() {
        var matcher = ComboMatcher(combo: .defaultCombo)
        #expect(matcher.process(.keyDown(keyCode: kF, modifiers: .option, isRepeat: false, timestamp: 0)) == .fire)
        #expect(matcher.process(.keyDown(keyCode: kF, modifiers: .option, isRepeat: true, timestamp: 0.5)) == .swallow)
        #expect(matcher.process(.keyDown(keyCode: kF, modifiers: .option, isRepeat: true, timestamp: 0.6)) == .swallow)
        #expect(matcher.process(.keyUp(keyCode: kF, modifiers: .option, timestamp: 0.7)) == .swallow)
        // After the keyUp, unrelated keyUps pass through again.
        #expect(matcher.process(.keyUp(keyCode: kF, modifiers: [], timestamp: 0.8)) == .passThrough)
    }

    @Test func autorepeatOfUnswallowedKeyPassesThrough() {
        var matcher = ComboMatcher(combo: .defaultCombo)
        // F held without a modifier, then Option pressed: the repeats now carry Option.
        #expect(matcher.process(.keyDown(keyCode: kF, modifiers: [], isRepeat: false, timestamp: 0)) == .passThrough)
        #expect(matcher.process(.keyDown(keyCode: kF, modifiers: .option, isRepeat: true, timestamp: 0.5)) == .passThrough)
        #expect(matcher.process(.keyUp(keyCode: kF, modifiers: .option, timestamp: 0.6)) == .passThrough)
        // A fresh press still fires.
        #expect(matcher.process(.keyDown(keyCode: kF, modifiers: .option, isRepeat: false, timestamp: 1)) == .fire)
    }

    @Test func clearedComboNeverMatches() {
        var matcher = ComboMatcher(combo: nil)
        #expect(matcher.process(.keyDown(keyCode: kF, modifiers: .option, isRepeat: false, timestamp: 0)) == .passThrough)
    }

    @Test func flagsChangedPassThrough() {
        var matcher = ComboMatcher(combo: .defaultCombo)
        #expect(matcher.process(.flagsChanged(modifiers: .option, keyCode: 58, timestamp: 0)) == .passThrough)
    }

    @Test func codableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 3, modifiers: [.command, .shift])
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"keyCode\":3"))
    }

    @Test func comboDropsNonComboModifiers() {
        #expect(KeyCombo(keyCode: kF, modifiers: [.option, .function]).modifiers == .option)
    }
}
