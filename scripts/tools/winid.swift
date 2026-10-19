// Lists on-screen windows of an app: "<id> <layer> <width> <height> <title>". Used by scripts/screenshots.sh.
import CoreGraphics
let owner = CommandLine.arguments[1]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == owner {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    print(w[kCGWindowNumber as String]!, w[kCGWindowLayer as String]!, b["Width"]!, b["Height"]!, w[kCGWindowName as String] ?? "")
}
