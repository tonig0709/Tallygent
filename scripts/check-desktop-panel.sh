#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d)
trap 'rm -f "$probe_dir/panel-probe"; rmdir "$probe_dir"' EXIT
set --
if [ -f App/GlassSettingsView.swift ]; then
    set -- -D CODEX_QUOTA_ADVANCED_GLASS App/GlassSettingsView.swift
fi
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    "$@" Gate/DesktopPanelProbe.swift App/DesktopGlassPanelView.swift App/DashboardView.swift \
    Shared/QuotaWidgetView.swift Shared/UsageSnapshot.swift \
    -framework AppKit -framework Charts -framework SwiftUI \
    -o "$probe_dir/panel-probe"
"$probe_dir/panel-probe"
# Actual WindowServer dragging/closing still needs the desktop smoke test.
grep -q 'Button(action: closePanel)' App/DesktopGlassPanelView.swift
grep -q 'DesktopPanelController.shared.close()' App/DesktopGlassPanelView.swift
grep -q 'Button("关闭桌面玻璃面板")' App/CodexQuotaApp.swift
grep -q 'window.styleMask.remove(.titled)' App/DesktopGlassPanelView.swift
grep -q '.scrollTargetBehavior(.viewAligned)' App/DashboardView.swift
grep -Fq 'TimelineView(.periodic(from: .now, by: 1))' Shared/QuotaWidgetView.swift
grep -Fq 'Text(Date(), format: .dateTime.hour().minute().second())' Shared/QuotaWidgetView.swift
if grep -Fq 'Text(snapshot.updatedAt, style: .time)' Shared/QuotaWidgetView.swift; then
    echo 'Panel clock is frozen to the account snapshot timestamp' >&2
    exit 1
fi
grep -q 'QuotaPanelContent(mode: mode, snapshot: panelSnapshot' App/DesktopGlassPanelView.swift
grep -Fq 'DesktopPanelDragRegion(cornerRadius: cornerRadius)' App/DesktopGlassPanelView.swift
grep -Fq 'GlassOptics(blurAmount: blurAmount, dispersion: dispersion)' App/DesktopGlassPanelView.swift
if grep -Eq 'import WidgetKit|WidgetCenter|WidgetRepairService' App/*.swift; then
    echo 'Panel-only app still invokes WidgetKit' >&2
    exit 1
fi
