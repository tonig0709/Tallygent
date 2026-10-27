#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "${CODEX_QUOTA_ISOLATED_REGISTRY:-}" != 1 ]; then
    echo 'Desktop runtime probes require an isolated CI user; do not run against personal app settings.' >&2
    exit 1
fi
probe_dir=$(mktemp -d)
trap 'rm -f "$probe_dir/panel-probe" "$probe_dir/history.sqlite" "$probe_dir/history.sqlite-journal"; rmdir "$probe_dir"' EXIT
set --
if [ -f App/GlassSettingsView.swift ]; then
    set -- -D CODEX_QUOTA_ADVANCED_GLASS App/GlassSettingsView.swift
fi
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    "$@" Gate/DesktopPanelProbe.swift App/AdaptiveLayout.swift App/DesktopGlassPanelView.swift App/DashboardView.swift \
    App/PlannerView.swift App/PlannerStore.swift Shared/Planner.swift Shared/ClaudeStatusline.swift \
    App/InsightsView.swift App/InsightsStore.swift Shared/ObservationHistory.swift Shared/UsageInsights.swift \
    Shared/QuotaWidgetView.swift Shared/UsageSnapshot.swift Shared/PanelTrend.swift Shared/PanelTrendView.swift \
    -lsqlite3 -framework UserNotifications -framework CryptoKit -framework AppKit -framework Charts -framework SwiftUI \
    -o "$probe_dir/panel-probe"
if [ -n "${TALLYGENT_UI_CHECKS:-}" ]; then
    mkdir -p "$TALLYGENT_UI_CHECKS"
    /usr/bin/ditto "$probe_dir/panel-probe" "$TALLYGENT_UI_CHECKS/panel-probe"
fi
TALLYGENT_HISTORY_DB="$probe_dir/history.sqlite" "$probe_dir/panel-probe"
# Choice labels must not share a fixed-width native Picker allocation again.
if grep -Eq '\.frame\(width:[[:space:]]*(320|340)(\.0)?[[:space:]]*[,)]' App/DashboardView.swift ||
   grep -Eq '\.frame\(width:[[:space:]]*180(\.0)?[[:space:]]*[,)]' App/PlannerView.swift; then
    echo 'A previously broken fixed-width labelled native Picker allocation has returned' >&2
    exit 1
fi
awk '
    /Picker\(title, selection: selection\)/ {
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
grep -q 'Button("关闭桌面玻璃面板")' App/CodexQuotaApp.swift
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
if grep -Eq 'import WidgetKit|WidgetCenter|WidgetRepairService' App/*.swift; then
    echo 'Panel-only app still invokes WidgetKit' >&2
    exit 1
fi
