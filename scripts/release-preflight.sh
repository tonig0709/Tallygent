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
app_executable="$app/Contents/MacOS/Codex Quota"
app_info="$app/Contents/Info.plist"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/codex-quota-release.XXXXXX")"
app_pid=""
blocker_pid=""
translocated_pid=""
translocation_mount=""
payload_mount=""
runtime_app=""

cleanup() {
    if [ -n "$blocker_pid" ]; then kill "$blocker_pid" 2>/dev/null || true; fi
    if [ -n "$app_pid" ]; then
        pkill -TERM -P "$app_pid" 2>/dev/null || true
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    if [ -n "$translocated_pid" ]; then kill "$translocated_pid" 2>/dev/null || true; fi
    if [ -n "$translocation_mount" ]; then hdiutil detach "$translocation_mount" -force >/dev/null 2>&1 || true; fi
    if [ -n "$payload_mount" ]; then hdiutil detach "$payload_mount" -force >/dev/null 2>&1 || true; fi
    if [ -n "$runtime_app" ] && [ -e "$runtime_app" ]; then rm -rf "$runtime_app"; fi
    rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

section() { printf '\n==> %s\n' "$1"; }
pass() { printf '    PASS  %s\n' "$1"; }
fail() {
    printf '    FAIL  %s\n' "$1" >&2
    if [ -s "$tmp/app.log" ]; then tail -80 "$tmp/app.log" >&2; fi
    exit 1
}
require_text() {
    grep -Fq -- "$1" "$2" || fail "$3"
}
forbid_text() {
    ! grep -Fq -- "$1" "$2" || fail "$3"
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

section "Panel source, parser, and visual render checks"
sh scripts/check-codex-discovery.sh
sh scripts/check-desktop-panel.sh
swift run quota-self-check
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    Gate/PanelSnapshotProbe.swift Shared/QuotaWidgetView.swift Shared/UsageSnapshot.swift \
    -framework AppKit -framework Charts -framework SwiftUI -o "$tmp/panel-snapshot-probe"
require_text 'NSVisualEffectView' App/DesktopGlassPanelView.swift "native desktop material is missing"
require_text 'view.blendingMode = .behindWindow' App/DesktopGlassPanelView.swift "wallpaper sampling is missing"
require_text 'Slider(value: value' App/GlassSettingsView.swift "native live sliders are missing"
require_text '.onContinuousHover(perform: updateHover)' App/DesktopGlassPanelView.swift "pointer feedback is missing"
require_text 'accessibilityReduceMotion' App/DesktopGlassPanelView.swift "reduced motion is missing"
require_text 'withTimeInterval: 15' App/CodexAppServer.swift "15-second refresh timer is missing"
require_text 'if snapshotChanged' App/CodexAppServer.swift "unchanged refreshes still rewrite snapshots"
require_text 'private func retry()' App/CodexAppServer.swift "snapshot port recovery is missing"
require_text 'reloadIgnoringLocalCacheData' Shared/UsageSnapshot.swift "snapshot cache bypass is missing"
forbid_text 'import WidgetKit' App/CodexAppServer.swift "panel-only app still depends on WidgetKit"
forbid_text 'CodexQuotaWidgetExtension' CodexQuotaWidget.xcodeproj/project.pbxproj "removed widget target is still built"
forbid_text 'WidgetRepairService' App/CodexQuotaApp.swift "removed widget registration is still invoked"
pass "three native panel sizes, single-window ownership, live settings, readable content, and glass regressions"

section "Built panel-only app"
[ -x "$app_executable" ] || fail "app executable is missing"
[ -f "$app/Contents/Resources/Assets.car" ] || fail "compiled assets are missing"
[ ! -d "$app/Contents/PlugIns" ] || [ -z "$(find "$app/Contents/PlugIns" -name '*.appex' -print)" ] ||
    fail "panel-only app still embeds a widget extension"
if [ -f "$app/Contents/Resources/Metadata.appintents/extract.actionsdata" ]; then
    strings "$app/Contents/Resources/Metadata.appintents/extract.actionsdata" > "$tmp/intent-strings.txt"
    ! grep -Eq 'AppearanceV[345]ConfigurationIntent' "$tmp/intent-strings.txt" ||
        fail "obsolete widget configuration metadata is still shipped"
fi
app_identifier="$(plist_value "$app_info" CFBundleIdentifier)"
app_version="$(plist_value "$app_info" CFBundleShortVersionString)"
app_build="$(plist_value "$app_info" CFBundleVersion)"
[ "$app_identifier" = "dev.codexquota.app" ] || fail "unexpected bundle identifier"
case "$app_build" in *[!0-9]*|'') fail "bundle build number is not numeric" ;; esac
app_archs="$(lipo -archs "$app_executable")"
case " $app_archs " in *" arm64 "*) ;; *) fail "app is missing arm64" ;; esac
case " $app_archs " in *" x86_64 "*) ;; *) fail "app is missing x86_64" ;; esac
codesign --verify --deep --strict --verbose=2 "$app" >/dev/null 2>&1 || fail "app signature is invalid"
/usr/bin/assetutil --info "$app/Contents/Resources/Assets.car" > "$tmp/assets.json" ||
    fail "asset catalog cannot be inspected"
