import CoreGraphics
import Foundation

// Read-only. Window titles can contain private information; do not publish output.
let owners = Set(CommandLine.arguments.dropFirst())
let defaults: Set<String> = ["System Preferences", "System Settings", "ToDesk"]
guard let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
    fputs("无法读取窗口列表。\n", stderr)
    exit(1)
}
for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    guard (owners.isEmpty ? defaults : owners).contains(owner) else { continue }
    let number = window[kCGWindowNumber as String] as? Int ?? 0
    let title = window[kCGWindowName as String] as? String ?? ""
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let onScreen = window[kCGWindowIsOnscreen as String] as? Int ?? 0
    let bounds = window[kCGWindowBounds as String] ?? ""
    print("owner=\(owner) id=\(number) layer=\(layer) onScreen=\(onScreen) title=\(title) bounds=\(bounds)")
}
