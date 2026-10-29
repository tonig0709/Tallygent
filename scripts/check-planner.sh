#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tallygent-planner.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$probe_dir/module-cache" \
    Gate/PlannerProbe.swift Shared/Localization.swift Shared/Planner.swift Shared/ClaudeStatusline.swift \
    Shared/ObservationHistory.swift Shared/UsageSnapshot.swift App/PlannerStore.swift \
    -lsqlite3 -framework Foundation -framework Combine -framework CryptoKit -o "$probe_dir/planner-probe"
"$probe_dir/planner-probe" "$probe_dir"
