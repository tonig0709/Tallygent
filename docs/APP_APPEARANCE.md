# Main app appearance — build 64

App Appearance is available from the workspace header or the native Settings
command (⌘,). It changes Monitor, Insights, Planner and this settings window.
It does not redesign the desktop panel or its glass settings.

- Follow System, Light or Dark is scoped to app content. Automatic panel
  appearance and glass previews retain their original system appearance.
- Ocean, Iris, Mint and Rose change decorative accents. Quota green/orange/red,
  warnings and chart data colors keep their existing meanings.
- Primary buttons offer two-tone gradients or solid fills. Secondary actions
  stay quieter. Press and hover are short, interruptible native transitions.
- Comfortable/Compact changes app padding, section gaps and control spacing.
  Content corners range from 8–16pt; these are not desktop panel corners.
- Motion Intensity controls decorative button response, with 0 disabling it
  and preview navigation animation. Reduce Motion is always respected.
- Quiet, Colorful and Vivid are editable presets, not separate rendering paths.

The single local preference `appUI.appearance.v1` is separate from glass,
provider, observation and Planner data. Restoring appearance defaults writes
only this key. Invalid data falls back to defaults; numeric inputs are bounded.
No new dependency, WebView, timer, telemetry or account access is introduced.

## Checks

`scripts/check-app-appearance.sh` checks persistence, all option combinations,
numeric bounds, invalid data, contrast over the complete gradient/hover range,
and source isolation in both directions. Known-bad contrast is rejected.

The native desktop gate additionally checks live appearance updates and settings
layouts in the isolated CI user. The existing language, theme, large-font,
resize/restoration, non-black, live-data, panel ownership and package checks
remain mandatory. Passing a headless gate does not replace actual pointer,
keyboard and compositor checks on a user's Mac.
