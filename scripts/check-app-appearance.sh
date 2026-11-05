#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tallygent-app-appearance.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$probe_dir/module-cache" \
    Shared/AppUISettings.swift Gate/AppAppearanceProbe.swift \
    -framework Foundation -o "$probe_dir/app-appearance-probe"
"$probe_dir/app-appearance-probe"
# Main-app styling must never become a second owner of panel/provider state.
ruby - <<'RUBY'
paths = %w[Shared/AppUISettings.swift App/AppAppearanceView.swift]
forbidden = /GlassSettingKeys|GlassSettingsSnapshot|PanelChartSource|SnapshotStore|UsageSnapshot|CodexAppServer|QuotaMonitor|DesktopPanelController|Timer\s*[.(]|Task\s*[{.(]|WKWebView|removePersistentDomain|removeObject\(forKey:/
paths.each do |path|
  abort "App appearance crossed its isolation boundary: #{path}" if File.read(path).match?(forbidden)
end
%w[App/DesktopGlassPanelView.swift App/GlassSettingsView.swift Shared/QuotaWidgetView.swift
   Shared/UsageSnapshot.swift App/CodexAppServer.swift].each do |path|
  abort "Panel/provider state now depends on main-app styling: #{path}" if File.read(path).match?(/AppUISettings|appUISettings|AppActionStyle|AppAppearanceSettingsView/)
end
view = File.read('App/AppAppearanceView.swift')
abort 'Appearance settings lost their dedicated persistence key' unless view.include?('@AppStorage(AppUISettings.defaultsKey)')
abort 'Appearance reset no longer writes only main-app defaults' unless view.include?('AppUISettings.standard.encoded')
abort 'Primary button sheen exceeds the tested contrast-safe cap' unless view.include?('.white.opacity(0.07 * ui.motionIntensity)')
abort 'Pressed opacity washes out primary labels in the light theme' if view.match?(/configuration\.isPressed\s*\?\s*0\.85/)
dashboard = File.read('App/DashboardView.swift')
abort 'Main-app appearance now changes the entire window material context' if dashboard.include?('.preferredColorScheme(')
abort 'Main-app appearance is not scoped to app content' unless dashboard.include?('.environment(\.colorScheme, appUI.colorScheme ?? colorScheme)')
abort 'Panel preview/settings no longer preserve their original system color scheme' unless dashboard.scan('.environment(\.colorScheme, colorScheme)').length >= 3
puts 'App appearance source isolation: dedicated key, no panel/provider dependency, no timers or WebView: PASS'
RUBY
