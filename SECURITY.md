# Security

The app launches the locally installed `codex app-server` and uses its official
JSONL protocol. OAuth credentials are stored and refreshed by Codex itself.
The Codex integration does not read `~/.codex/auth.json` or copy Codex access
tokens. This project does not send credentials to a third-party server. The
Claude settings backup described below can contain secrets already present in
the user's configuration.

The v0.5.8 candidate adds an experimental, opt-in Claude Code status-line bridge.
It consumes the official status-line JSON locally; it does not access private
OAuth endpoints, browser cookies or Claude login credentials, and does not make
inference requests to estimate subscription quota. Enabling the bridge is a
separate user action; selecting Claude alone does not install it.

The sanitized quota cache at `~/Library/Application Support/CodexQuota/claude-usage.json`
contains only normalized quota windows, local receipt time and a SHA-256 session
fingerprint. Raw input, prompts, transcript data and project paths are not saved.
The first usable record binds one session; other sessions cannot replace it
until the user explicitly resets that binding. Missing quota is not recorded as
zero. The receipt time is not evidence of a fresh server query; rereading this
cache cannot refresh Claude's server-side data. Real subscription access is
still unverified and the integration remains experimental.

Setup reads the complete `~/.claude/settings.json` to preserve unrelated settings
and saves its original contents in
`~/.claude/.codex-quota-statusline-backup.json` before modifying `statusLine`.
That backup may contain environment variables or secrets already present in the
original JSON. It remains local and is written with owner-only `0600` permissions;
do not include it in bug reports. Quota records and lock files are also written
with `0600` permissions. Reads are bounded and reject symlinks, non-regular files
and files owned by another user; writes use an atomic replacement under a lock.
These permissions do not protect against another process running as the same user.

An existing third-party `statusLine` causes setup to refuse installation. Removal
requires the current status line to still match this app's recorded command,
restores only that owned setting, preserves other current settings and deletes
the backup. If configuration was changed externally, the app leaves it intact
and reports the conflict. Removing the bridge retains the last quota record;
the separate session-reset action clears that record.

The current product uses native movable panels, not WidgetKit extensions.
Panels observe the App's in-process snapshot directly. The existing read-only
compatibility/diagnostic bridge serves quota-only JSON at `127.0.0.1:48193`. The listener
binds only to loopback, accepts only `GET /snapshot`, sends `Cache-Control:
no-store`, and removes the account email and plan before encoding the response.
No OAuth credential or account identifier crosses this local bridge.
The bridge is not required for panel rendering or synchronization. This build
does not register extensions, invoke PlugInKit repair, or clear system widget caches.

When the maintainer configures the credentials below, official GitHub Releases
are signed with the maintainer's Apple Developer ID, notarized by Apple, and
stapled to the DMG. Without those credentials, the workflow clearly records an
ad-hoc-signed release. It is not Apple-notarized and macOS may require first-launch
approval; the available approval path depends on the macOS version and policy.
Partially configured credentials fail the release instead of silently falling
back. Each release also contains a SHA-256 checksum file; verify it with
`scripts/verify-release.sh` before opening a download if you need an independent
integrity check.

This trust applies only to DMGs attached to the repository's official GitHub
Release. Builds from forks, source archives, and copies shared elsewhere are
not official releases and should be treated as untrusted until independently
verified.

A local process could still impersonate the fixed loopback port, and a process
running as the same user could modify the Claude cache. These inputs are display
data, not authority for account actions. Do not treat displayed quota or a hashed
session fingerprint as authenticated account identity.

## Maintainer release setup

An Apple Developer Program membership and a **Developer ID Application**
certificate are required. Add these GitHub Actions repository secrets before
pushing the next `v*` tag:

- `DEVELOPER_ID_APPLICATION` — certificate common name, for example
  `Developer ID Application: Your Name (TEAMID)`.
- `DEVELOPER_TEAM_ID` — the ten-character Apple team ID.
- `BUILD_CERTIFICATE_BASE64` and `P12_PASSWORD` — base64-encoded `.p12`
  Developer ID certificate and its export password.
- `KEYCHAIN_PASSWORD` — a new random password used only by the CI keychain.
- `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, and `APPLE_API_KEY_BASE64` — an
  App Store Connect API key with notarization access; the last value is the
  base64-encoded `.p8` file.

The CI workflow imports these only into its temporary keychain, timestamps the
signature, submits the DMG to Apple notarization, staples the resulting ticket,
and verifies Gatekeeper acceptance before creating the GitHub Release.

Please report vulnerabilities privately to the repository maintainer rather
than opening a public issue.
