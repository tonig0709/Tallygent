#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$root"

app_input="${1:-}"
if [ -z "$app_input" ] || [ ! -d "$app_input" ]; then
    echo "Usage: $0 <Codex Quota.app> [Codex-Quota.dmg]" >&2
    exit 64
fi
dmg_input="${2:-}"
[ -z "$dmg_input" ] || [ -f "$dmg_input" ] || { echo "DMG not found: $dmg_input" >&2; exit 66; }

app="$(cd "$(dirname "$app_input")" && pwd -P)/$(basename "$app_input")"
widget="$app/Contents/PlugIns/CodexQuotaWidgetExtension.appex"
app_executable="$app/Contents/MacOS/Codex Quota"
widget_executable="$widget/Contents/MacOS/CodexQuotaWidgetExtension"
app_info="$app/Contents/Info.plist"
widget_info="$widget/Contents/Info.plist"
app_metadata="$app/Contents/Resources/Metadata.appintents/extract.actionsdata"
widget_metadata="$widget/Contents/Resources/Metadata.appintents/extract.actionsdata"
widget_identifier="dev.codexquota.app.widget"
launch_services_tool="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/codex-quota-release.XXXXXX")"
app_pid=""
blocker_pid=""
translocated_pid=""
translocation_mount=""
payload_mount=""
runtime_app=""
runtime_widget=""
stale_app=""
stale_widget=""

