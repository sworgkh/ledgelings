import AppKit
import CoreAudio
import LedgelingsCore

/// What the weather needs to know about the Mac (SPEC §7.20), read without asking for any permission: the
/// other apps' windows (only their frames, for the snow on their tops and for a full-screen app), whether a
/// microphone is in use (a call), and how long since a key was pressed.
@MainActor
enum WeatherWatch {
    /// Another app's window on screen, front first: its number and frame in AppKit's global points (y up).
    struct Window: Equatable {
        var id: Int
        var frame: CGRect
    }

    /// The ordinary windows of every other app on screen now, front to back.
    static func windows() -> [Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let top = NSScreen.screens.first?.frame.maxY else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0, (info[kCGWindowOwnerPID as String] as? pid_t) != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat], let x = b["X"], let y = b["Y"],
                  let w = b["Width"], let h = b["Height"], w >= 80, h >= 40,
                  let id = info[kCGWindowNumber as String] as? Int else { return nil }
            return Window(id: id, frame: CGRect(x: x, y: top - y - h, width: w, height: h))
        }
    }

    /// A window fills one of `screens` whole: a full-screen app (or one zoomed to cover the menu bar too).
    static func fullScreen(_ windows: [Window], screens: [CGRect]) -> Bool {
        windows.contains { w in screens.contains { abs($0.minX - w.frame.minX) < 1 && abs($0.maxY - w.frame.maxY) < 1 && abs($0.width - w.frame.width) < 1 && abs($0.height - w.frame.height) < 1 } }
    }

    /// Seconds since a key was last pressed anywhere; the Mac's own count, no permission needed.
    static var keyIdle: Double { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) }

    /// An app is listening on the default microphone now: a call, a meeting.
    static var microphoneInUse: Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// The windows' tops as the sky of the monitor at `display` sees them, in its art pixels (`scale` points
    /// each, y down from its top): the columns under a window further front are left out.
    static func ledges(_ windows: [Window], on display: CGRect, scale: CGFloat, topInset: CGFloat) -> [Int: Weather.Ledge] {
        var out: [Int: Weather.Ledge] = [:]
        for (k, w) in windows.enumerated() {
            let top = w.frame.maxY
            // Its top on this monitor, below the menu bar, and not the monitor's own bottom.
            guard top <= display.maxY - topInset, top > display.minY + 40, w.frame.maxX > display.minX, w.frame.minX < display.maxX else { continue }
            let x0 = max(w.frame.minX, display.minX), x1 = min(w.frame.maxX, display.maxX)
            let ax = Int(((x0 - display.minX) / scale).rounded(.up)), width = Int(((x1 - display.minX) / scale).rounded(.down)) - ax
            guard width > 4 else { continue }
            let y = Int(((display.maxY - top) / scale).rounded())
            let front = windows[..<k].map(\.frame)
            let open = (0..<width).map { c -> Bool in
                let p = CGPoint(x: display.minX + (CGFloat(ax + c) + 0.5) * scale, y: top + scale)
                return !front.contains { $0.contains(p) }
            }
            guard open.contains(true) else { continue }
            out[w.id] = Weather.Ledge(x: ax, y: y, open: open)
        }
        return out
    }
}
