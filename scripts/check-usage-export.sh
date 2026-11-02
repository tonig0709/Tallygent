#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tallygent-export.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$probe_dir/module-cache" \
    Gate/UsageExportProbe.swift Shared/UsageExport.swift Shared/UsageInsights.swift Shared/ObservationHistory.swift \
    Shared/ClaudeStatusline.swift Shared/UsageSnapshot.swift Shared/Localization.swift \
    -framework Foundation -framework CryptoKit -lsqlite3 -o "$probe_dir/export-probe"
"$probe_dir/export-probe"
# Report conversion must not block the history actor or main-thread UI.
grep -Fq 'Task.detached(priority: .utility)' App/InsightsStore.swift
grep -Fq 'if format == .json { return json }' App/InsightsStore.swift
grep -Fq '.disabled(isPreparingExport || showsExporter)' App/InsightsView.swift
