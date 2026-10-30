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
# Published emits in willSet; recomputing from its old stored value lags one receipt.
grep -Fq 'recommend(report: report)' App/PlannerView.swift
grep -Fq '(report ?? server.insights.panelReport).windows' App/PlannerView.swift
sh scripts/check-planner-benchmark.sh Shared/Planner.swift "$probe_dir/policy-comparison.json"
