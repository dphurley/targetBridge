import XCTest
@testable import TargetBridge

/// Tests for the two pure pieces behind auto-connect: the persisted per-receiver
/// opt-in (`TBAutoConnectTrustStore`) and the debounce/backoff policy that turns
/// a noisy Bonjour sighting stream into at most one dial per backoff window
/// (`TBAutoConnectGate`).
final class TBAutoConnectTrustStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "fd.tbdisplaysender.tests.autoconnect.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testUnknownReceiverIsNotTrusted() {
        let store = TBAutoConnectTrustStore(defaults: defaults)
        XCTAssertFalse(store.isTrusted(identity: "service:Studio"))
        XCTAssertTrue(store.load().isEmpty)
    }

    func testTrustSurvivesANewStoreOverTheSameDefaults() {
        TBAutoConnectTrustStore(defaults: defaults).setTrusted(true, identity: "service:Studio")
        // A fresh store stands in for a relaunch: nothing is cached in memory.
        XCTAssertTrue(TBAutoConnectTrustStore(defaults: defaults).isTrusted(identity: "service:Studio"))
    }

    func testTrustIsPerReceiver() {
        let store = TBAutoConnectTrustStore(defaults: defaults)
        store.setTrusted(true, identity: "service:Studio")
        XCTAssertTrue(store.isTrusted(identity: "service:Studio"))
        XCTAssertFalse(store.isTrusted(identity: "service:Mini"))
    }

    func testRevokingTrustRemovesOnlyThatReceiver() {
        let store = TBAutoConnectTrustStore(defaults: defaults)
        store.setTrusted(true, identity: "service:Studio")
        store.setTrusted(true, identity: "service:Mini")
        let remaining = store.setTrusted(false, identity: "service:Studio")
        XCTAssertEqual(remaining, ["service:Mini"])
        XCTAssertEqual(TBAutoConnectTrustStore(defaults: defaults).load(), ["service:Mini"])
    }

    func testTrustingTwiceDoesNotDuplicate() {
        let store = TBAutoConnectTrustStore(defaults: defaults)
        store.setTrusted(true, identity: "service:Studio")
        store.setTrusted(true, identity: "service:Studio")
        XCTAssertEqual(defaults.stringArray(forKey: TBAutoConnectTrustStore.defaultsKey), ["service:Studio"])
    }

    func testEmptyingTheSetClearsTheDefaultsKey() {
        let store = TBAutoConnectTrustStore(defaults: defaults)
        store.setTrusted(true, identity: "service:Studio")
        store.setTrusted(false, identity: "service:Studio")
        XCTAssertNil(defaults.object(forKey: TBAutoConnectTrustStore.defaultsKey))
    }

    /// The link-local IP in `TBDiscoveredReceiver.id` changes every time the
    /// bridge comes back up, so trust must be keyed on the Bonjour service name.
    func testStableIdentityIgnoresAddressChanges() {
        func receiver(ip: String) -> TBDiscoveredReceiver {
            TBDiscoveredReceiver(
                serviceName: "Studio._targetbridge._tcp.",
                receiverName: "Studio",
                preferredIP: ip,
                thunderboltIP: ip,
                networkIP: "",
                panelSummary: "",
                version: "3.5.0",
                supportsHEVCDecode: true,
                hostName: "studio.local."
            )
        }
        XCTAssertNotEqual(receiver(ip: "169.254.1.2").id, receiver(ip: "169.254.9.9").id)
        XCTAssertEqual(receiver(ip: "169.254.1.2").stableIdentity, receiver(ip: "169.254.9.9").stableIdentity)
    }
}

final class TBAutoConnectGateTests: XCTestCase {
    private let studio = "service:Studio"
    private let mini = "service:Mini"
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let policy = TBAutoConnectGate.Policy.default

    private func date(_ offset: TimeInterval) -> Date { start.addingTimeInterval(offset) }

    // MARK: - Debounce

