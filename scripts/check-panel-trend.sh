#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tallygent-panel-trend.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$probe_dir/module-cache" \
    Gate/PanelTrendProbe.swift Shared/Localization.swift Shared/PanelTrend.swift Shared/UsageInsights.swift Shared/ObservationHistory.swift \
    Shared/ClaudeStatusline.swift Shared/UsageSnapshot.swift App/InsightsStore.swift \
    -framework Foundation -framework CryptoKit -framework Combine -framework UserNotifications -lsqlite3 \
    -o "$probe_dir/panel-trend-probe"
"$probe_dir/panel-trend-probe" "$probe_dir"
for source in Shared/PanelTrendView.swift App/InsightsView.swift; do
    grep -Fq 'AxisValueLabel(format: UsageChartAxis.remainingPercent)' "$source" || {
        echo "Quota chart lost its explicit percentage axis: $source" >&2; exit 1;
    }
    grep -Fq 'UsageChartAxis.labelAnchorX(' "$source"
    grep -Fq 'collisionResolution: .greedy' "$source"
done
grep -Fq 'Text(L("Token（百万）"))' Shared/QuotaWidgetView.swift
grep -Fq 'Text(L("日期（月/日）"))' Shared/QuotaWidgetView.swift
