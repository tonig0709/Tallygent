# Native language support

Tallygent v0.8.0 adds **English (`en`)**, **简体中文 (`zh-Hans`)**, and **繁體中文 (`zh-Hant`)**.

## Selection

The app uses native macOS bundle localization, following the user's preferred language list. A language explicitly selected for Tallygent in System Settings takes precedence. Unsupported languages fall back to English. Relaunch the app after changing its language; no global language preference is changed by Tallygent.

The README's language links are manual document navigation, not an app-language switch. Date, time, and number formatting continues to use the user's system region; language and region are separate preferences.

## Scope and compatibility

Translations cover the dashboard, menu bar, three desktop panel sizes, glass/chart settings, Insights, Planner presentation, notifications, accessibility text, and app-owned error messages. Provider names, model identifiers, user-entered tasks and upstream diagnostic messages are not translated. Existing saved task descriptions and historical recommendation text are retained as entered/recorded; changing language does not rewrite user data.

The app keeps its bundle ID, database schema, preference keys, provider protocol values, panel ownership, collection cadence, and glass rendering. `Localizable.strings` uses stable source keys. Dynamic display strings use the same Foundation bundle lookup and locale-aware formatting, not a remote translation service or a custom language-selection engine.

Planner applies native Traditional-to-Simplified normalization only to its transient keyword-matching copy, so existing architecture/security terms also work with Traditional Chinese spelling. Original task input is not rewritten or saved by this conversion; the classifier remains a transparent heuristic, not a semantic language model.

## Contributor workflow

1. Add a stable display key to all three `Resources/*.lproj/Localizable.strings` tables.
2. Use native SwiftUI localized literals for static UI; use `L` for String-based presentation and `LF` for typed formatted messages. Never translate persisted raw values, selectors, account data, or model IDs.
3. Keep format arguments type-compatible, including `%lld`, `%@`, and escaped literal `%%`. Dates/numbers must retain native formatters.
4. Run `sh scripts/check-localization.sh`. The release gate also compares the packaged tables against source.
5. Isolated native UI probes launch separate localized bundles for all three languages, checking actual bundle selection and semantic label geometry. Preserve the narrow/threshold widths, light/dark, large fonts, same-window restoration, negative controls, non-black rendering, and live-data tests.
6. Complete the real-desktop smoke test in `RELEASE_CHECKLIST.md` before publishing. Native CI rendering is not proof of desktop dragging, hover or compositor behavior.

## References

- [Stats localization resources](https://github.com/exelban/stats/tree/master/Stats/Supporting%20Files): native language resource folders, including `en`, `zh-Hans`, and `zh-Hant`.
- [Apple localization documentation](https://developer.apple.com/localization/): native localized resources and language-aware formatting.
