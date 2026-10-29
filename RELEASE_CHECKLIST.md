# Release checklist — panel-only product

The user requested removal of WidgetKit in favor of three movable desktop panel modes.
The project must build only the App target; legacy extension bundles and AppIntent metadata must not ship.

Every push/PR, version tag and final signed payload runs:

```sh
CODEX_QUOTA_ISOLATED_REGISTRY=1 \
  ./scripts/release-preflight.sh "/path/to/Tallygent.app" "/path/to/Tallygent.dmg"
```

Run the full gate only in an isolated CI user: it installs a temporary candidate,
launches a deterministic fake account server and reserves the local snapshot port.
It must never mutate a real user's PlugInKit registry.
Pure non-destructive checks include `swift run quota-self-check` and the isolated-file
history/Planner checks. `check-desktop-panel.sh` operates native windows/settings;
its runtime requires an isolated CI user, not a personal desktop session.

## Automated gate

- **Native languages:** English, Simplified Chinese and Traditional Chinese tables have identical key coverage and type-compatible placeholders. Packaged tables match source. Isolated native bundles select each language through AppleLanguages; layout checks use real translations, not only a changed Locale environment.

- **Three layouts:** small 164×164, medium 344×164 and existing large 680×300 logical points.
  Small reuses both quota rings, medium omits the trend, large retains it.
- **One panel:** repeated show calls do not create a second window; close/reopen works.
  Resizing preserves the top-left position, accepts keyboard focus, and keeps the panel below normal apps but above Finder.
  The production drag surface covers the panel body and excludes transparent rounded corners.
- **Selector restoration:** a hosted production Dashboard must position its native scroll
  view on the persisted mode, not just mark a mode button selected. Its minimum height
  must accommodate the complete selector and action row after restoring an old window.
- **Internal layout:** compare meaningful title frames against their natural text size
  and local containers across locale/theme/large-font/threshold widths. Shrink and
  restore the same window; include long status text and expanded Planner fields.
  A rendered compressed-CJK negative control must fail these same assertions.
- **Non-black content:** all three layouts × light/dark × minimum/maximum opacity are
  compared against their empty glass surface, including individual quota/trend regions.
  Solid-black negative controls must fail. Updated quota snapshots must change every layout.
- **Shared settings:** opacity boundaries, thresholds, settings serialization and visible
  optical parameter changes remain covered. Mode selection has a safe large-mode fallback.
  Elastic highlights must stay within the rounded rim at every panel size and corner
  radius, at rest and with pointer movement; the old detached blurred bar must fail.
- **Large-panel trends:** seven-day Token / 12h / 24h history × bar/line styles must remain
  readable in both themes and opacity bounds. Plot-only comparisons must prove history
  updates independently of the live clock/current quota. Small/medium pixels remain unchanged.
  Reuse segmented Insights history, match the live account/session, retain empty hours,
  and keep the panel's 24h cache independent of the Insights page's selected range.
- **Live data:** fake Codex A→B→C data proves initialization, account read, notifications,
  delayed and queued refreshes, quota progress despite missing trend, preservation of
  last valid trend, unchanged snapshot stability and port-collision recovery.
  Every mode renders the production snapshot client output. Identity is removed from the local endpoint.
- **Provider isolation:** temporary Claude settings and records prove bounded input,
  missing-data semantics, session binding/reset, receipt time, refusal to overwrite
  another statusLine and reversible setup. Switching providers cannot mix their caches
  or allow a late Codex response to replace selected Claude content.
- **Update safety:** non-installed copies cannot connect an account or occupy the local port.
  Tagged builds are monotonic and match their marketing version.
- **Exact artifact:** full Xcode universal arm64+x86_64 build, valid app signature,
  original Codex icon, no embedded extension, no old widget intents, verified DMG,
  correct Applications shortcut, no unexpected payloads, and identical app bytes/modes.

CI runs on macOS 14, 15 and 26. A version tag creates a **draft** Release only.

## Required real-desktop smoke test before publishing

