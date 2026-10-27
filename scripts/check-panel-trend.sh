#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tallygent-panel-trend.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$probe_dir/module-cache" \
    Gate/PanelTrendProbe.swift Shared/PanelTrend.swift Shared/UsageInsights.swift Shared/ObservationHistory.swift \
    Shared/ClaudeStatusline.swift Shared/UsageSnapshot.swift App/InsightsStore.swift \
    -framework Foundation -framework CryptoKit -framework Combine -framework UserNotifications -lsqlite3 \
    -o "$probe_dir/panel-trend-probe"
"$probe_dir/panel-trend-probe" "$probe_dir"