cleanup() {
    if [ -n "$blocker_pid" ]; then kill "$blocker_pid" 2>/dev/null || true; fi
    if [ -n "$app_pid" ]; then
        pkill -TERM -P "$app_pid" 2>/dev/null || true
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    if [ -n "$translocated_pid" ]; then kill "$translocated_pid" 2>/dev/null || true; fi
    if [ -n "$runtime_widget" ]; then /usr/bin/pluginkit -r "$runtime_widget" >/dev/null 2>&1 || true; fi
    if [ -n "$stale_widget" ]; then /usr/bin/pluginkit -r "$stale_widget" >/dev/null 2>&1 || true; fi
    if [ -n "$translocation_mount" ]; then hdiutil detach "$translocation_mount" -force >/dev/null 2>&1 || true; fi
    if [ -n "$payload_mount" ]; then hdiutil detach "$payload_mount" -force >/dev/null 2>&1 || true; fi
    if [ -n "$runtime_app" ]; then "$launch_services_tool" -u "$runtime_app" >/dev/null 2>&1 || true; fi
    if [ -n "$stale_app" ]; then "$launch_services_tool" -u "$stale_app" >/dev/null 2>&1 || true; fi
    if [ -n "$runtime_app" ] && [ -e "$runtime_app" ]; then rm -rf "$runtime_app"; fi
    if [ -n "$stale_app" ] && [ -e "$stale_app" ]; then rm -rf "$stale_app"; fi
    rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

section() { printf '\n==> %s\n' "$1"; }
pass() { printf '    PASS  %s\n' "$1"; }
fail() {
    printf '    FAIL  %s\n' "$1" >&2
    if [ -s "$tmp/app.log" ]; then tail -80 "$tmp/app.log" >&2; fi
    if [ -s "$tmp/pluginkit.txt" ]; then cat "$tmp/pluginkit.txt" >&2; fi
    exit 1
}
require_text() {
    grep -Fq -- "$1" "$2" || fail "$3"
}
forbid_text() {
    ! grep -Fq -- "$1" "$2" || fail "$3"
}
registration_count() {
    /usr/bin/pluginkit -m -A -v -i "$widget_identifier" |
        awk -v id="$widget_identifier" 'index($0, id "(") { count++ } END { print count + 0 }'
}
wait_for_empty_registry() {
    local stable=0 count
    for _ in {1..40}; do
        count="$(registration_count)"
        if [ "$count" -eq 0 ]; then
            stable=$((stable + 1))
            [ "$stable" -ge 2 ] && return 0
        else
            stable=0
        fi
        sleep 0.25
    done
    return 1
}
plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}
bundle_digest() {
    python3 - "$1" <<'PY'
import hashlib
import os
import sys

root = os.path.abspath(sys.argv[1])
digest = hashlib.sha256()
root_mode = os.stat(root, follow_symlinks=False).st_mode & 0o7777
digest.update(f"root-mode:{root_mode:o}".encode() + b"\0")
for directory, subdirectories, files in os.walk(root, topdown=True, followlinks=False):
    subdirectories.sort()
    files.sort()
    for name in subdirectories + files:
        path = os.path.join(directory, name)
        relative = os.path.relpath(path, root).encode()
        digest.update(relative + b"\0")
        mode = os.stat(path, follow_symlinks=False).st_mode & 0o7777
        digest.update(f"{mode:o}".encode() + b"\0")
        if os.path.islink(path):
            digest.update(b"link\0" + os.readlink(path).encode() + b"\0")
        elif os.path.isfile(path):
            digest.update(b"file\0")
            with open(path, "rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
print(digest.hexdigest())
PY
}

section "First-principles release topology"
ruby -r yaml - .github/workflows/release.yml .github/workflows/test.yml <<'RUBY' || fail "workflow topology is not enforceable"
release = YAML.load_file(ARGV[0]).fetch("jobs")
test = YAML.load_file(ARGV[1]).fetch("jobs")
raise "release must depend on preflight" unless release.fetch("release").fetch("needs") == "preflight"
expected_os = ["macos-14", "macos-15", "macos-26"]
release_os = release.fetch("preflight").fetch("strategy").fetch("matrix").fetch("os")
test_os = test.fetch("release-gate").fetch("strategy").fetch("matrix").fetch("os")
raise "release preflight OS matrix is incomplete" unless release_os == expected_os
raise "test OS matrix is incomplete" unless test_os == expected_os

release_steps = release.fetch("release").fetch("steps")
release_names = release_steps.map { |step| step["name"] }.compact
required = [
  "Package app",
  "Notarize and staple DMG",
  "Run release bug gate on final payload",
  "Create checksum",
  "Create draft GitHub Release"
]
indexes = required.map { |name| release_names.index(name) or raise "missing release step: #{name}" }
raise "release steps are out of order" unless indexes == indexes.sort && indexes.uniq.length == indexes.length

create_step = release_steps.find { |step| step["name"] == "Create draft GitHub Release" }
create_run = create_step.fetch("run")
raise "release command is missing" unless create_run.lines.any? { |line| line.match?(/^\s*gh release create\b/) }
raise "release is not draft" unless create_run.lines.any? { |line| line.match?(/^\s*--draft(?:\s|\\|$)/) }

test_steps = test.fetch("release-gate").fetch("steps")
test_names = test_steps.map { |step| step["name"] }.compact
package_index = test_names.index("Package test DMG") or raise "missing test package step"
gate_index = test_names.index("Run release bug gate") or raise "missing test gate step"
raise "test gate runs before packaging" unless package_index < gate_index
RUBY
pass "the last mutable artifact is gated before a draft release can be created"

section "Source, parser, and visual render checks"
sh scripts/check-codex-discovery.sh
sh scripts/check-desktop-panel.sh
swift run quota-self-check
xcrun swiftc \
    -parse-as-library \
    -D CODEX_QUOTA_PROVIDER_PROBE \
    -target "$(uname -m)-apple-macos14.0" \
    Gate/WidgetProviderProbe.swift \
    Widget/CodexQuotaWidget.swift \
    Shared/AppearanceV3ConfigurationIntent.swift \
    Shared/QuotaWidgetView.swift \
    Shared/UsageSnapshot.swift \
    -framework AppIntents \
    -framework Charts \
    -framework SwiftUI \
    -framework WidgetKit \
    -o "$tmp/widget-provider-probe"
require_text 'SmallCodexQuotaWidget()' Widget/CodexQuotaWidget.swift "small widget is missing from WidgetBundle"
require_text 'LargeCodexQuotaWidget()' Widget/CodexQuotaWidget.swift "large widget is missing from WidgetBundle"
require_text '.supportedFamilies([.systemSmall])' Widget/CodexQuotaWidget.swift "small widget family is missing"
require_text '.supportedFamilies([.systemExtraLarge])' Widget/CodexQuotaWidget.swift "large widget family is missing"
require_text '.containerBackground(for: .widget)' Widget/CodexQuotaWidget.swift "widget container background is missing"
forbid_text '.fill(.ultraThinMaterial)' Shared/QuotaWidgetView.swift "legacy material flattens minimum dark glass to gray"
require_text '.codexWidgetSurface(' Widget/CodexQuotaWidget.swift "widget content is not attached to its glass surface"
require_text 'WidgetTransparentDarkSurface' Widget/CodexQuotaWidget.swift "transparent dark widget background is missing"
forbid_text '.glassEffect(' Widget/CodexQuotaWidget.swift "glassEffect on a WidgetKit snapshot can hide all foreground content"
require_text 'WidgetGlassOpacity.darkFilmOpacity' Shared/QuotaWidgetView.swift "adjustable dark glass film is missing"
require_text 'DesktopPanelController.shared.show(server: server)' App/CodexQuotaApp.swift "desktop glass panel entry is missing"
require_text 'DesktopGlassPanelView(server: server)' App/DesktopGlassPanelView.swift "desktop glass panel content is missing"
require_text 'NSVisualEffectView' App/DesktopGlassPanelView.swift "desktop panel lacks native wallpaper material"
require_text 'view.blendingMode = .behindWindow' App/DesktopGlassPanelView.swift "desktop panel cannot sample wallpaper behind its window"
require_text 'Slider(value: value' App/GlassSettingsView.swift "glass inspector lacks native live sliders"
require_text 'QuotaWidgetView(snapshot: panelSnapshot' App/DesktopGlassPanelView.swift "desktop panel does not reuse the widget information layout"
require_text '.inspector(isPresented:' App/DashboardView.swift "dashboard lacks the glass settings inspector"
require_text 'GlassSettingsView(compact: true' App/DesktopGlassPanelView.swift "desktop panel does not reuse glass settings"
require_text '.onContinuousHover(perform: updateHover)' App/DesktopGlassPanelView.swift "desktop glass lacks pointer-following feedback"
require_text 'accessibilityReduceMotion' App/DesktopGlassPanelView.swift "desktop glass motion lacks reduced-motion fallback"
require_text 'GlassSettingKeys.elasticity' App/DesktopGlassPanelView.swift "desktop glass does not apply its elasticity setting"
require_text 'GlassSettingKeys.dispersion' App/DesktopGlassPanelView.swift "desktop glass does not apply its dispersion setting"
require_text 'glass dispersion setting has no visible render effect' Checks/main.swift "glass dispersion lacks a render regression"
require_text 'glass corner-radius setting has no visible render effect' Checks/main.swift "glass corner radius lacks a render regression"
require_text 'glass elasticity setting has no visible render effect' Checks/main.swift "glass elasticity lacks a render regression"
require_text 'glass displacement setting has no visible render effect' Checks/main.swift "glass displacement lacks a render regression"
require_text 'glass edge strength changes the interior tone' Checks/main.swift "glass edge/tone isolation lacks a render regression"
require_text 'polar refraction mode has no visible effect' Checks/main.swift "glass refraction modes lack a render regression"
require_text 'ContainerRelativeShape()' Widget/CodexQuotaWidget.swift "widget background does not follow the system-owned container silhouette"
require_text 'glass settings did not survive the app-to-widget snapshot round trip' Checks/main.swift "app-to-widget glass settings sync lacks a regression"
require_text 'updateGlassSettings' App/CodexAppServer.swift "app does not persist glass settings for widgets"
require_text 'glassReloadWorkItem?.cancel()' App/CodexAppServer.swift "glass slider updates are not coalesced to the final widget value"
require_text 'snapshot.glassSettings' Widget/CodexQuotaWidget.swift "widget ignores app glass settings"
require_text 'AppearanceV5ConfigurationIntent.self' Widget/CodexQuotaWidget.swift "widgets do not use the crash-safe V5 appearance intent"
require_text 'controlStyle: .field' Shared/AppearanceV3ConfigurationIntent.swift "safe opacity field is missing"
forbid_text 'struct AppearanceV4ConfigurationIntent' Shared/AppearanceV3ConfigurationIntent.swift "crash-prone V4 slider intent is still shipped"
require_text 'SnapshotHTTPClient.load' Widget/CodexQuotaWidget.swift "widget does not use the checked snapshot client"
require_text 'context.isPreview ? UsageSnapshot.placeholder : SnapshotStore.load()' Widget/CodexQuotaWidget.swift "configuration preview does not use an immediate cached snapshot"
require_text 'reloadIgnoringLocalCacheData' Shared/UsageSnapshot.swift "widget HTTP cache bypass is missing"
require_text 'addingTimeInterval(60)' Widget/CodexQuotaWidget.swift "one-minute WidgetKit fallback is missing"
require_text 'withTimeInterval: 15' App/CodexAppServer.swift "15-second app refresh timer is missing"
require_text 'if snapshotChanged' App/CodexAppServer.swift "unchanged polling can still invalidate widget configuration previews"
require_text 'arguments: ["-r", staleWidget.path]' App/WidgetRepairService.swift "verified obsolete widget registrations are not removed"
require_text 'private func retry()' App/CodexAppServer.swift "snapshot listener recovery is missing"
require_text 'reloadTimelines(ofKind: SnapshotStore.smallWidgetKind)' App/CodexAppServer.swift "small widget reload is missing"
require_text 'reloadTimelines(ofKind: SnapshotStore.largeWidgetKind)' App/CodexAppServer.swift "large widget reload is missing"
require_text 'WidgetRepairService.repair()' App/CodexQuotaApp.swift "launch-time widget repair is missing"
require_text 'isCurrentWidgetRegistered' App/WidgetRepairService.swift "installed widget registration check is missing"
require_text 'registrationDecision' App/WidgetRepairService.swift "widget version election guard is missing"
require_text '["-e", "use", "-i", extensionIdentifier]' App/WidgetRepairService.swift "widget enable repair is missing"
python3 - App/WidgetRepairService.swift <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("case .newerBuildPresent:")
end = source.index("case let .proceed", start)
branch = source[start:end]
if "return" not in branch or "run(" in branch:
    raise SystemExit("newer-build guard must return before every registration write")
PY
pass "quota parsing, boundary renders, background-difference detection, and refresh contracts"

section "Built app and WidgetKit extension"
[ -x "$app_executable" ] || fail "app executable is missing"
[ -x "$widget_executable" ] || fail "widget executable is missing"
[ -f "$app_metadata" ] || fail "app intent metadata is missing"
[ -f "$widget_metadata" ] || fail "widget intent metadata is missing"
[ -f "$app/Contents/Resources/Assets.car" ] || fail "compiled widget assets are missing"
[ -f "$widget/Contents/Resources/Assets.car" ] || fail "widget asset catalog is missing"

app_identifier="$(plist_value "$app_info" CFBundleIdentifier)"
extension_point="$(plist_value "$widget_info" NSExtension:NSExtensionPointIdentifier)"
app_version="$(plist_value "$app_info" CFBundleShortVersionString)"
widget_version="$(plist_value "$widget_info" CFBundleShortVersionString)"
app_build="$(plist_value "$app_info" CFBundleVersion)"
widget_build="$(plist_value "$widget_info" CFBundleVersion)"
[ "$app_identifier" = "dev.codexquota.app" ] || fail "unexpected app bundle identifier: $app_identifier"
[ "$(plist_value "$widget_info" CFBundleIdentifier)" = "$widget_identifier" ] || fail "unexpected widget bundle identifier"
[ "$extension_point" = "com.apple.widgetkit-extension" ] || fail "invalid WidgetKit extension point"
[ "$app_version" = "$widget_version" ] || fail "app and widget marketing versions differ"
[ "$app_build" = "$widget_build" ] || fail "app and widget build numbers differ"
[ "$(plist_value "$widget_info" NSAppTransportSecurity:NSAllowsLocalNetworking 2>/dev/null || true)" = "true" ] ||
    fail "widget does not allow local networking"

if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
    tag_version="${GITHUB_REF_NAME#v}"
    [ "$app_version" = "$tag_version" ] || fail "tag $GITHUB_REF_NAME does not match bundle version $app_version"
    require_text "Latest release: [$GITHUB_REF_NAME]" README.md "README latest release does not match $GITHUB_REF_NAME"
    require_text "Codex-Quota-${GITHUB_REF_NAME}-macOS.dmg" README.md "README download does not match $GITHUB_REF_NAME"
fi

app_archs="$(lipo -archs "$app_executable")"
widget_archs="$(lipo -archs "$widget_executable")"
case " $app_archs " in *" arm64 "*) ;; *) fail "app is missing arm64" ;; esac
case " $app_archs " in *" x86_64 "*) ;; *) fail "app is missing x86_64" ;; esac
case " $widget_archs " in *" arm64 "*) ;; *) fail "widget is missing arm64" ;; esac
case " $widget_archs " in *" x86_64 "*) ;; *) fail "widget is missing x86_64" ;; esac
codesign --verify --deep --strict --verbose=2 "$app" >/dev/null 2>&1 || fail "app or embedded widget signature is invalid"
codesign -d --entitlements :- "$widget" > "$tmp/widget-entitlements.plist" 2>/dev/null ||
    fail "widget signature entitlements cannot be read"
