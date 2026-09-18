// usage: swift scripts/set-icon.swift <icon.icns> <file>...
// Gives a file a custom Finder icon. It lives in the file's extended
// attributes, so it survives on this Mac but not a trip through most uploads.
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let icon = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: set-icon.swift <icon.icns> <file>...\n".utf8))
    exit(1)
}
for file in args.dropFirst(2) where !NSWorkspace.shared.setIcon(icon, forFile: file) {
    FileHandle.standardError.write(Data("could not set the icon on \(file)\n".utf8))
    exit(1)
}
