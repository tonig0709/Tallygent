#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tallygent-history.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$probe_dir/module-cache" \
    Gate/ObservationHistoryProbe.swift Shared/UsageSnapshot.swift Shared/ClaudeStatusline.swift Shared/ObservationHistory.swift \
    -framework Foundation -framework CryptoKit -lsqlite3 -o "$probe_dir/history-probe"
"$probe_dir/history-probe" "$probe_dir"