[ "$(plist_value "$tmp/widget-entitlements.plist" com.apple.security.app-sandbox 2>/dev/null || true)" = "true" ] ||
    fail "widget lacks com.apple.security.app-sandbox entitlement"
[ "$(plist_value "$tmp/widget-entitlements.plist" com.apple.security.network.client 2>/dev/null || true)" = "true" ] ||
    fail "widget lacks com.apple.security.network.client entitlement"
/usr/bin/assetutil --info "$widget/Contents/Resources/Assets.car" > "$tmp/widget-assets.json" ||
    fail "widget asset catalog cannot be inspected"
grep -Fq 'CodexMark' "$tmp/widget-assets.json" || fail "widget asset catalog lacks CodexMark"

case "$app_build" in *[!0-9]*|'') fail "bundle build number is not numeric" ;; esac
if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
    head_commit="$(git rev-parse HEAD)"
    max_previous_build=0
    for tag in $(git tag --list 'v*'); do
        tag_commit="$(git rev-parse "$tag^{commit}" 2>/dev/null || true)"
        [ "$tag_commit" = "$head_commit" ] && continue
        tag_build="$(git show "${tag}:CodexQuotaWidget.xcodeproj/project.pbxproj" 2>/dev/null | sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9][0-9]*\).*/\1/p' | sort -n | tail -1)"
        case "$tag_build" in *[!0-9]*|'') continue ;; esac
        [ "$tag_build" -gt "$max_previous_build" ] && max_previous_build="$tag_build"
    done
    [ "$app_build" -gt "$max_previous_build" ] || fail "build $app_build must be greater than released build $max_previous_build"
