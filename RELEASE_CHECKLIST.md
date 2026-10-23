# Release checklist — panel-only product

The user requested removal of WidgetKit in favor of three movable desktop panel modes.
The project must build only the App target; legacy extension bundles and AppIntent metadata must not ship.

Every push/PR, version tag and final signed payload runs:

```sh
CODEX_QUOTA_ISOLATED_REGISTRY=1 \
  ./scripts/release-preflight.sh "/path/to/Codex Quota.app" "/path/to/Codex-Quota.dmg"
```

Run the full gate only in an isolated CI user: it installs a temporary candidate,
launches a deterministic fake account server and reserves the local snapshot port.
It must never mutate a real user's PlugInKit registry.
Local non-destructive checks are `swift run quota-self-check` and `./scripts/check-desktop-panel.sh`.

## Automated gate

- **Three layouts:** small 164×164, medium 344×164 and existing large 680×300 logical points.
  Small reuses both quota rings, medium omits the trend, large retains it.
- **One panel:** repeated show calls do not create a second window; close/reopen works.
  Resizing preserves the top-left position, accepts keyboard focus, and keeps the panel below normal apps but above Finder.
- **Selector restoration:** a hosted production Dashboard must position its native scroll
  view on the persisted mode, not just mark a mode button selected. Its minimum height
  must accommodate the complete selector and action row after restoring an old window.
- **Non-black content:** all three layouts × light/dark × minimum/maximum opacity are
  compared against their empty glass surface, including individual quota/trend regions.
  Solid-black negative controls must fail. Updated quota snapshots must change every layout.
- **Shared settings:** opacity boundaries, thresholds, settings serialization and visible
  optical parameter changes remain covered. Mode selection has a safe large-mode fallback.
- **Live data:** fake Codex A→B→C data proves initialization, account read, notifications,
  delayed and queued refreshes, quota progress despite missing trend, preservation of
  last valid trend, unchanged snapshot stability and port-collision recovery.
  Every mode renders the production snapshot client output. Identity is removed from the local endpoint.
- **Update safety:** non-installed copies cannot connect an account or occupy the local port.
  Tagged builds are monotonic and match their marketing version.
- **Exact artifact:** full Xcode universal arm64+x86_64 build, valid app signature,
  original Codex icon, no embedded extension, no old widget intents, verified DMG,
  correct Applications shortcut, no unexpected payloads, and identical app bytes/modes.

CI runs on macOS 14, 15 and 26. A version tag creates a **draft** Release only.

## Required real-desktop smoke test before publishing

- [ ] Install only the checked candidate in Applications; eject its DMG.
- [ ] In the App, swipe left/right through all three modes, including a fast reversal.
      Arrows and mode-name buttons must also work; reduced motion must remain usable.
- [ ] Open the desktop panel, repeatedly switch modes, and verify exactly one panel remains.
      Dimensions match the table, no native title bar/extra blank area appears, and its top-left position stays fixed.
- [ ] Confirm small dual rings, medium two bars without a trend, and the unchanged large layout.
- [ ] In every mode, test dark/light and opacity 0.35, 0.44 and 1.00 without crashes or blank content.
      At 0.35, wallpaper must remain visible; 1.00 dark must stay near-black.
- [ ] Adjust all sliders in the App and in the panel popover. The placed panel follows continuously;
      mode changes preserve all current values.
- [ ] With Finder active, reveal edge controls, drag the top region, close with X, reopen,
      and close via the menu bar. Moving to the center/outside hides chrome.
      Controls stay available while the settings popover is open.
- [ ] Generate usage; verify 5h, weekly and large-panel trend refresh within the expected polling cycle.
      Closing a panel must not stop the App's connection.
- [ ] Verify the installed bundle contains no WidgetKit extension. Old desktop widgets are manually removed;
      do not clear global system caches.
- [ ] Homepage/download instructions clearly identify which published DMG contains this panel-only product.
      Do not advertise a draft or older widget release as the new build.
- [ ] Publish the draft only after all checks above pass.
