#!/bin/sh
# File Converter end-to-end: real drag sessions + synthetic Shift/Command/Control taps and keys against tully.app.
# Needs Accessibility permission for the terminal (to post events). Moves the mouse; don't touch it while running.
set -u
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
WORK=$(mktemp -d)
BIN="$WORK/bin"; mkdir -p "$BIN"
for t in dragsource driver key wins click; do swiftc -O "$t.swift" -o "$BIN/$t" 2>/dev/null || { echo "build $t failed"; exit 1; }; done
APP="$ROOT/dist/tully.app"
[ -d "$APP" ] || "$ROOT/scripts/build.sh" Debug
F="$WORK/files"; mkdir -p "$F/batch" "$F/dest"
DOMAIN=com.simone98dm.tully
pkill -x tully; sleep 0.5
defaults write $DOMAIN tully.converter.enabled -bool true
defaults write $DOMAIN tully.converter.hasOnboarded -bool true
defaults write $DOMAIN tully.converter.moveFolders -array "$F/dest"
open "$APP"; sleep 3

swift - "$F/photo.png" <<'SWIFT'
import AppKit
let ctx = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
for i in 0..<40 { ctx.setFillColor(CGColor(red: CGFloat(i % 5) / 5, green: CGFloat(i % 7) / 7, blue: 0.4, alpha: 1)); ctx.fill(CGRect(x: i * 15, y: (i * 37) % 300, width: 60, height: 90)) }
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
cp "$F/photo.png" "$F/batch/a.png"; cp "$F/photo.png" "$F/batch/b.png"; cp "$F/photo.png" "$F/mover.png"; cp "$F/photo.png" "$F/mover2.png"

PASS=0; FAIL=0
ok() { echo "PASS $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL $1"; FAIL=$((FAIL+1)); }
check() { if [ -e "$2" ]; then ok "$1"; else ko "$1 (missing $2)"; fi; }
count() { ls "$F" | wc -l | tr -d ' '; }
# drag FILES MOD DX DY [KEYS]: the source stays open like Finder, so focus behaves as in real use.
drag() { pkill -f "$BIN/dragsource"; files=$1; shift; ("$BIN/dragsource" $files >/dev/null 2>&1 &); sleep 1.5; "$BIN/driver" "$@" >/dev/null; sleep 3; }

# First drag after launch: the wheel must open under the cursor, so a hub drop cancels.
drag "$F/photo.png" shift 0 0
if [ "$(count)" = "5" ]; then ok "hub drop cancels"; else ko "hub drop created a file"; fi
# Convert wheel by mouse (png targets: JPG at 12 o'clock, WEBP at 1:30)
drag "$F/photo.png" shift 0 -88;  check "Shift wheel -> JPG" "$F/photo.jpg"
# Keyboard: Right x2 highlights WEBP, Return picks it; Escape closes without converting.
drag "$F/photo.png" shift 0 0 "124,124,36"; check "arrows + Return -> WEBP" "$F/photo.webp"
before=$(count); drag "$F/photo.png" shift 0 -88 "53"
if [ "$(count)" = "$before" ]; then ok "Escape closes the wheel"; else ko "Escape still converted"; fi
# Return with nothing highlighted opens the full list after release (not under the held mouse).
pkill -f "$BIN/dragsource"; ("$BIN/dragsource" "$F/photo.png" >/dev/null 2>&1 &); sleep 1.5; "$BIN/driver" shift 0 0 "36" >/dev/null; sleep 1.5
if "$BIN/wins" | grep -q '"101 '; then ok "Return opens the list"; else ko "Return list"; fi
"$BIN/key" 53; sleep 1
# Batch
drag "$F/batch/a.png $F/batch/b.png" shift 0 -88; check "batch a.jpg" "$F/batch/a.jpg"; check "batch b.jpg" "$F/batch/b.jpg"
# Actions wheel: Copy Path (8 o'clock), Copy (4 o'clock), Float (2 o'clock), Move (6 o'clock -> folder menu)
drag "$F/photo.png" control -76 44
if [ "$(pbpaste)" = "$F/photo.png" ]; then ok "Control wheel -> Copy Path"; else ko "Copy Path: $(pbpaste)"; fi
drag "$F/photo.png" control 76 44
copied=$(swift -e 'import AppKit; print((NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).map(\.path).joined())')
if [ "$copied" = "$F/photo.png" ]; then ok "Control wheel -> Copy"; else ko "Copy: $copied"; fi
drag "$F/photo.png" control 76 -44
if "$BIN/wins" | grep -q 140; then ok "Control wheel -> Float window"; else ko "Float window"; fi
drag "$F/mover.png" control 0 88
"$BIN/click" 320 400; sleep 1.5   # first menu item ("dest") sits just below-right of the drop point
check "Control wheel -> Move menu" "$F/dest/mover.png"
# Same by keyboard mid-drag (Right x4 = Move, Return): the menu opens at release, under the hub, not clicked by it.
drag "$F/mover2.png" control 0 0 "124,124,124,124,36"
"$BIN/click" 320 312; sleep 1.5
check "Keyboard -> Move menu" "$F/dest/mover2.png"
# Tools wheel: Compress (12 o'clock) opens the form, Return runs it (the form takes focus while the source stays frontmost)
drag "$F/photo.png" command 0 -88; "$BIN/key" 36; sleep 4; check "Command wheel -> Compress" "$F/photo compressed.png"
# Tools wheel overflow: More… (11 o'clock) -> list -> first item -> form -> Run
rm -f "$F/photo compressed.png"
drag "$F/photo.png" command -52 -71; sleep 1; "$BIN/key" 125; sleep 0.5; "$BIN/key" 36; sleep 2; "$BIN/key" 36; sleep 5
check "More… list -> Compress" "$F/photo compressed.png"

pkill -f "$BIN/dragsource"; pkill -x tully
defaults delete $DOMAIN tully.converter.moveFolders
echo "e2e: $PASS passed, $FAIL failed"
rm -rf "$WORK"
[ "$FAIL" = 0 ]