fi

plutil -convert json -o "$tmp/app-intents.json" "$app_metadata"
plutil -convert json -o "$tmp/widget-intents.json" "$widget_metadata"
for token in AppearanceV5ConfigurationIntent useLightAppearance glassOpacity; do
    grep -Fq "$token" "$tmp/app-intents.json" || fail "app intent metadata lacks $token"
    grep -Fq "$token" "$tmp/widget-intents.json" || fail "widget intent metadata lacks $token"
done
python3 - "$tmp/app-intents.json" "$tmp/widget-intents.json" <<'PY'
import json
import sys

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as file:
        actions = json.load(file)["actions"]
        if "AppearanceV4ConfigurationIntent" in actions:
            raise SystemExit(f"{path}: crash-prone V4 slider metadata is still present")
        for name, candidate in actions.items():
            for parameter in candidate.get("parameters", []):
                if parameter.get("name") != "glassOpacity":
                    continue
                candidate_metadata = parameter.get("typeSpecificMetadata", [])
                key = "LNValueTypeMetadataKeyNumberControlStyle"
                if key in candidate_metadata:
                    candidate_style = candidate_metadata[candidate_metadata.index(key) + 1]
                    if candidate_style.get("int", {}).get("wrapper") == 2:
                        raise SystemExit(f"{path}: {name} contains a crash-prone opacity slider")
        action = actions["AppearanceV5ConfigurationIntent"]
    opacity = next(item for item in action["parameters"] if item["name"] == "glassOpacity")
    metadata = opacity["typeSpecificMetadata"]
    style = metadata[metadata.index("LNValueTypeMetadataKeyNumberControlStyle") + 1]
    if style.get("int", {}).get("wrapper") != 1:
        raise SystemExit(f"{path}: V5 glass opacity is not the crash-safe field")
    type_identifier = opacity["valueType"]["primitive"]["wrapper"]["typeIdentifier"]
    if type_identifier != 7:
        raise SystemExit(f"{path}: V5 glass opacity field is not Double-backed")