require_text 'CodexMark' "$tmp/assets.json" "Codex mark asset is missing"
if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
    [ "$app_version" = "${GITHUB_REF_NAME#v}" ] || fail "tag does not match bundle version"
    head_commit="$(git rev-parse HEAD)"
    max_previous_build=0
    for tag in $(git tag --list 'v*'); do
        tag_commit="$(git rev-parse "$tag^{commit}" 2>/dev/null || true)"
        [ "$tag_commit" = "$head_commit" ] && continue
        tag_build="$(git show "${tag}:CodexQuotaWidget.xcodeproj/project.pbxproj" 2>/dev/null | sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9][0-9]*\).*/\1/p' | sort -n | tail -1)"
        case "$tag_build" in *[!0-9]*|'') continue ;; esac
        [ "$tag_build" -gt "$max_previous_build" ] && max_previous_build="$tag_build"
    done
    [ "$app_build" -gt "$max_previous_build" ] || fail "build must be greater than every released build"
fi
pass "signed universal app, original icon, monotonic build, and no legacy widget payload"

section "Isolated runtime user"
[ "${CODEX_QUOTA_ISOLATED_REGISTRY:-}" = "1" ] ||
    fail "runtime probes require an isolated CI user"
if /usr/sbin/lsof -nP -iTCP:48193 -sTCP:LISTEN >/dev/null 2>&1; then
    fail "snapshot port is already occupied; never run this gate against a live user session"
fi

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
hdiutil detach "$translocation_mount" >/dev/null ||
    fail "translocated DMG remained mounted after its app terminated"
translocation_mount=""
pass "DMG/build copies do not connect an account or occupy the live snapshot port"

section "Installed app snapshot freshness"
mkdir -p "$HOME/Applications"
runtime_app="$HOME/Applications/Codex Quota Current Gate $$.app"
[ ! -e "$runtime_app" ] || fail "temporary installed-app path already exists"
/usr/bin/ditto "$app" "$runtime_app"
runtime_executable="$runtime_app/Contents/MacOS/Codex Quota"

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
    "$tmp/panel-snapshot-probe"

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
    "$tmp/panel-snapshot-probe"

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
    "$tmp/panel-snapshot-probe"
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
    fail "unchanged polling invalidated the panel settings"
pass "candidate-owned port recovery, queued/delayed refreshes, partial quota liveness, all-mode snapshot A-to-B-to-C refresh, and privacy checks"

if [ -n "$dmg_input" ]; then
    section "DMG payload"
    hdiutil verify "$dmg_input" >/dev/null || fail "DMG verification failed"
    payload_mount="$tmp/payload-mount"
    mkdir -p "$payload_mount"
    hdiutil attach -quiet -nobrowse -readonly -mountpoint "$payload_mount" "$dmg_input"
    payload_app="$payload_mount/Codex Quota.app"
    payload_app_executable="$payload_app/Contents/MacOS/Codex Quota"
    [ -d "$payload_app" ] || fail "DMG does not contain Codex Quota.app"
    [ ! -L "$payload_app" ] || fail "DMG app is an unexpected symbolic link"
    [ -L "$payload_mount/Applications" ] && [ "$(readlink "$payload_mount/Applications")" = "/Applications" ] ||
        fail "DMG lacks the expected Applications shortcut"
    unexpected_payload_count="$(find "$payload_mount" -mindepth 1 -maxdepth 1 ! -name 'Codex Quota.app' ! -name Applications -print | wc -l | tr -d ' ')"
    [ "$unexpected_payload_count" -eq 0 ] || fail "DMG contains unexpected top-level payloads"
    [ -x "$payload_app_executable" ] || fail "DMG app executable lost its executable mode"
    [ "$(plist_value "$payload_app/Contents/Info.plist" CFBundleShortVersionString)" = "$app_version" ] || fail "DMG app version differs from checked app"
    [ "$(plist_value "$payload_app/Contents/Info.plist" CFBundleVersion)" = "$app_build" ] || fail "DMG app build differs from checked app"
    [ "$(lipo -archs "$payload_app_executable")" = "$app_archs" ] || fail "DMG app architectures differ from checked app"
    codesign --verify --deep --strict --verbose=2 "$payload_app" >/dev/null 2>&1 || fail "DMG contains an invalid app signature"
    [ "$(bundle_digest "$payload_app")" = "$(bundle_digest "$app")" ] ||
        fail "DMG app bytes differ from the app that passed the release gate"
    hdiutil detach "$payload_mount" >/dev/null
    payload_mount=""
    pass "verified DMG contains the exact signed app bundle that passed the gate"
fi

printf '\nRelease gate passed for Codex Quota %s (%s).\n' "$app_version" "$app_build"
