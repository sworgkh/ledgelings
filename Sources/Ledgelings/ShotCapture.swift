import AppKit
import LedgelingsCore
import ScreenCaptureKit

/// One monitor as it looked the moment the shot was taken: where it is, and its pixels.
struct ShotFrame {
    var monitor: Shot.Monitor
    var image: CGImage
    var name = ""
}

/// Taking the pictures, with ScreenCaptureKit: every monitor at its own pixel size,
/// without the cursor. macOS asks for **Screen Recording** the first time; without
/// it the capture fails (or, on older systems, shows only the wallpaper).
@MainActor
enum ShotCapture {
    enum Failure: Error, CustomStringConvertible {
        case notAllowed, noDisplays
        var description: String {
            switch self {
            case .notAllowed: tr("Ledgelings needs Screen Recording to take screenshots (System Settings › Privacy & Security).")
            case .noDisplays: tr("No screen to take.")
            }
        }
    }

    /// Screen Recording is granted to this build.
    static var allowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks macOS for Screen Recording, and opens its page in System Settings for the switch.
    static func askForPermission() {
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Every attached monitor, left to right as the screens list has them, without the
    /// windows numbered in `leaving` (the creatures' overlays, when they are hidden).
    static func capture(leaving: Set<CGWindowID> = []) async throws -> [ShotFrame] {
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        catch { throw Failure.notAllowed }
        let hidden = content.windows.filter { leaving.contains($0.windowID) }
        var frames: [ShotFrame] = []
        for screen in NSScreen.screens {
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            guard let display = content.displays.first(where: { $0.displayID == number }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: hidden)
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int((screen.frame.width * scale).rounded())
            config.height = Int((screen.frame.height * scale).rounded())
            config.showsCursor = false
            config.captureResolution = .best
            config.colorSpaceName = CGColorSpace.sRGB
            let image: CGImage
            do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
            catch { throw Failure.notAllowed }
            frames.append(ShotFrame(monitor: Shot.Monitor(frame: screen.frame, scale: scale), image: image, name: screen.localizedName))
        }
        guard !frames.isEmpty else { throw Failure.noDisplays }
        return frames
    }
}
