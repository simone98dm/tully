import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
print(list.filter { $0[kCGWindowOwnerName as String] as? String == "tully" }.map { "\($0[kCGWindowLayer as String]!) \(($0[kCGWindowBounds as String] as! [String: Any])["Width"]!)" })