PY
strings "$widget_executable" > "$tmp/widget-strings.txt"
grep -Fq 'dev.codexquota.widget.small.v5' "$tmp/widget-strings.txt" || fail "small widget kind is absent from binary"
grep -Fq 'dev.codexquota.widget.large.v5' "$tmp/widget-strings.txt" || fail "large widget kind is absent from binary"
pass "signed, version-matched app and extension with both widget configurations"

section "Isolated WidgetKit registry"
[ "${CODEX_QUOTA_ISOLATED_REGISTRY:-}" = "1" ] ||
    fail "widget self-registration probe requires CODEX_QUOTA_ISOLATED_REGISTRY=1 on a clean CI user"
/usr/bin/pluginkit -m -A -v -i "$widget_identifier" > "$tmp/pluginkit-baseline.txt"
baseline_count="$(registration_count)"
if [ "$baseline_count" -eq 1 ] && grep -Fq "$widget" "$tmp/pluginkit-baseline.txt"; then
    /usr/bin/pluginkit -r "$widget" >/dev/null 2>&1 || true
fi
wait_for_empty_registry || fail "isolated widget registry contains a registration unrelated to the checked build"
pass "isolated WidgetKit registry starts empty"

section "Non-installed copies stay inert"
volume_name="Codex Quota Gate $$"
mkdir -p "$tmp/dmg-root"
/usr/bin/ditto "$app" "$tmp/dmg-root/Codex Quota.app"
hdiutil create -quiet -volname "$volume_name" -srcfolder "$tmp/dmg-root" -format UDZO "$tmp/translocation.dmg"
hdiutil attach -quiet -nobrowse -readonly "$tmp/translocation.dmg"
translocation_mount="/Volumes/$volume_name"
"$translocation_mount/Codex Quota.app/Contents/MacOS/Codex Quota" >"$tmp/translocated.log" 2>&1 &
translocated_pid=$!
sleep 2
if /usr/sbin/lsof -nP -iTCP:48193 -sTCP:LISTEN >/dev/null 2>&1; then
    fail "a DMG copy started the snapshot bridge"
fi
kill "$translocated_pid" 2>/dev/null || true
wait "$translocated_pid" 2>/dev/null || true
translocated_pid=""
/usr/bin/pluginkit -r "$translocation_mount/Codex Quota.app/Contents/PlugIns/CodexQuotaWidgetExtension.appex" >/dev/null 2>&1 || true
hdiutil detach "$translocation_mount" >/dev/null ||
    fail "translocated DMG remained mounted after its app terminated"
translocation_mount=""
/usr/bin/pluginkit -r "$widget" >/dev/null 2>&1 || true
wait_for_empty_registry || fail "non-installed candidate remained registered after the inert-copy probe"
pass "DMG/build copies do not run registration repair or occupy the live snapshot port"

section "Widget self-registration fault injection"
mkdir -p "$HOME/Applications"
runtime_app="$HOME/Applications/Codex Quota Current Gate $$.app"
stale_app="$HOME/Applications/Codex Quota Stale Gate $$.app"
[ ! -e "$runtime_app" ] && [ ! -e "$stale_app" ] ||
    fail "temporary installed-app path already exists"
[ "$app_build" -gt 1 ] || fail "build number must permit a lower-build registration control"
stale_build=$((app_build - 1))
/usr/bin/ditto "$app" "$stale_app"
stale_widget="$stale_app/Contents/PlugIns/CodexQuotaWidgetExtension.appex"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.0.0" "$stale_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.0.0" "$stale_widget/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $stale_build" "$stale_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $stale_build" "$stale_widget/Contents/Info.plist"
codesign --force --sign - --entitlements Widget/CodexQuotaWidget.entitlements "$stale_widget"
codesign --force --sign - --entitlements App/CodexQuota.entitlements "$stale_app"

