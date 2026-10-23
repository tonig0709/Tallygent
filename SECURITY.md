# Security

The app launches the locally installed `codex app-server` and uses its official
JSONL protocol. OAuth credentials are stored and refreshed by Codex itself.
This project never reads `~/.codex/auth.json`, never stores access tokens, and
never sends credentials to a third-party server.

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
ad-hoc-signed release, which requires Control-click → **Open** on first launch.
Partially configured credentials fail the release instead of silently falling
back. Each release also contains a SHA-256 checksum file; verify it with
`scripts/verify-release.sh` before opening a download if you need an independent
integrity check.

This trust applies only to DMGs attached to the repository's official GitHub
Release. Builds from forks, source archives, and copies shared elsewhere are
not official releases and should be treated as untrusted until independently
verified.

A local process could still impersonate the fixed loopback port; the impact is
limited to displaying false quota data, not account access or token exposure.

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
