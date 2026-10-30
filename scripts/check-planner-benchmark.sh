#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Optional first argument pins an old Planner.swift snapshot for before/after policy comparisons.
# The probe uses only the pre-upgrade public API and writes no user history or settings.
planner_source=${1:-Shared/Planner.swift}
report=${2:-outputs/planner-adaptive/current.json}
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tallygent-planner-benchmark.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
mkdir -p "$(dirname "$report")"
xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$probe_dir/module-cache" \
    Gate/PlannerBenchmark.swift Shared/Localization.swift "$planner_source" Shared/ClaudeStatusline.swift \
    Shared/ObservationHistory.swift Shared/UsageSnapshot.swift \
    -lsqlite3 -framework Foundation -framework CryptoKit -o "$probe_dir/planner-benchmark"
if [ "$planner_source" = Shared/Planner.swift ]; then
    "$probe_dir/planner-benchmark" "$report" --enforce-policy
else
    "$probe_dir/planner-benchmark" "$report"
fi