- [ ] Launch the candidate in English, Simplified Chinese and Traditional Chinese without changing global system preferences. Verify navigation, menu bar, all panel sizes, glass settings, Insights, Planner, errors and chart units; dates/numbers follow region settings. Check long English labels and Traditional Chinese at narrow widths. Switching language must preserve data, panel position and settings.

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
- [ ] With Finder active, reveal edge controls, drag from the title, center, quota content and lower body, close with X, reopen,
      and close via the menu bar. Moving to the center/outside hides chrome.
      Controls stay available while the settings popover is open.
- [ ] Edge dispersion at 0%/100% visibly changes only the rim. Frost depth at 0%/100%
      visibly changes haze at minimum opacity, while fully opaque dark glass stays black.
      Labels must distinguish native system blur from the adjustable haze layer; no private backdrop APIs or screen capture are used.
- [ ] At minimum/maximum elastic highlight and corner radius, check the panel and App
      preview in all three languages: highlights follow the rounded rim, with no detached
      white bar inside the surface. Pointer feedback must not move the rim into content.
- [ ] Generate usage; verify 5h, weekly and large-panel trend refresh within the expected polling cycle.
      Closing a panel must not stop the App's connection.
- [ ] In panel settings switch the large chart among seven-day Token, 12h and 24h, and
      bar/line forms; preview and the same placed panel must agree and survive restart.
      Choosing Insights' 1h range must not truncate the panel; absent history stays blank,
      resets/gaps remain separate, and percentage history is never labeled Token consumption.
- [ ] Switch Codex → Claude → Codex in each panel size. The same single panel follows;
      glass settings and position remain unchanged, and unavailable Claude quota is not 0%.
      Claude is visibly experimental and its timestamp is a local receipt time, not a server refresh claim.
- [ ] For Claude, explicitly test enable/remove/reset using disposable settings first.
      Existing third-party statusLine must be refused; unrelated settings must survive setup/removal.
      Only claim real Claude subscription support after a subscribing tester verifies activity,
      idle/exit behavior, reset fields and session switching. Record an untested result honestly;
      an experimental release may retain that limitation, never mark it as a real-account pass.
- [ ] Verify the installed bundle contains no WidgetKit extension. Old desktop widgets are manually removed;
      do not clear global system caches.
- [ ] Homepage/download instructions clearly identify which published DMG contains this panel-only product.
      Do not advertise a draft or older widget release as the new build.
- [ ] Publish the draft only after all checks above pass.

## Experimental multi-agent checks

- Run `sh scripts/check-agent-providers.sh` before packaging. It must preserve
  provider isolation, missing-data semantics, receipt time, and existing Claude
  configuration using temporary files only.
- Confirm Codex/Claude selection updates the same single desktop panel in all
  sizes, retaining glass preferences and position. Claude is labeled experimental
  and as a session record; it must not claim a fresh background server query.
- Test actual Claude subscription input with a subscribing volunteer before
  claiming real-account support. Mock data cannot satisfy this check.
- Keep bridge setup opt-in; an existing third-party statusLine must remain intact.

## Monitor / Insights checks (build 48 and later)

- Run `sh scripts/check-observation-history.sh` and `sh scripts/check-usage-insights.sh`;
  both are mandatory in the full gate. Never replace existing panel and Planner checks.
- Only accepted source responses create history. Verify unchanged new receipts persist,
  duplicate responses/cache reads/settings/model-list do not, and late responses cannot
  cross account or process ownership. Keep the actual source receipt time despite usage timeout.
- SQLite must pass two-process writes, interruption recovery, bounded lock wait,
  retention, privacy, symlink refusal, version migration and corrupt/future-file preservation.
- On the real desktop verify Insights loads at compact/wide widths, collection toggles
  remain independent of displayed service, export works, and clear leaves all panel/Planner settings intact.
- Cold start, unknown identity, reset, stale source, negative jump and sampling gaps must
  show unknown estimates, not fabricated zero/infinite capacity. Charts must not join segments.
- Notifications are opt-in; verify first enable/no backlog, crossings, dedup across restart,
  disable, account/cycle changes and sleep. Do not claim real OS delivery from pure rule tests.
- History starts when collection is enabled; do not claim reconstructed past quota,
  statistical confidence, verified fixed-cycle semantics or real Claude subscription acceptance.