/usr/bin/pluginkit -a "$stale_widget" || fail "could not seed the stale widget registration"
/usr/bin/pluginkit -e use -i "$widget_identifier" || fail "could not enable the stale widget registration"
stale_seeded=0
stale_stable=0
for _ in {1..60}; do
    /usr/bin/pluginkit -m -A -v -i "$widget_identifier" > "$tmp/pluginkit.txt"
    registration_count="$(awk -v id="$widget_identifier" 'index($0, id "(") { count++ } END { print count + 0 }' "$tmp/pluginkit.txt")"
    if [ "$registration_count" -eq 1 ] &&
       grep -E '^\+.*dev\.codexquota\.app\.widget' "$tmp/pluginkit.txt" | grep -Fq "$stale_widget"; then
        stale_stable=$((stale_stable + 1))
        if [ "$stale_stable" -ge 2 ]; then
            stale_seeded=1
            break
        fi
    else
        stale_stable=0
    fi
    sleep 0.25
done
[ "$stale_seeded" -eq 1 ] || fail "could not establish the stale-registration negative control"
pass "a lower-version enabled extension was seeded without registering the candidate"

/usr/bin/ditto "$app" "$runtime_app"
runtime_widget="$runtime_app/Contents/PlugIns/CodexQuotaWidgetExtension.appex"
runtime_executable="$runtime_app/Contents/MacOS/Codex Quota"

section "Installed app self-repair and snapshot freshness"
if /usr/sbin/lsof -nP -iTCP:48193 -sTCP:LISTEN >/dev/null 2>&1; then
    fail "port 48193 is already occupied; quit old Codex Quota copies before release testing"
fi

cat > "$tmp/fake-codex" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys
import time

generation = 0
for line in sys.stdin:
    request = json.loads(line)
    method = request.get("method")
    request_id = request.get("id")
    response = None
    if method == "initialize":
        actual_version = request.get("params", {}).get("clientInfo", {}).get("version")
        if actual_version != os.environ.get("CODEX_QUOTA_EXPECT_VERSION"):
            raise SystemExit(f"client version mismatch: {actual_version}")
        response = {"id": request_id, "result": {}}
    elif method == "account/read":
        response = {"id": request_id, "result": {"account": {"email": "gate@example.invalid", "planType": "test"}}}
    elif method == "account/rateLimits/read":
        generation += 1
        if generation == 2:
            time.sleep(5)
        five_hour_used = {1: 12, 2: 47}.get(generation, 73)
        weekly_used = {1: 11, 2: 46}.get(generation, 72)
        response = {"id": request_id, "result": {"rateLimits": {
            "primary": {"usedPercent": five_hour_used, "windowDurationMins": 300},
            "secondary": {"usedPercent": weekly_used, "windowDurationMins": 10080}
        }}}
    elif method == "account/usage/read":
        if generation == 3:
            continue
        if generation >= 4:
            time.sleep(3)
        if generation == 1:
            time.sleep(4)
        values = [101, 202, 303, 404, 505, 606, 1111] if generation == 1 else [404, 808, 1212, 1616, 2424, 3232, 4646]
        buckets = [
            {"startDate": f"2099-01-0{index}", "tokens": tokens}
            for index, tokens in enumerate(values, start=1)
        ]
        response = {"id": request_id, "result": {"dailyUsageBuckets": buckets}}
    if response is not None:
        print(json.dumps(response), flush=True)
        if method == "account/rateLimits/read" and generation == 1:
            print(json.dumps({"method": "account/rateLimits/updated", "params": {}}), flush=True)
        if method == "account/rateLimits/read" and generation == 3:
            print(json.dumps({"method": "account/rateLimits/updated", "params": {}}), flush=True)
        if method == "account/usage/read" and generation >= 4:
            open(os.environ["CODEX_QUOTA_STABLE_MARKER"], "a").close()
PY
chmod +x "$tmp/fake-codex"

python3 -c 'import pathlib,socket,sys,time; s=socket.socket(); s.bind(("127.0.0.1",48193)); s.listen(); pathlib.Path(sys.argv[1]).touch(); time.sleep(30)' "$tmp/blocker-ready" &
blocker_pid=$!
for _ in {1..40}; do
    [ -f "$tmp/blocker-ready" ] && break
    sleep 0.1
done
[ -f "$tmp/blocker-ready" ] || fail "could not reserve the snapshot port for the recovery test"

CODEX_BINARY="$tmp/fake-codex" CODEX_QUOTA_EXPECT_VERSION="$app_version" \
CODEX_QUOTA_STABLE_MARKER="$tmp/stable-response" \
    "$runtime_executable" >"$tmp/app.log" 2>&1 &
app_pid=$!
sleep 2
kill -0 "$app_pid" 2>/dev/null || fail "installed candidate app exited during startup"

auto_registered=0
auto_registration_stable=0
for _ in {1..80}; do
    /usr/bin/pluginkit -m -A -v -i "$widget_identifier" > "$tmp/pluginkit.txt"
    registration_count="$(awk -v id="$widget_identifier" 'index($0, id "(") { count++ } END { print count + 0 }' "$tmp/pluginkit.txt")"
    if [ "$registration_count" -eq 1 ] &&
       grep -E '^\+.*dev\.codexquota\.app\.widget' "$tmp/pluginkit.txt" | grep -Fq "$runtime_widget" &&
       ! grep -Fq "$stale_widget" "$tmp/pluginkit.txt"; then
        auto_registration_stable=$((auto_registration_stable + 1))
        if [ "$auto_registration_stable" -ge 2 ]; then
            auto_registered=1
            break
        fi
    else
        auto_registration_stable=0
    fi
    sleep 0.25
done
[ "$auto_registered" -eq 1 ] || fail "installed app did not remove the stale registration and auto-register its current widget"
pass "installed app produced exactly one enabled current WidgetKit registration"

kill "$blocker_pid" 2>/dev/null || true
wait "$blocker_pid" 2>/dev/null || true
blocker_pid=""

first_snapshot=0
for _ in {1..15}; do
    if curl --silent --show-error --fail --max-time 2 \
        -D "$tmp/headers.txt" \
        http://127.0.0.1:48193/snapshot \
        -o "$tmp/snapshot.json"; then
        if python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); ok=s.get("fiveHour",{}).get("usedPercent")==12 and s.get("weekly",{}).get("usedPercent")==11 and len(s.get("dailyUsage",[]))==7 and s.get("dailyUsage",[{}])[-1].get("tokens")==1111; raise SystemExit(0 if ok else 1)' "$tmp/snapshot.json"; then
            first_snapshot=1
            break
        fi
    fi
    sleep 1
done
[ "$first_snapshot" -eq 1 ] || fail "snapshot bridge did not recover with the first synchronized quota snapshot"
grep -Eiq '^Content-Type: *application/json' "$tmp/headers.txt" || fail "snapshot response is not JSON"
grep -Eiq '^Cache-Control: *no-store' "$tmp/headers.txt" || fail "snapshot response can be cached"
grep -Eiq '^X-Content-Type-Options: *nosniff' "$tmp/headers.txt" || fail "snapshot response permits MIME sniffing"
[ "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 2 http://127.0.0.1:48193/not-snapshot)" = "404" ] ||
    fail "snapshot bridge exposes an unexpected route"
listener_pids="$(/usr/sbin/lsof -nP -t -iTCP:48193 -sTCP:LISTEN | sort -u)"
[ "$listener_pids" = "$app_pid" ] || fail "snapshot port is not owned exclusively by the installed candidate app"
first_updated_at="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["updatedAt"])' "$tmp/snapshot.json")"

python3 - "$tmp/snapshot.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    snapshot = json.load(handle)

required = {"fiveHour", "weekly", "appearance", "glassSettings", "dailyUsage", "updatedAt"}
missing = sorted(required.difference(snapshot))
if missing:
    raise SystemExit(f"snapshot missing fields: {', '.join(missing)}")
if "email" in snapshot or "plan" in snapshot:
    raise SystemExit("snapshot leaks account identity")
if not isinstance(snapshot["dailyUsage"], list):
    raise SystemExit("dailyUsage is not a list")
PY

CODEX_QUOTA_EXPECT_FIVE_HOUR=12 \
CODEX_QUOTA_EXPECT_WEEKLY=11 \
CODEX_QUOTA_EXPECT_DAILY_COUNT=7 \
CODEX_QUOTA_EXPECT_LAST_TOKENS=1111 \
    "$tmp/widget-provider-probe"

second_snapshot=0
for _ in {1..25}; do
    curl --silent --show-error --fail --max-time 2 \
        http://127.0.0.1:48193/snapshot \
        -o "$tmp/snapshot.json" || true
    if python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); ok=s.get("fiveHour",{}).get("usedPercent")==47 and s.get("weekly",{}).get("usedPercent")==46 and len(s.get("dailyUsage",[]))==7 and s.get("dailyUsage",[{}])[-1].get("tokens")==4646 and float(s.get("updatedAt",0))>float(sys.argv[2]); raise SystemExit(0 if ok else 1)' "$tmp/snapshot.json" "$first_updated_at"; then
        second_snapshot=1
        break
    fi
    sleep 1
