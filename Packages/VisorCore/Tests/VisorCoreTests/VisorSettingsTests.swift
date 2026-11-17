import Foundation
import Testing
@testable import VisorCore

@Suite struct VisorSettingsTests {
    @Test func defaults() {
        let settings = VisorSettings.default
        #expect(settings.doubleTapModifier == .option)
        #expect(settings.combo == KeyCombo(keyCode: 3, modifiers: .option))
        #expect(settings.heightPercent == 50)
    }

    @Test func allowedHeights() {
        #expect(VisorSettings.allowedHeightPercents.first == 20)
        #expect(VisorSettings.allowedHeightPercents.last == 90)
        #expect(VisorSettings.allowedHeightPercents.count == 15)
    }

    @Test(arguments: [(10, 20), (20, 20), (22, 20), (23, 25), (40, 40), (88, 90), (90, 90), (200, 90), (-5, 20)])
    func heightValidation(input: Int, expected: Int) {
        #expect(VisorSettings.validatedHeightPercent(input) == expected)
        #expect(VisorSettings(heightPercent: input).heightPercent == expected)
    }

    @Test func setterValidates() {
        var settings = VisorSettings()
        settings.heightPercent = 97
        #expect(settings.heightPercent == 90)
    }

    @Test func offValuesSurviveRoundTrip() throws {
        let settings = VisorSettings(doubleTapModifier: nil, combo: nil, heightPercent: 55)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(VisorSettings.self, from: data) == settings)
    }

    @Test func missingKeysDecodeToDefaults() throws {
        let decoded = try JSONDecoder().decode(VisorSettings.self, from: Data("{}".utf8))
        #expect(decoded == VisorSettings.default)
    }

    @Test func outOfRangeStoredHeightIsValidated() throws {
        let decoded = try JSONDecoder().decode(VisorSettings.self, from: Data(#"{"heightPercent": 13}"#.utf8))
        #expect(decoded.heightPercent == 20)
    }
}
