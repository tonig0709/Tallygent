# README screenshot provenance

The README gallery retains native UI snapshots of **Tallygent v0.7.1 / build 52**, using deterministic demo data rather than a personal account. They predate v0.8.0 localization and are visual references, not demonstrations of every current translated label.

- Source: [`142091a94d8ab41893d5bc754d1b9bea2507095f`](https://github.com/tonig0709/Tallygent/commit/142091a94d8ab41893d5bc754d1b9bea2507095f), also tagged `v0.7.1`.
- Capture run: [isolated macOS CI 40524844261](https://github.com/tonig0709/Tallygent/actions/runs/40524844261), `Tallygent-ui-checks` artifact on macOS 26.
- The existing native regression probes render the product's SwiftUI views. These are not AI-generated designs or recreated HTML mockups. They are **not screenshots of a user's installed desktop**.
- UI labels follow the capture environment and are primarily Chinese; this does not imply that every application label is localized into English.
- Actual wallpaper sampling, application-bundle service icons, dragging, and pointer highlights can differ from standalone native rendering. These images do not substitute for the real-desktop acceptance checklist.
- The screenshots use a known published version, not the particle experiment. Later releases can refine axis labels or translate copy without changing this gallery's recorded provenance.
- Files are copied unchanged from the capture artifact. No account email, credentials, private project names, or user wallpaper are included.

| Repository image | Original artifact filename | Dimensions |
| --- | --- | --- |
| `screenshots/panel-12h-dark.png` | `panel-trend-12h-line-dark.png` | 680 × 300 |
| `screenshots/panel-24h-light.png` | `panel-trend-24h-bars-light.png` | 680 × 300 |
| `screenshots/insights.png` | `insights-1120.png` | 1024 × 642 |
| `screenshots/glass-settings.png` | `panel-settings-compact.png` | 360 × 640 |

SHA-256 of the committed images:

```text
22efc0eef01a788ad64b95bee6dbd3e02aae783eeef1ca1d5472e9aea612e302  panel-12h-dark.png
b0bbb0f0bd242e1e1885dac17807939542f6d06edaadf0463eead4dd8868527b  panel-24h-light.png
6bad31c4079c80ef79945a7085d9f6bdd0d5d42c63de8fa0bd05ed5aa9b7c4b0  insights.png
eaedc56c178361e5755334a7622bdd7095f2bbc2312884cc6e558e415c0a4c4a  glass-settings.png
```

When refreshing this gallery, use a known source version and sanitized demo data; record the new run and hashes here. Do not illustrate stable downloads with unreleased functionality or claim that CI renders prove desktop-compositor behavior.
