# Codex Quota release invariant

Before creating a version tag, DMG, or GitHub Release:

1. The current product is panel-only, as requested by the user. Build the app
   with full Xcode for both `arm64` and `x86_64`. Never package a `swiftc`-assembled
   app, an old WidgetKit extension, or old AppIntent metadata.
2. Sign the app, package the exact signed app, then run:

   ```sh
   CODEX_QUOTA_ISOLATED_REGISTRY=1 \
     ./scripts/release-preflight.sh "/path/to/Codex Quota.app" "/path/to/Codex-Quota.dmg"
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
