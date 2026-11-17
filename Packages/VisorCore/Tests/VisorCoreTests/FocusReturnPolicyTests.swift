import Testing
@testable import VisorCore

private let ownPID: Int32 = 500
private let finderPID: Int32 = 300
private let policy = FocusReturnPolicy(ownPID: ownPID)

@Suite struct FocusReturnPolicyTests {
    @Test func ownPIDIgnored() {
        #expect(policy.returnTarget(for: ActivationEvent(pid: ownPID, bundleID: "io.github.findervisor.FinderVisor")) == nil)
    }

    @Test func finderWithVisorKeyIgnored() {
        let event = ActivationEvent(pid: finderPID, bundleID: "com.apple.finder", visorIsFinderKeyWindow: true)
        #expect(policy.returnTarget(for: event) == nil)
    }

    @Test func finderWithOtherWindowKeyAccepted() {
        let event = ActivationEvent(pid: finderPID, bundleID: "com.apple.finder", visorIsFinderKeyWindow: false)
        #expect(policy.returnTarget(for: event) == ReturnTarget(pid: finderPID, bundleID: "com.apple.finder"))
    }

    @Test func otherAppAccepted() {
        let event = ActivationEvent(pid: 777, bundleID: "com.apple.TextEdit")
        #expect(policy.returnTarget(for: event) == ReturnTarget(pid: 777, bundleID: "com.apple.TextEdit"))
    }
}
