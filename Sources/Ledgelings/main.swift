import AppKit

// Scroll bars that stay put, whatever System Settings says: an overlay bar
// that fades out tells nobody a settings column goes on below the fold.
UserDefaults.standard.register(defaults: ["AppleShowScrollBars": "Always"])
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, no app menu
app.run()
