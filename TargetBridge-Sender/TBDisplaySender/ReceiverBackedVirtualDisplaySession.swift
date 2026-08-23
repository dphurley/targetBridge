import CoreGraphics
import Foundation

extension CGVirtualDisplayDescriptor: @unchecked @retroactive Sendable {}
extension CGVirtualDisplay: @unchecked @retroactive Sendable {}
extension CGVirtualDisplaySettings: @unchecked @retroactive Sendable {}

/// Pixel size of the mode handed to CGVirtualDisplay. With `settings.hiDPI = true`
/// macOS synthesises a strictly 2x backing store, so a mode of (w, h) renders the
/// desktop into a (2w, 2h) framebuffer and reports "looks like w x h" in Displays.
struct TBVirtualDisplayModeSize: Equatable {
    let width: Int
    let height: Int

    var backingWidth: Int { width * 2 }
    var backingHeight: Int { height * 2 }
}

struct TBVirtualDisplayIdentity {
    let productID: UInt32
    let serialNumber: UInt32
    let displayNamePrefix: String
    let usesDedicatedArrangementIdentity: Bool

    static let desktopMirror = TBVirtualDisplayIdentity(
        productID: 0x5000,
        serialNumber: 0x2026,
        displayNamePrefix: "TB Mirror",
        usesDedicatedArrangementIdentity: false
    )

    static func extendedDesktop(receiverKey: String) -> TBVirtualDisplayIdentity {
        // Deterministic identity per receiver so macOS retains window placement
        // and the saved extended-desktop arrangement across reconnects.
        //
        // `receiverKey` must uniquely identify the receiver (the caller derives it
        // from the connection address, matching the saved-arrangement key). Keying
        // on the receiver-reported display name alone is not enough: identical iMac
        // models report the same SDL display name and the same hard-coded panel
        // size, so two of them would derive the same identity and macOS would
        // refuse to create the second virtual display.
        let hash = djb2(receiverKey)
        let productLow = (hash & 0x00FF) | 0x01
        let serialLow = (hash & 0xFFFE) | 0x0100
        return TBVirtualDisplayIdentity(
            productID: 0x6000 | productLow,
            serialNumber: 0x2027_0000 | UInt32(serialLow),
            displayNamePrefix: "TB Extend",
            usesDedicatedArrangementIdentity: true
        )
    }

    private static func djb2(_ input: String) -> UInt32 {
        var hash: UInt32 = 5381
        for byte in input.utf8 {
            hash = hash &* 33 &+ UInt32(byte)
        }
        return hash
    }
}

@MainActor
final class ReceiverBackedVirtualDisplaySession {
    private var virtualDisplay: CGVirtualDisplay?
    private(set) var displayID: CGDirectDisplayID = kCGNullDirectDisplay
    private(set) var displayName: String = ""
    private(set) var identityDescription: String = ""

