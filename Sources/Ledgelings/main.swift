import AppKit

// Scroll bars that stay put, whatever System Settings says: an overlay bar
// that fades out tells nobody a settings column goes on below the fold.
UserDefaults.standard.register(defaults: ["AppleShowScrollBars": "Always"])
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// `LEDGELINGS_APPEARANCE=light|dark`: every window in that mode, whatever the Mac is in, for snapshots of both.
switch ProcessInfo.processInfo.environment["LEDGELINGS_APPEARANCE"] {
case "light": app.appearance = NSAppearance(named: .aqua)
case "dark": app.appearance = NSAppearance(named: .darkAqua)
default: break
}
app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, no app menu
app.run()
