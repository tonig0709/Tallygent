#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tallygent-insights.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$probe_dir/module-cache" \
    Gate/UsageInsightsProbe.swift Shared/Localization.swift Shared/UsageInsights.swift Shared/ObservationHistory.swift \
    Shared/ClaudeStatusline.swift Shared/UsageSnapshot.swift \
    -framework Foundation -framework CryptoKit -lsqlite3 -o "$probe_dir/insights-probe"
"$probe_dir/insights-probe"
