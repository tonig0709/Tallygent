# Release checklist

Every push and pull request, every version tag, and the final signed release
payload run the same gate:

```sh
CODEX_QUOTA_ISOLATED_REGISTRY=1 \
  ./scripts/release-preflight.sh "/path/to/Codex Quota.app" "/path/to/Codex-Quota.dmg"
```

The full gate intentionally mutates the current user's PlugInKit registry. Run
it only in a clean CI user with no existing Codex Quota registration. Local
development can run the non-destructive parser and render checks with
`swift run quota-self-check`.

The gate blocks release unless all of these pass:

- **Widget discovery:** the gate seeds an enabled lower-version/build registration,
  launches the installed candidate without registering it from the script, and
  requires the App to remove only the verified obsolete extension path and elect
  exactly one enabled current extension. The newer-build decision branch is
  checked to return before every app-controlled registration write; macOS may
  independently elect an App when its executable is launched. AppIntent metadata, both
  sizes, assets, ATS, and signed network entitlements are checked on the built
  extension.
- **No black or blank widget:** SwiftUI renders small/large × light/dark into
  all eight family × appearance × opacity-boundary bitmaps. Each result is
  compared with the same empty glass background, including separate quota and
  trend regions; a solid-black negative control must fail the same readable-
  contrast predicate, so a visible border or black surface cannot pass.
- **Live synchronization:** a deterministic fake Codex app-server proves the
  full initialize/account/rate-limit/usage path, a deliberately delayed trend
  response plus a refresh notification while work is in flight, forced port-
  collision recovery, candidate process ownership of the bridge, and A→B→C
  refresh of 5h, weekly, and seven-day data. C deliberately omits trend data to
  prove quota liveness without erasing B's valid trend. An unchanged follow-up
  proves polling cannot invalidate the widget editor, and configuration
  snapshots use the immediate cache instead of waiting on the live bridge. The
  production `CodexQuotaProvider` is compiled into the probe and executed
  against A, B, and C, including its default HTTP endpoint, cache prevention,
  unexpected-route rejection, and identity removal.
- **Update safety:** the bundle build is greater than every existing release
  tag; temporary DMG/build copies cannot run registration repair or occupy
  port 48193.
- **Release artifact:** app/widget signatures and `arm64` + `x86_64` slices are
  valid. After any notarization/stapling mutation, the DMG is verified and its
  App paths, link targets, permission modes, and file bytes must equal the exact
  candidate that passed the gate. Both mounted executables and the two-
  architecture slices are checked again.

The push/PR workflow and the tag workflow's required preflight both run this
behavioral gate on macOS 14, macOS 15, and macOS 26. Universal slices are built
and inspected on every runner; runtime behavior is executed on each runner's native
CPU architecture.

## Final desktop smoke test

The tag workflow now creates a **draft** Release. Automated checks use Apple's
registration database and off-screen rendering, but a headless GitHub runner
cannot click the widget gallery or inspect the live desktop compositor. Before
publishing that draft:

- [ ] Remove every existing **Codex Quota** desktop widget and prior test build,
      drag the new app into **Applications**, eject the DMG, and launch only
      that copy.
- [ ] Open **Edit Widgets**, search **Codex Quota**, and add both **小型** and
      **大型**.
- [ ] Confirm neither size is black or blank in light and dark appearance.
- [ ] Edit both sizes, enter opacity values `0.35`, `0.44`, and `1.00`, and
      confirm the configuration sheet remains loaded after each change.
- [ ] In dark appearance over a colorful wallpaper, confirm `0.35` visibly
      transmits the wallpaper's colors/details while text stays readable, and
      `1.00` remains uniformly near-black. A gray opaque `0.35` is a failure.
- [ ] Confirm the small widget shows separate 5h and weekly rings and the large
      widget shows 5h above weekly quota.
- [ ] Generate new Codex usage and confirm quota plus seven-day trend update
      within one minute.
- [ ] Only after every item passes, publish the draft Release on GitHub.
- [ ] Open the desktop glass panel while Finder is active; drag its top strip,
      verify the window moves, then close using X. Reopen it, confirm settings
      still respond, and close using the menu-bar action. Closing the panel must
      not quit the App or stop widget synchronization.
