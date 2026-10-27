# Tallygent release invariant

Before creating a version tag, DMG, or GitHub Release:

1. The current product is panel-only, as requested by the user. Build the app
   with full Xcode for both `arm64` and `x86_64`. Never package a `swiftc`-assembled
   app, an old WidgetKit extension, or old AppIntent metadata.
2. Sign the app, package the exact signed app, then run:

   ```sh
   CODEX_QUOTA_ISOLATED_REGISTRY=1 \
     ./scripts/release-preflight.sh "/path/to/Tallygent.app" "/path/to/Tallygent.dmg"
   ```

   Run the full command only in an isolated CI user: runtime probes launch a
   fake account server, occupy port 48193, and create a temporary installed app.
   The panel-only gate must not modify a user's PlugInKit registry.
3. Do not publish when the gate fails. It is the single source of truth for
   three panel sizes, single-panel ownership, non-black rendering, live
   synchronization, version/build monotonicity, signatures, architectures, and
   DMG payload integrity. Removed WidgetKit artifacts must remain absent.
4. A version tag creates a draft Release only. Complete the desktop smoke test
   in `RELEASE_CHECKLIST.md`, then publish the draft; a headless runner cannot
   directly operate the desktop compositor, native dragging, or hover controls.

Keep stable Liquid Glass releases separate from the particle experiment. When
a production bug is fixed, add the smallest regression to the release gate so
the same failure cannot pass a later release.

## Product direction (2026-10-24)

The approved product name is **Tallygent**. See `docs/TALLYGENT_ROADMAP.md` before
future feature or branding work. Build 45 has the legacy binary name; build 46
is the first renamed test candidate. Preserve bundle
identity, preference keys, data and panel ownership, and explicitly handle the
Claude bridge's absolute executable path when renaming the installed app.

## Native layout invariant

See `docs/LAYOUT_INVARIANTS.md`. Do not constrain a native Picker's implicit
title and options to a shared fixed width. Use the existing `AdaptivePicker`
for bounded fields and preserve accessibility names. Measure semantic labels,
not only the root window: the desktop gate includes Chinese/English, themes,
large fonts, narrow/threshold widths, same-window restoration and a known-bad
negative control. Keep those checks mandatory and run their UI runtime only
in an isolated CI user. Never delete user preferences to hide a layout bug.
