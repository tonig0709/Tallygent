#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-quota-providers.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$probe_dir/module-cache" \
    Gate/MultiProviderProbe.swift Shared/UsageSnapshot.swift Shared/ClaudeStatusline.swift \
    App/ClaudeBridgeSetup.swift App/QuotaMonitor.swift \
    -framework Foundation -framework Combine -framework CryptoKit \
    -o "$probe_dir/provider-probe"
"$probe_dir/provider-probe" "$probe_dir"
# Time-only expiry must invalidate an otherwise unchanged SwiftUI child input.
grep -Fq '.id(server.service == .claude ? server.snapshot.claudePresentationKey() : "codex")' App/DashboardView.swift
grep -Fq '.id(server.service == .claude ? server.snapshot.claudePresentationKey() : "codex")' App/DesktopGlassPanelView.swift
