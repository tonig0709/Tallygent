#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Keep the official bundled binary in the shared discovery path.
grep -Fq '"/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"' App/CodexAppServer.swift
grep -Fq '"/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"' App/CodexAppServer.swift
python3 - <<'PY'
from pathlib import Path
source = Path('App/CodexAppServer.swift').read_text()
refresh = source.split('    func refresh() {', 1)[1].split('    private func beginRefresh()', 1)[0]
assert 'if case .failed = state' in refresh and 'requestAccount()' in refresh, 'Failed account reads cannot recover on refresh'
PY
binary=/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex
if [ -x "$binary" ]; then
    "$binary" --version
fi
echo 'Codex bundled CLI discovery check passed.'