    func testReceiverIsNotEligibleUntilItHasSettled() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        XCTAssertNil(gate.candidate(from: [studio], now: date(0)))
        XCTAssertNil(gate.candidate(from: [studio], now: date(policy.settleInterval - 0.1)))
        XCTAssertEqual(gate.candidate(from: [studio], now: date(policy.settleInterval)), studio)
    }

    func testRepeatedAnnouncementsDoNotRestartTheSettleWindow() {
        var gate = TBAutoConnectGate()
        // Bonjour re-announcing the same service every 100 ms must not keep
        // pushing the eligibility moment out.
        for tick in stride(from: 0.0, through: policy.settleInterval, by: 0.1) {
            gate.updateVisibility([studio], now: date(tick))
        }
        XCTAssertEqual(gate.candidate(from: [studio], now: date(policy.settleInterval)), studio)
    }

    func testOnlyOneAttemptRunsAtATime() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio, mini], now: date(0))
        let now = date(policy.settleInterval)
        XCTAssertEqual(gate.candidate(from: [studio, mini], now: now), studio)
        gate.beginAttempt(identity: studio, now: now)
        // No connect storm: nothing else is offered while a dial is in flight,
        // no matter how many sightings arrive.
        for tick in stride(from: 0.0, to: policy.attemptTimeout, by: 0.5) {
            gate.updateVisibility([studio, mini], now: now.addingTimeInterval(tick))
            XCTAssertNil(gate.candidate(from: [studio, mini], now: now.addingTimeInterval(tick)))
        }
    }

    func testBriefFlapDoesNotRestartTheSettleWindow() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        gate.updateVisibility([], now: date(1))          // dropped out
        XCTAssertNil(gate.candidate(from: [studio], now: date(1)))
        gate.updateVisibility([studio], now: date(1.5))  // back, well inside the grace
        XCTAssertEqual(gate.candidate(from: [studio], now: date(policy.settleInterval)), studio)
    }

    func testProlongedAbsenceForgetsTheReceiver() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        gate.updateVisibility([], now: date(1))
        XCTAssertTrue(gate.isTracking(identity: studio))
        gate.updateVisibility([], now: date(1 + policy.absenceGrace))
        XCTAssertFalse(gate.isTracking(identity: studio))
    }

    // MARK: - Backoff

    func testFailureBlocksRetriesForAnExponentiallyGrowingWindow() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        var now = date(policy.settleInterval)

        for failure in 1...3 {
            XCTAssertEqual(gate.candidate(from: [studio], now: now), studio, "failure \(failure)")
            gate.beginAttempt(identity: studio, now: now)
            now = now.addingTimeInterval(policy.attemptTimeout)
            XCTAssertNotNil(gate.timedOutAttempt(now: now))
            gate.noteFailure(now: now)
            XCTAssertEqual(gate.failureCount(identity: studio), failure)

            let backoff = gate.backoff(afterFailures: failure)
            XCTAssertEqual(backoff, policy.initialBackoff * pow(2, Double(failure - 1)))
            gate.updateVisibility([studio], now: now.addingTimeInterval(backoff - 0.1))
            XCTAssertNil(gate.candidate(from: [studio], now: now.addingTimeInterval(backoff - 0.1)))
            now = now.addingTimeInterval(backoff)
            gate.updateVisibility([studio], now: now)
        }
    }

    func testBackoffIsCapped() {
        let gate = TBAutoConnectGate()
        XCTAssertEqual(gate.backoff(afterFailures: 0), 0)
        XCTAssertEqual(gate.backoff(afterFailures: 1), policy.initialBackoff)
        XCTAssertEqual(gate.backoff(afterFailures: 40), policy.maximumBackoff)
    }

    func testAnAttemptIsNotConsideredTimedOutEarly() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        gate.beginAttempt(identity: studio, now: date(policy.settleInterval))
        XCTAssertNil(gate.timedOutAttempt(now: date(policy.settleInterval + policy.attemptTimeout - 0.1)))
        XCTAssertNotNil(gate.timedOutAttempt(now: date(policy.settleInterval + policy.attemptTimeout)))
    }

    func testSuccessClearsAccumulatedBackoff() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        gate.beginAttempt(identity: studio, now: date(2))
        gate.noteFailure(now: date(2 + policy.attemptTimeout))
        XCTAssertEqual(gate.failureCount(identity: studio), 1)

        let retryAt = date(2 + policy.attemptTimeout + policy.initialBackoff)
        gate.updateVisibility([studio], now: retryAt)
        gate.beginAttempt(identity: studio, now: retryAt)
        gate.noteSuccess()
        XCTAssertEqual(gate.failureCount(identity: studio), 0)
        XCTAssertNil(gate.attemptInFlight)
        XCTAssertEqual(gate.candidate(from: [studio], now: retryAt), studio)
    }

    func testBackoffSurvivesAFlapSoAFlappingLinkCannotStorm() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        gate.beginAttempt(identity: studio, now: date(2))
        gate.noteFailure(now: date(2 + policy.attemptTimeout))

        // Disappear and reappear inside both the grace and the backoff window:
        // the backoff must not be forgotten, or a flapping cable would dial on
        // every reappearance.
        let failedAt = date(2 + policy.attemptTimeout)
        var now = failedAt
        while now.timeIntervalSince(failedAt) < policy.initialBackoff - 2 {
            now = now.addingTimeInterval(1)
            gate.updateVisibility([], now: now)
            now = now.addingTimeInterval(1)
            gate.updateVisibility([studio], now: now)
            XCTAssertNil(gate.candidate(from: [studio], now: now))
        }
        XCTAssertEqual(gate.failureCount(identity: studio), 1)

        // Once the backoff has genuinely elapsed, it retries.
        now = failedAt.addingTimeInterval(policy.initialBackoff)
        gate.updateVisibility([studio], now: now)
        XCTAssertEqual(gate.candidate(from: [studio], now: now), studio)
    }

    // MARK: - User stop suppression

    func testUserStopSuppressesUntilTheReceiverActuallyDisappears() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        gate.beginAttempt(identity: studio, now: date(2))
        gate.noteSuccess()

        gate.noteUserStopped(identity: studio)
        XCTAssertTrue(gate.isSuppressed(identity: studio))

        // Still advertised: Stop must stay stopped, however long we wait.
        for tick in stride(from: 3.0, through: 600.0, by: 30.0) {
            gate.updateVisibility([studio], now: date(tick))
            XCTAssertNil(gate.candidate(from: [studio], now: date(tick)))
        }

        // Cable out for longer than the grace period, then back in.
        gate.updateVisibility([], now: date(700))
        gate.updateVisibility([], now: date(700 + policy.absenceGrace))
        XCTAssertFalse(gate.isSuppressed(identity: studio))
        gate.updateVisibility([studio], now: date(800))
        XCTAssertEqual(gate.candidate(from: [studio], now: date(800 + policy.settleInterval)), studio)
    }

    func testUserStopSurvivesABriefFlap() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        gate.noteUserStopped(identity: studio)
        gate.updateVisibility([], now: date(1))
        gate.updateVisibility([studio], now: date(2))
        XCTAssertTrue(gate.isSuppressed(identity: studio))
        XCTAssertNil(gate.candidate(from: [studio], now: date(100)))
    }

    func testUserStopDuringAnAttemptCancelsIt() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        gate.beginAttempt(identity: studio, now: date(2))
        gate.noteUserStopped(identity: studio)
        XCTAssertNil(gate.attemptInFlight)
    }

    func testStoppingOneReceiverLeavesAnotherEligible() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio, mini], now: date(0))
        gate.noteUserStopped(identity: studio)
        XCTAssertEqual(gate.candidate(from: [studio, mini], now: date(policy.settleInterval)), mini)
    }

    // MARK: - Explicit opt-in

    func testArmingMakesAnAlreadyVisibleReceiverImmediatelyEligible() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        gate.noteUserStopped(identity: studio)
        gate.beginAttempt(identity: studio, now: date(0))
        gate.noteFailure(now: date(policy.attemptTimeout))

        gate.arm(identity: studio, now: date(20))
        XCTAssertFalse(gate.isSuppressed(identity: studio))
        XCTAssertEqual(gate.failureCount(identity: studio), 0)
        XCTAssertEqual(gate.candidate(from: [studio], now: date(20)), studio)
    }

    func testForgettingAReceiverDropsItsStateAndAttempt() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio], now: date(0))
        gate.beginAttempt(identity: studio, now: date(2))
        gate.forget(identity: studio)
        XCTAssertNil(gate.attemptInFlight)
        XCTAssertFalse(gate.isTracking(identity: studio))
    }

    func testCandidateOrderFollowsTheCallersPreference() {
        var gate = TBAutoConnectGate()
        gate.updateVisibility([studio, mini], now: date(0))
        XCTAssertEqual(gate.candidate(from: [mini, studio], now: date(policy.settleInterval)), mini)
        XCTAssertEqual(gate.candidate(from: [studio, mini], now: date(policy.settleInterval)), studio)
    }

    func testUntrackedReceiverIsNeverACandidate() {
        let gate = TBAutoConnectGate()
        XCTAssertNil(gate.candidate(from: [studio], now: date(1_000)))
    }
}