done
[ "$second_snapshot" -eq 1 ] || fail "15-second polling did not replace snapshot A with snapshot B"
CODEX_QUOTA_EXPECT_FIVE_HOUR=47 \
CODEX_QUOTA_EXPECT_WEEKLY=46 \
CODEX_QUOTA_EXPECT_DAILY_COUNT=7 \
CODEX_QUOTA_EXPECT_LAST_TOKENS=4646 \
    "$tmp/widget-provider-probe"

second_updated_at="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["updatedAt"])' "$tmp/snapshot.json")"
partial_snapshot=0
for _ in {1..30}; do
    curl --silent --show-error --fail --max-time 2 \
        http://127.0.0.1:48193/snapshot \
        -o "$tmp/snapshot.json" || true
    if python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); ok=s.get("fiveHour",{}).get("usedPercent")==73 and s.get("weekly",{}).get("usedPercent")==72 and len(s.get("dailyUsage",[]))==7 and s.get("dailyUsage",[{}])[-1].get("tokens")==4646 and float(s.get("updatedAt",0))>float(sys.argv[2]); raise SystemExit(0 if ok else 1)' "$tmp/snapshot.json" "$second_updated_at"; then
        partial_snapshot=1
        break
    fi
    sleep 1
done
[ "$partial_snapshot" -eq 1 ] || fail "a missing trend response froze the 5h and weekly quota refresh"
CODEX_QUOTA_EXPECT_FIVE_HOUR=73 \
CODEX_QUOTA_EXPECT_WEEKLY=72 \
CODEX_QUOTA_EXPECT_DAILY_COUNT=7 \
CODEX_QUOTA_EXPECT_LAST_TOKENS=4646 \
    "$tmp/widget-provider-probe"
