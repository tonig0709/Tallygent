#!/bin/sh
set -eu

[ "$#" = 2 ] || { echo "Usage: $0 <Tallygent.dmg> <checksums.txt>" >&2; exit 64; }

dmg=$1
checksums=$2
expected=$(awk -v file="$(basename "$dmg")" '$2 == file { print $1 }' "$checksums")
actual=$(shasum -a 256 "$dmg" | awk '{ print $1 }')

[ -n "$expected" ] && [ "$expected" = "$actual" ] || { echo "Checksum verification failed" >&2; exit 1; }
hdiutil verify "$dmg" >/dev/null

work=$(mktemp -d "${TMPDIR:-/tmp}/codex-quota-verify.XXXXXX")
cleanup() {
    hdiutil detach "$work/mount" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT INT TERM
mkdir "$work/mount"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$work/mount" "$dmg"
app="$work/mount/Tallygent.app"
[ -d "$app" ] || { echo "Tallygent.app is missing from DMG" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$app"

signature=$(codesign -d --verbose=4 "$app" 2>&1)
if printf '%s\n' "$signature" | grep -Fq 'Authority=Developer ID Application'; then
    xcrun stapler validate "$dmg"
    spctl -a -vvv -t open "$dmg"
    echo "Verified: checksum, Developer ID signature, and notarization are valid."
else
    printf '%s\n' "$signature" | grep -Fq 'Signature=adhoc' || { echo "Unexpected signing identity" >&2; exit 1; }
    echo "Verified: checksum and ad-hoc bundle signature are valid; this DMG is not Apple-notarized."
fi
