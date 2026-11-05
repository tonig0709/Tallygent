#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tallygent-quota-curve.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$probe_dir/module-cache" \
    Gate/QuotaCurveProbe.swift Shared/QuotaCurve.swift Shared/UsageInsights.swift \
    Shared/ObservationHistory.swift Shared/ClaudeStatusline.swift Shared/UsageSnapshot.swift Shared/Localization.swift \
    -framework Foundation -framework CryptoKit -lsqlite3 -o "$probe_dir/quota-curve-probe"
"$probe_dir/quota-curve-probe"
