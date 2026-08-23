import XCTest
@testable import TargetBridge

final class TBDisplayProfileTests: XCTestCase {
    func testWork5KUsesAnExtendedNative5KDisplay() {
        let settings = TBDisplayProfile.work5K.settings

        XCTAssertEqual(settings.captureSource, .extendedDesktop)
        XCTAssertEqual(settings.capturePreset, .native5k)
        XCTAssertTrue(settings.matchRenderToStream)
        XCTAssertNil(settings.audioEnabled)
    }

    func testLowLatencyPrioritizesSmoothVideoWithoutAudio() {
        let settings = TBDisplayProfile.lowLatency.settings

        XCTAssertEqual(settings.captureSource, .desktopMirror)
        XCTAssertEqual(settings.capturePreset, .smooth1440p60)
        XCTAssertFalse(settings.matchRenderToStream)
        XCTAssertNil(settings.audioEnabled)
    }

    func testPresentationUsesACompatibleMirrorProfileWithAudio() {
        let settings = TBDisplayProfile.presentation.settings

        XCTAssertEqual(settings.captureSource, .desktopMirror)
        XCTAssertEqual(settings.capturePreset, .standard1440p)
        XCTAssertEqual(settings.audioEnabled, true)
    }

    func testAudioPreferenceRepairRestoresOnlyTheAmbiguousDisabledState() {
        XCTAssertTrue(TBDisplaySenderService.restoredAudioEnabled(from: false, repairPending: true))
        XCTAssertFalse(TBDisplaySenderService.restoredAudioEnabled(from: false, repairPending: false))
        XCTAssertTrue(TBDisplaySenderService.restoredAudioEnabled(from: true, repairPending: false))
    }
}

final class TBCapturePresetSizeTests: XCTestCase {
    /// 15" MacBook Air in its default scaled mode: 1920x1243 points backed by a
    /// 3840x2486 framebuffer.
    private func airProfile(
        captureWidth: Int = 3840,
        captureHeight: Int = 2486
    ) -> TBMonitorDisplayProfile {
        TBMonitorDisplayProfile(
            receiverName: "Air",
            panelWidth: 3840,
            panelHeight: 2486,
            modeWidth: 1920,
            modeHeight: 1243,
            refreshRate: 60,
            hiDPI: true,
            captureWidth: captureWidth,
            captureHeight: captureHeight
        )
    }

    func testFixedPresetsIgnoreTheReceiverProfile() {
        let profile = airProfile()

        XCTAssertEqual(
            TBDisplayCapturePreset.native5k.captureSize(for: profile),
            TBCaptureSize(width: 5120, height: 2880)
        )
        XCTAssertEqual(
            TBDisplayCapturePreset.standard1440p.captureSize(for: profile),
            TBCaptureSize(width: 2560, height: 1440)
        )
    }

    func testMatchReceiverStreamsTheReceiverBackingStore() {
        XCTAssertEqual(
            TBDisplayCapturePreset.matchReceiver.captureSize(for: airProfile()),
            TBCaptureSize(width: 3840, height: 2486)
        )
    }

    func testMatchReceiverRoundsOddDimensionsDownToEven() {
        // 4:2:0 chroma subsampling cannot encode odd dimensions.
        let size = TBDisplayCapturePreset.matchReceiver.captureSize(
            for: airProfile(captureWidth: 3841, captureHeight: 2487)
        )

        XCTAssertEqual(size, TBCaptureSize(width: 3840, height: 2486))
    }

    func testMatchReceiverFallsBackBeforeTheProfileHandshake() {
        XCTAssertEqual(
            TBDisplayCapturePreset.matchReceiver.captureSize(for: nil),
            TBDisplayCapturePreset.unresolvedCaptureSize
        )
    }

    func testMatchReceiverIgnoresDegenerateReceiverGeometry() {
        XCTAssertEqual(
            TBDisplayCapturePreset.matchReceiver.captureSize(
                for: airProfile(captureWidth: 0, captureHeight: 0)
            ),
            TBDisplayCapturePreset.unresolvedCaptureSize
        )
    }

    /// Under `.matchReceiver` the stream is already the receiver's backing
    /// store, so render matching should resolve to its native point size and
    /// therefore change nothing.
    func testRenderMatchingIsANoOpUnderMatchReceiver() {
        let profile = airProfile()
        let mode = TBDisplayCapturePreset.matchReceiver.renderMatchedDisplayMode(for: profile)

        XCTAssertEqual(mode.width, profile.modeWidth)
        XCTAssertEqual(mode.height, profile.modeHeight)
        XCTAssertEqual(mode.backingWidth, profile.panelWidth)
        XCTAssertEqual(mode.backingHeight, profile.panelHeight)
    }

    func testMatchReceiverBitRateTracksPixelCount() {
        let air = TBDisplayCapturePreset.matchReceiver.averageBitRate(
            for: TBCaptureSize(width: 3840, height: 2486)
        )
        let smaller = TBDisplayCapturePreset.matchReceiver.averageBitRate(
            for: TBCaptureSize(width: 2560, height: 1440)
        )

        XCTAssertGreaterThan(air, smaller)
        // Tuned for wired Thunderbolt, so it should sit well above the Wi-Fi
        // oriented 5K preset rather than on the same curve.
        XCTAssertGreaterThan(
            air,
            TBDisplayCapturePreset.native5k60Experimental.averageBitRate(
                for: TBCaptureSize(width: 5120, height: 2880)
            )
        )
    }

    /// The ceiling keeps the stream inside HEVC Level 6.1 High tier (480 Mbps)
    /// so VideoToolbox does not clamp or emit an undecodable stream.
    func testMatchReceiverBitRateStaysWithinHEVCLevelLimits() {
        let huge = TBDisplayCapturePreset.matchReceiver.averageBitRate(
            for: TBCaptureSize(width: 7680, height: 4320)
        )
        let tiny = TBDisplayCapturePreset.matchReceiver.averageBitRate(
            for: TBCaptureSize(width: 640, height: 480)
        )

        XCTAssertLessThanOrEqual(huge, 400_000_000)
        XCTAssertGreaterThanOrEqual(tiny, 60_000_000)
    }

    func testFixedPresetBitRatesAreUnchanged() {
        let ignored = TBCaptureSize(width: 1, height: 1)

        XCTAssertEqual(TBDisplayCapturePreset.standard1440p.averageBitRate(for: ignored), 36_000_000)
        XCTAssertEqual(TBDisplayCapturePreset.native5k.averageBitRate(for: ignored), 120_000_000)
    }
}