third_updated_at="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["updatedAt"])' "$tmp/snapshot.json")"
for _ in {1..20}; do
    [ -f "$tmp/stable-response" ] && break
    sleep 0.25
done
[ -f "$tmp/stable-response" ] || fail "unchanged refresh control did not complete"
sleep 1
curl --silent --show-error --fail --max-time 2 \
    http://127.0.0.1:48193/snapshot \
    -o "$tmp/snapshot.json"
python3 -c 'import json,sys; current=float(json.load(open(sys.argv[1]))["updatedAt"]); expected=float(sys.argv[2]); raise SystemExit(0 if current == expected else 1)' "$tmp/snapshot.json" "$third_updated_at" ||
    fail "unchanged polling invalidated the widget configuration preview"
pass "candidate-owned port recovery, queued/delayed refreshes, partial quota liveness, Widget client A-to-B-to-C refresh, and privacy checks"

if [ -n "$dmg_input" ]; then
    section "DMG payload"
    hdiutil verify "$dmg_input" >/dev/null || fail "DMG verification failed"
    payload_mount="$tmp/payload-mount"
    mkdir -p "$payload_mount"
    hdiutil attach -quiet -nobrowse -readonly -mountpoint "$payload_mount" "$dmg_input"
    payload_app="$payload_mount/Codex Quota.app"
    payload_widget="$payload_app/Contents/PlugIns/CodexQuotaWidgetExtension.appex"
    payload_app_executable="$payload_app/Contents/MacOS/Codex Quota"
    payload_widget_executable="$payload_widget/Contents/MacOS/CodexQuotaWidgetExtension"
    [ -d "$payload_app" ] || fail "DMG does not contain Codex Quota.app"
    [ ! -L "$payload_app" ] || fail "DMG app is an unexpected symbolic link"
    [ -L "$payload_mount/Applications" ] && [ "$(readlink "$payload_mount/Applications")" = "/Applications" ] ||
        fail "DMG lacks the expected Applications shortcut"
    unexpected_payload_count="$(find "$payload_mount" -mindepth 1 -maxdepth 1 ! -name 'Codex Quota.app' ! -name Applications -print | wc -l | tr -d ' ')"
    [ "$unexpected_payload_count" -eq 0 ] || fail "DMG contains unexpected top-level payloads"
    [ -x "$payload_app_executable" ] || fail "DMG app executable lost its executable mode"
    [ -x "$payload_widget_executable" ] || fail "DMG widget executable lost its executable mode"
    [ "$(plist_value "$payload_app/Contents/Info.plist" CFBundleShortVersionString)" = "$app_version" ] || fail "DMG app version differs from checked app"
    [ "$(plist_value "$payload_app/Contents/Info.plist" CFBundleVersion)" = "$app_build" ] || fail "DMG app build differs from checked app"
    [ "$(lipo -archs "$payload_app_executable")" = "$app_archs" ] || fail "DMG app architectures differ from checked app"
    [ "$(lipo -archs "$payload_widget_executable")" = "$widget_archs" ] || fail "DMG widget architectures differ from checked app"
    codesign --verify --deep --strict --verbose=2 "$payload_app" >/dev/null 2>&1 || fail "DMG contains an invalid app signature"
    [ "$(bundle_digest "$payload_app")" = "$(bundle_digest "$app")" ] ||
        fail "DMG app bytes differ from the app that passed the release gate"
    hdiutil detach "$payload_mount" >/dev/null
    payload_mount=""
    pass "verified DMG contains the exact signed app bundle that passed the gate"
fi

printf '\nRelease gate passed for Codex Quota %s (%s).\n' "$app_version" "$app_build"