    func create(
        from profile: TBMonitorDisplayProfile,
        refreshRate: Double? = nil,
        modeOverride: TBVirtualDisplayModeSize? = nil,
        identity: TBVirtualDisplayIdentity,
        receiverKey: String
    ) -> Bool {
        destroy()
        let preferredRefreshRate = refreshRate ?? profile.refreshRate

        // `profile.modeWidth/Height` is the receiver's own logical desktop and
        // `panelWidth/Height` its HiDPI backing store, so the default mode below
        // reproduces the receiver's native geometry exactly. `modeOverride` lets
        // the sender instead size the backing store to the capture preset, so
        // capture is 1:1 and only the panel-side scale remains.
        var resolvedMode = modeOverride ?? TBVirtualDisplayModeSize(
            width: profile.modeWidth,
            height: profile.modeHeight
        )

        // macOS refuses a HiDPI mode whose backing store exceeds the advertised
        // panel. Clamp to the largest mode the panel can actually back — the
        // previous fallback re-assigned the profile default, which is the value
        // `resolvedMode` already holds whenever no override was supplied.
        let requiredWidth = profile.hiDPI ? resolvedMode.backingWidth : resolvedMode.width
        let requiredHeight = profile.hiDPI ? resolvedMode.backingHeight : resolvedMode.height
        if requiredWidth > profile.panelWidth || requiredHeight > profile.panelHeight {
            let scale = profile.hiDPI ? 2 : 1
            let fitted = TBVirtualDisplayModeSize(
                width: profile.panelWidth / scale,
                height: profile.panelHeight / scale
            )
            NSLog(
                "TargetBridge: mode %dx%d needs a %dx%d backing store, exceeds panel %dx%d; clamping to %dx%d",
                resolvedMode.width, resolvedMode.height,
                requiredWidth, requiredHeight,
                profile.panelWidth, profile.panelHeight,
                fitted.width, fitted.height
            )
            resolvedMode = fitted
        }

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "\(identity.displayNamePrefix) - \(profile.receiverName)"
        descriptor.vendorID = 0xEEEE
        descriptor.productID = identity.productID
        descriptor.serialNum = identity.serialNumber
        descriptor.serialNumber = identity.serialNumber
        descriptor.maxPixelsWide = UInt32(profile.panelWidth)
        descriptor.maxPixelsHigh = UInt32(profile.panelHeight)

        // A virtual display without chromaticity metadata can receive a generic
        // ColorSync profile. In mirror mode that makes macOS render the same
        // desktop differently from the built-in Display P3 panel. Advertise the
        // iMac's wide-gamut SDR space explicitly so capture is colour-managed
        // before it enters the 8-bit NV12 video pipeline.
        descriptor.whitePoint = CGPoint(x: 0.3125, y: 0.3291) // D65
        descriptor.redPrimary = CGPoint(x: 0.6797, y: 0.3203)
        descriptor.greenPrimary = CGPoint(x: 0.2559, y: 0.6983)
        descriptor.bluePrimary = CGPoint(x: 0.1494, y: 0.0557)

        // Prefer the receiver's real panel size. Receivers predating the
        // dynamic-geometry change omit it, so fall back to the 27" 5K iMac
        // density this originally hard-coded.
        let fallbackPPI = 218.0
        descriptor.sizeInMillimeters = CGSize(
            width: profile.physicalWidthMM ?? (Double(profile.panelWidth) / fallbackPPI * 25.4),
            height: profile.physicalHeightMM ?? (Double(profile.panelHeight) / fallbackPPI * 25.4)
        )

        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            return false
        }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = profile.hiDPI
        guard let mode = CGVirtualDisplayMode(
            width: UInt(resolvedMode.width),
            height: UInt(resolvedMode.height),
            refreshRate: preferredRefreshRate
        ) else {
            return false
        }
        settings.modes = [mode]

        guard display.apply(settings), display.displayID != kCGNullDirectDisplay else {
            return false
        }

        // Restore the user's previously chosen mode for this receiver if we have
        // one; otherwise fall back to the receiver-advertised profile default.
        // An explicit render-matching override outranks the remembered choice: a
        // stale manual pick would silently break the 1:1 capture the user asked for.
        let preferenceKey = TBVirtualDisplayModeMemory.preferenceKey(
            for: identity,
            receiverKey: receiverKey
        )
        // A saved 1x choice against a HiDPI profile is an artefact of macOS
        // settling the display, not a deliberate pick, and restoring it would
        // re-impose the very fault it recorded. Discard it.
        let rawSavedChoice = modeOverride == nil
            ? TBVirtualDisplayModeMemory.shared.load(forKey: preferenceKey)
            : nil
        let savedChoice = rawSavedChoice.flatMap { choice -> TBVirtualDisplayModeMemory.Choice? in
            guard profile.hiDPI,
                  choice.pixelWidth == choice.pointWidth,
                  choice.pixelHeight == choice.pointHeight else { return choice }
            NSLog(
                "TargetBridge: discarding remembered 1x mode %dx%d for a HiDPI receiver",
                choice.pointWidth, choice.pointHeight
            )
            return nil
        }
        activatePreferredMode(for: display.displayID,
                              mode: resolvedMode,
                              refreshRate: preferredRefreshRate,
                              hiDPI: profile.hiDPI,
                              savedChoice: savedChoice)

