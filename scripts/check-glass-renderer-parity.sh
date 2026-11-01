#!/bin/sh
set -eu
# Source-only: safe to run without an app, WindowServer, or personal preferences.
exec python3 -B - "${1:-$(dirname "$0")/..}" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])

def source(path):
    text = (root / path).read_text()
    return re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)

def require(condition, message):
    if not condition:
        sys.exit("Glass renderer parity: " + message)

def contains(text, pattern):
    return re.search(pattern, text, re.S) is not None

def region(text, marker, opening="{", closing="}"):
    match = re.search(marker, text, re.S)
    require(match is not None, "missing source route: " + marker)
    start = text.find(opening, match.end())
    require(start >= 0, "missing route body: " + marker)
    depth = 1
    for end in range(start + 1, len(text)):
        depth += (text[end] == opening) - (text[end] == closing)
        if depth == 0:
            return text[start + 1:end]
    sys.exit("Glass renderer parity: unterminated source route: " + marker)

desktop = source("App/DesktopGlassPanelView.swift")
settings = source("App/GlassSettingsView.swift")
gallery = source("App/DashboardView.swift")
shared = source("Shared/QuotaWidgetView.swift")

require(not contains(desktop, r"\b(?:DesktopGlassSurface|DesktopVisualEffectView)\b"),
        "desktop has a duplicate glass renderer")
require(not contains(desktop, r"\.material\s*=\s*\.popover"),
        "desktop overrides the shared native material")
for text, label in [(desktop, "desktop"), (settings, "settings preview")]:
    require(len(re.findall(r"\bLiquidGlassSurface\s*\(", text)) == 1,
            label + " must call the shared renderer exactly once")
desktop_call = region(desktop, r"\bLiquidGlassSurface\b", "(", ")")
require(contains(desktop_call, r"nativeClearBackdropProvided\s*:\s*true\b"),
        "desktop must use its root-provided clear backdrop")
preview_call = region(settings, r"\bLiquidGlassSurface\b", "(", ")")
require(not contains(preview_call, r"nativeClearBackdropProvided\s*:\s*true\b"),
        "settings preview cannot omit its own clear backdrop")
require(contains(settings, r"GlassOpticsPreview\s*\(\s*settings\s*:\s*currentSettings\b") and
        contains(settings, r"GlassPreviewSurface\s*\(\s*settings\s*:\s*settings\b"),
        "settings optics preview bypasses the production preview route")
require(len(re.findall(r"\bGlassPreviewSurface\s*\(", gallery)) == 1 and
        not contains(gallery, r"\bLiquidGlassSurface\s*\("),
        "gallery must use the same production preview route")

require(contains(shared, r"nativeClearBackdropProvided\s*:\s*Bool\s*=\s*false\b") and
        contains(shared, r"self\.nativeClearBackdropProvided\s*=\s*nativeClearBackdropProvided\b"),
        "shared renderer must default to providing its own clear backdrop")
clear = region(shared, r"if\s+surfaceStyle\s*==\s*\.nativeClear\b")
guarded = region(clear, r"if\s+!nativeClearBackdropProvided\b")
require(contains(guarded, r"\bNativeClearMaterial\s*\(") and
        len(re.findall(r"\bNativeClearMaterial\s*\(", shared)) == 1,
        "native clear backdrop must exist only inside the root-provider guard")
require(len(re.findall(r"\bif\s+!?nativeClearBackdropProvided\b", shared)) == 1,
        "root-provider guard must not alter the tinted rendering path")
require(contains(clear, r"darkFilmOpacity\b"),
        "clear backdrop guard must not remove the shared opacity coating")
require(not contains(desktop_call, r"surfaceStyle\s*:\s*\.nativeClear\b"),
        "desktop must pass the selected style, not force clear")
require(contains(desktop_call, r"surfaceStyle\s*:\s*surfaceStyle\b"),
        "desktop must pass the selected style to the shared renderer")
require(contains(desktop_call, r"pointerHighlightIntensity\s*:\s*pointerHighlightIntensity\b") and
        contains(preview_call, r"pointerHighlightIntensity\s*:\s*settings\.resolvedPointerHighlightIntensity\b") and
        contains(gallery, r"pointerHighlightIntensity\s*:\s*pointerHighlightIntensity\b"),
        "mouse-highlight strength must reach desktop, settings preview and gallery")
for text in [desktop, settings, gallery]:
    require(contains(text, r"@AppStorage\(GlassSettingKeys\.pointerHighlightIntensity\)"),
            "mouse-highlight strength is not shared through the same persisted setting")
require(contains(settings, r'slider\("鼠标高光强度",\s*value:\s*\$pointerHighlightIntensity,\s*range:\s*0\.\.\.1'),
        "native mouse-highlight slider is missing its zero-to-one range")

host = region(desktop, r"final\s+class\s+DesktopGlassBackdropHost\b")
require(contains(host, r"material\.isHidden\s*=\s*!clear\b") and
        contains(host, r"NativeClearMaterial\.configure\s*\(\s*material\b"),
        "desktop root must use the shared clear configuration only for clear style")
require(len(re.findall(r"NSVisualEffectView\s*\(\s*\)", desktop)) == 1 and
        contains(host, r"NSVisualEffectView\s*\(\s*\)"),
        "desktop must have exactly one native backdrop, at the root")
for style in [r"surfaceStyle", r"settings\.resolvedSurfaceStyle"]:
    require(contains(desktop, r"clearMaterial\s*:\s*" + style + r"\s*==\s*\.nativeClear\b"),
            "desktop root activation must follow selected style on creation and updates")
print("Glass renderer source parity: PASS")
PY
