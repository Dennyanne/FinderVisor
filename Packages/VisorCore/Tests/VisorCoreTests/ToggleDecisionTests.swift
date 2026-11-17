import Testing
@testable import VisorCore

@Suite struct ToggleDecisionTests {
    @Test(arguments: [
        (VisorState(exists: false, visible: false, fullyCovered: false), ToggleAction.create),
        (VisorState(exists: true, visible: false, fullyCovered: false), ToggleAction.show),
        (VisorState(exists: true, visible: true, fullyCovered: false), ToggleAction.hide),
        (VisorState(exists: true, visible: true, fullyCovered: true), ToggleAction.bringToFront),
    ])
    func decides(state: VisorState, expected: ToggleAction) {
        #expect(ToggleDecision.decide(state) == expected)
    }
}