        virtualDisplay = display
        displayID = display.displayID
        displayName = profile.receiverName
        identityDescription = "vendor=0x\(String(descriptor.vendorID, radix: 16)) product=0x\(String(identity.productID, radix: 16)) serial=0x\(String(identity.serialNumber, radix: 16))"

        // Remember any manual resolution change the user makes from now on, so it
        // sticks across reconnects for this receiver.
        TBVirtualDisplayModeMemory.shared.track(displayID: display.displayID, key: preferenceKey)
        return true
    }

    func destroy() {
        if displayID != kCGNullDirectDisplay {
            TBVirtualDisplayModeMemory.shared.untrack(displayID: displayID)
        }
        virtualDisplay = nil
        displayID = kCGNullDirectDisplay
        displayName = ""
        identityDescription = ""
    }

    @discardableResult
    private func activatePreferredMode(for displayID: CGDirectDisplayID,
                                       mode: TBVirtualDisplayModeSize,
                                       refreshRate: Double,
                                       hiDPI: Bool,
                                       savedChoice: TBVirtualDisplayModeMemory.Choice?) -> Bool {
        let timeout = Date().addingTimeInterval(2.0)
        while Date() < timeout {
            var success = false
            autoreleasepool {
                let chosenMode = savedChoice.flatMap { savedMode(for: displayID, choice: $0) }
                    ?? preferredMode(for: displayID, mode: mode, refreshRate: refreshRate, hiDPI: hiDPI)
                if let chosenMode {
                    success = CGDisplaySetDisplayMode(displayID, chosenMode, nil) == .success
                }
            }
            if success {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return false
    }

    /// Find the display mode matching a saved choice. Matches on pixel size as
    /// well as point size so a HiDPI mode is not confused with its 1× ("Standard")
    /// counterpart. The low-resolution-duplicates option ensures both variants are
    /// enumerated.
    private func savedMode(for displayID: CGDirectDisplayID, choice: TBVirtualDisplayModeMemory.Choice) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modesCF = CGDisplayCopyAllDisplayModes(displayID, options) else {
            return nil
        }
        let modes = modesCF as? [CGDisplayMode] ?? []

        let candidates = modes.filter { mode in
            mode.width == choice.pointWidth && mode.height == choice.pointHeight &&
            mode.pixelWidth == choice.pixelWidth && mode.pixelHeight == choice.pixelHeight
        }
        if let exact = candidates.first(where: { abs($0.refreshRate - choice.refreshRate) < 0.5 }) {
            return exact
        }
        return candidates.first
    }

    private func preferredMode(for displayID: CGDirectDisplayID,
                               mode: TBVirtualDisplayModeSize,
                               refreshRate: Double,
                               hiDPI: Bool) -> CGDisplayMode? {
        // Enumerate duplicates so the 1x twin of a HiDPI mode is visible and can
        // be discriminated against below, rather than left to chance.
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modesCF = CGDisplayCopyAllDisplayModes(displayID, options) else {
            return nil
        }
        let modes = modesCF as? [CGDisplayMode] ?? []

        var matchingModes = modes.filter { candidate in
            candidate.width == mode.width && candidate.height == mode.height
        }

        // A HiDPI mode and its 1x duplicate report identical point dimensions;
        // only the backing store tells them apart. Filtering on point size alone
        // let the 1x variant win on enumeration order, which silently halved the
        // render resolution: the desktop looked the right size but every glyph
        // was rasterised at 1x and then upscaled by the capture stage.
        if hiDPI {
            let retina = matchingModes.filter {
                $0.pixelWidth == mode.backingWidth && $0.pixelHeight == mode.backingHeight
            }
            if !retina.isEmpty {
                matchingModes = retina
            } else {
                NSLog(
                    "TargetBridge: no HiDPI mode %dx%d (backing %dx%d) offered by display %u; falling back to 1x",
                    mode.width, mode.height, mode.backingWidth, mode.backingHeight, displayID
                )
            }
        }

        let sorted = matchingModes.sorted { $0.refreshRate > $1.refreshRate }
        if let exactMatch = sorted.first(where: { abs($0.refreshRate - refreshRate) < 0.5 }) {
            return exactMatch
        }

        return sorted.first
    }
}
