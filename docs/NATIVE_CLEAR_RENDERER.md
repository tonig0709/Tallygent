# Native Clear — local build 60

Operate surface: a readable floating quota panel, with the existing three sizes,
charts, drag/close/settings behavior and continuous native sliders. This is a
material extension, not a replacement product identity.

## Preview / placed-panel parity (build 59)

Settings, gallery and the placed desktop now route through `LiquidGlassSurface`.
The old `DesktopGlassSurface` / forced dark popover path is removed. Tinted glass
keeps the approved preview backend (SwiftUI clear Liquid Glass on macOS 26;
ultra-thin material fallback on older systems), with identical film, haze, tint,
rim, refraction and pointer layers. Light mode also uses the preview's exact fill
curve instead of a separate desktop formula. Reduce Transparency shares an
explicit opaque fallback.

Only Native Clear moves its one popover backdrop outside SwiftUI, into the
desktop root. `nativeClearBackdropProvided` skips the embedded backdrop only in
that branch; it never skips coatings or Tinted Glass. The root stays hidden for
Tinted Glass, avoiding double frosting. Preview and desktop still sample their
respective backgrounds, so different wallpapers/windows cannot yield identical
pixels. No preferences are reset or migrated to conceal a renderer mismatch.

The window configurator also reapplies its latest value when its native view
attaches to a window. Large charts can defer that attachment beyond a settings
update; a one-shot queued call with a nil window previously dropped the change.
Queued work now reads the view's latest configuration rather than an older
captured value. A dedicated late-attachment/latest-value probe guards this race.

The pure `scripts/check-glass-renderer-parity.sh` guards all three entry paths
and backdrop exclusivity. The isolated desktop probe also switches both
materials, dark/light/automatic, opacity endpoints and all sizes on the actual
placed view. Its cached frames test settings propagation, not live wallpaper
transmission; that last optical check remains a real-desktop acceptance step.

## Material boundary

The old Clear preset only changed numbers in the tinted renderer. Native Clear
is now an explicit persisted `glassSurfaceStyle` choice. Selecting **Native
Clear** or the **Clear** preset resets to 0.35 opacity, zero added haze and neutral
tone. Light/Dark is retained for Tinted Glass, but does not recolor Native Clear.

The desktop window has an AppKit `NSVisualEffectView` root below the transparent
SwiftUI content host. It uses public `.popover`, `.behindWindow`, `.active` and
the native vibrant appearance. There is no wallpaper screenshot, screen recording
permission, private blur API, global desktop preference, React runtime or new
dependency. At the clear preset's minimum, film, haze and neutral tone add zero
interior color; the operating system provides backdrop sampling and frosting.
Higher opacity and explicit custom haze/tone still work. Reduce Transparency is
respected. Exact pixels vary with the wallpaper, OS and accessibility settings;
offscreen content renders do not prove actual wallpaper transmission.

## Pointer light

Build 60 adds a shared **Pointer Highlight** slider (0–100%) to both settings
entry points. It controls the cursor-triggered interior glow and rim tracking;
zero removes pointer feedback while preserving fixed glass reflections. The
default is 100%, matching build 59. App preview, gallery and desktop use the same
persisted `glassPointerHighlightIntensity` value. Old snapshots without the
optional field resolve to 100%; zero round-trips without being replaced by a
default. Presets/Restore Defaults restore the standard intensity. Reduce Motion
still uses stationary feedback, and zero disables that feedback too.

Tests cover exact zero/off pixels, monotonic intensity, default compatibility,
three-size surface movement, old JSON/clamping, shared preference routing and
live strength changes on the placed panel for both materials. No account request
or wallpaper sampling changes are involved.

A shared `GlassPointerGlow` paints a bounded white specular field on the interior
and a directional contour reflection, below quota text/charts. It follows local
coordinates continuously, does not translate panel geometry, and fades out on
exit. AppKit `.activeAlways` tracking covers the whole drag region even when the
desktop window is not key. Close/settings remain above that drag region. No
global event monitor, idle animation loop or account request is added. Reduce
Motion fixes the light's position instead of following the cursor.

## Reference and provenance

GitHub repository search `liquid-glass in:name`, sorted by stars, checked
2026-10-31: [rdev/liquid-glass-react](https://github.com/rdev/liquid-glass-react)
led the returned set with 6,565 stars (not a claim about every possible spelling).
Source inspected at `ac48eab18d1f7f444ae30002d240cae29c863a21`, MIT license.
Its container-local mouse coordinates and directional light motivated this native
implementation. No upstream TypeScript or shader code is bundled or copied.
Apple's public AppKit header documents `.popover` as the NSPopover background
material and `.behindWindow` as sampling the desktop/windows behind the window.

## Regression evidence required before handoff

- Existing snapshot JSON without the new optional field decodes as Tinted Glass;
  Native Clear round-trips without changing account/history or Planner data.
- Both local and three-OS CI retain existing contrast, black-screen negative
  controls, rim clipping, slider, three-size/layout and snapshot refresh tests.
- New tests cover native clear root placement/material/corner clipping, full-area
  inactive-window tracking, point delivery and exit, interior light location and
  idle invisibility, clear content in three sizes, and all three translations.
- The exact signed universal DMG payload must pass the existing release gate;
  downloaded ZIP digest, CRC, DMG checksum, build metadata and resources are
  checked again locally. No Release is created. Personal desktop optical matching
  remains a real-install acceptance check, not an offscreen claim.
