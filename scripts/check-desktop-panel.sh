#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "${CODEX_QUOTA_ISOLATED_REGISTRY:-}" != 1 ]; then
    echo 'Desktop runtime probes require an isolated CI user; do not run against personal app settings.' >&2
    exit 1
fi
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tallygent-desktop.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
probe_app="$probe_dir/Tallygent Localization Gate.app"
probe_executable="$probe_app/Contents/MacOS/panel-probe"
mkdir -p "$probe_app/Contents/MacOS" "$probe_app/Contents/Resources"
# Use a genuine native bundle so SwiftUI and Foundation both resolve AppleLanguages.
# Merely changing SwiftUI's locale environment does not localize dynamic String values.
/usr/bin/plutil -create xml1 "$probe_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "dev.tallygent.localization-gate.$$" "$probe_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string panel-probe "$probe_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$probe_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleDevelopmentRegion -string en "$probe_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleLocalizations -json '["en","zh-Hans","zh-Hant"]' "$probe_app/Contents/Info.plist"
for language in en zh-Hans zh-Hant; do
    /usr/bin/ditto "Resources/$language.lproj" "$probe_app/Contents/Resources/$language.lproj"
done
set --
if [ -f App/GlassSettingsView.swift ]; then
    set -- -D CODEX_QUOTA_ADVANCED_GLASS App/GlassSettingsView.swift
fi
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    "$@" Gate/DesktopPanelProbe.swift App/AdaptiveLayout.swift App/DesktopGlassPanelView.swift App/DashboardView.swift \
    App/PlannerView.swift App/PlannerStore.swift Shared/Planner.swift Shared/ClaudeStatusline.swift \
    App/InsightsView.swift App/InsightsStore.swift Shared/ObservationHistory.swift Shared/UsageInsights.swift \
    Shared/QuotaWidgetView.swift Shared/UsageSnapshot.swift Shared/PanelTrend.swift Shared/PanelTrendView.swift Shared/Localization.swift \
    -lsqlite3 -framework UserNotifications -framework CryptoKit -framework AppKit -framework Charts -framework SwiftUI \
    -o "$probe_executable"
codesign --force --sign - "$probe_app"
if [ -n "${TALLYGENT_UI_CHECKS:-}" ]; then
    mkdir -p "$TALLYGENT_UI_CHECKS"
    /usr/bin/ditto "$probe_executable" "$TALLYGENT_UI_CHECKS/panel-probe"
fi
# Run unrelated mouse/live/window behavior once. Each process still performs the
# complete semantic-label/theme/font/resize matrix in its actual bundle language.
TALLYGENT_PROBE_LANGUAGE=zh-Hans TALLYGENT_HISTORY_DB="$probe_dir/history-zh-Hans.sqlite" \
    "$probe_executable" -AppleLanguages '("zh-Hans")' -AppleLocale zh_CN
for language in en zh-Hant; do
    locale=en_US
    [ "$language" != zh-Hant ] || locale=zh_TW
    TALLYGENT_PROBE_LANGUAGE="$language" TALLYGENT_LAYOUT_ONLY=1 \
        TALLYGENT_HISTORY_DB="$probe_dir/history-$language.sqlite" \
        "$probe_executable" -AppleLanguages "(\"$language\")" -AppleLocale "$locale"
done
# Choice labels must not share a fixed-width native Picker allocation again.
if grep -Eq '\.frame\(width:[[:space:]]*(320|340)(\.0)?[[:space:]]*[,)]' App/DashboardView.swift ||
   grep -Eq '\.frame\(width:[[:space:]]*180(\.0)?[[:space:]]*[,)]' App/PlannerView.swift; then
    echo 'A previously broken fixed-width labelled native Picker allocation has returned' >&2
    exit 1
fi
awk '
    /Picker\((L\()?title\)?, selection: selection\)/ {
        count++
        getline
        if ($0 !~ /\.labelsHidden\(\)/) exit 1
    }
    END { if (count < 2) exit 1 }
' App/AdaptiveLayout.swift || {
    echo 'Adaptive native choices must hide implicit labels and preserve separate visible titles' >&2
    exit 1
}
# Actual WindowServer dragging/closing still needs the desktop smoke test.
grep -q 'Button(action: closePanel)' App/DesktopGlassPanelView.swift
grep -q 'DesktopPanelController.shared.close()' App/DesktopGlassPanelView.swift
grep -Eq 'Button\((L\()?"关闭桌面玻璃面板"' App/CodexQuotaApp.swift
grep -q 'window.styleMask.remove(.titled)' App/DesktopGlassPanelView.swift
grep -q '.scrollTargetBehavior(.viewAligned)' App/DashboardView.swift
grep -Fq '.accessibilityHidden(section != .planner)' App/DashboardView.swift
if grep -Fq 'if section == .planner {' App/DashboardView.swift; then
    echo 'Workspace branching destroys the unsaved in-memory Planner draft' >&2
    exit 1
fi
grep -Fq 'TimelineView(.periodic(from: .now, by: 1))' Shared/QuotaWidgetView.swift
grep -Fq 'Text(Date(), format: .dateTime.hour().minute().second())' Shared/QuotaWidgetView.swift
if grep -Fq 'Text(snapshot.updatedAt, style: .time)' Shared/QuotaWidgetView.swift; then
    echo 'Panel clock is frozen to the account snapshot timestamp' >&2
    exit 1
fi
grep -q 'QuotaPanelContent(mode: mode, snapshot: panelSnapshot' App/DesktopGlassPanelView.swift
grep -Fq 'DesktopPanelDragRegion(cornerRadius: cornerRadius)' App/DesktopGlassPanelView.swift
grep -Fq 'GlassOptics(blurAmount: blurAmount, dispersion: dispersion)' App/DesktopGlassPanelView.swift
for source in Shared/QuotaWidgetView.swift App/DesktopGlassPanelView.swift; do
    grep -Fq 'GlassRimHighlight(' "$source" || {
        echo "Glass surface bypasses the checked edge-following highlight: $source" >&2
        exit 1
    }
    if grep -Fq '42 + elasticity * 118' "$source"; then
        echo "Detached blurred highlight capsule has returned: $source" >&2
        exit 1
    fi
done
# Check consumption as well as declaration: an unused helper must not satisfy the gate.
grep -Fq '.overlay(alignment: .topLeading) { elasticHighlight }' Shared/QuotaWidgetView.swift
awk '
    /private struct DesktopGlassSurface: View/ { surface = 1 }
    surface && /var body: some View/ { body = 1 }
    body && /^[[:space:]]*elasticHighlight[[:space:]]*$/ { found = 1 }
    body && /private var frostColor/ { body = 0; surface = 0 }
    END { if (!found) exit 1 }
' App/DesktopGlassPanelView.swift || {
    echo 'Desktop glass body no longer renders the checked rim highlight' >&2
    exit 1
}
if grep -Eq 'import WidgetKit|WidgetCenter|WidgetRepairService' App/*.swift; then
    echo 'Panel-only app still invokes WidgetKit' >&2
    exit 1
fi
