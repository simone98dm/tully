# tully icon

Chosen direction: **A · Ring gauge**, a 3/4 usage arc around a small window. It ties the usage rings and the Window Ring together and stays legible at 16 px.

| File | What |
|---|---|
| `IconKit.swift` | Draws all three explored directions with Core Graphics; the single source for every exported size |
| `glyph.svg`, `app-icon.svg` | SVG masters of the chosen glyph and app icon |
| `directions.png` | Comparison sheet: menu bar (light/dark, real size and zoomed) and app icon sizes |

Regenerate everything with `./scripts/export-icons.sh` (writes `AppIcon.appiconset` PNGs and the vector template `MenuIcon` PDF).

The menu bar icon is a template image, so macOS tints it for light, dark and tinted menu bars and Increase Contrast.
