# Multi-agent quota monitoring — implementation baseline and Tallygent direction

The checked implementation baseline is v0.5.9 (build 45), extending the tested
build 42 panel and build 43 dual-service foundation. Its binary is still named
Codex Quota. On 2026-10-24 the user confirmed the future product name **Tallygent**.
The rename is a product decision, not an already-completed binary migration.
See [the Tallygent roadmap](TALLYGENT_ROADMAP.md) for the updated Monitor → Insights
→ Planner → Control phases, migration constraints and acceptance criteria.
Bundle identity and glass settings must remain compatible. This work uses the
existing three native movable panels, not WidgetKit or the particle experiment.

## Data flow

Codex app-server → CodexAppServer → QuotaMonitor → App and one desktop panel.

Claude Code statusLine → the app executable's bridge mode → sanitized local
record → QuotaMonitor → the same App and desktop panel.

Only QuotaMonitor owns selection. A late response from one provider cannot
replace the selected provider's data. The legacy usageSnapshot cache stays
Codex-only; Claude never writes to it. Glass settings and panel position remain
independent of provider selection.

## Claude first release scope

- Explicit, opt-in installation of a statusLine command. Never enabled at launch.
- Official five_hour and seven_day quota fields only. No private OAuth endpoint,
  cookie access, login credential extraction, API inference calls, or remote backend.
- One explicitly bound Claude session. Other session fingerprints cannot overwrite
  its data; users can reset the binding. This intentionally avoids unverified
  account inference or merging unrelated accounts.
- Existing third-party statusLine configuration causes a refusal with guidance,
  rather than silent replacement. Other settings are preserved. Removing the
  integration restores only the configuration owned by this app and retains the
  last quota record; resetting the session clears that record.
- Local record stores normalized quota windows, receipt time and a session hash.
  Raw statusLine input, prompt text, paths and transcripts are not saved. Setup
  must read and back up the full existing settings JSON to preserve other fields;
  its owner-only 0600 backup may therefore include pre-existing env secrets.
- Receipt time describes local ingestion, not a fresh server read. Refreshing the
  UI only rereads the file. Claude Code must be running and emit usable quota data.
- Missing quota remains missing; no fake 0%, sample values or synthetic seven-day
  Token history in the production UI. No subscription or an unsupported session
  may yield no quota fields. Cached or expired records are identified.

Official interface: https://code.claude.com/docs/en/statusline

## Delivery stages

1. Foundation: dual service selection, sanitized bridge, missing-data UI, separate
   caches, opt-in reversible setup, isolated regression checks.
2. Real-account validation: a subscribing volunteer runs the test version and
   confirms actual quota, reset fields, activity/idle/exit behavior and existing
   statusLine compatibility. No password or API token needs to be shared.
3. Branding: the approved product name is Tallygent. A new candidate must retain
   the bundle ID and preference keys, account for Claude's absolute bridge path,
   and test upgrades before replacing the already-checked Codex Quota binary.
4. Release: universal full-Xcode builds on macOS 14/15/26, existing full release
   preflight plus provider checks, then desktop drag/close/reopen/hover smoke test.
   Until real-account validation, Claude remains experimental.

For this delivery, stop before publication: prepare the candidate, test results
and draft notes. Do not update the public "latest" download to an unpublished
artifact or describe simulated Claude input as real-account acceptance.

No claim of verified real Claude subscription access can be made from simulated
input alone. Further providers require a documented data source and separate
capability review; subscription percentages and API spending are different metrics.

## Automated verification

`sh scripts/check-agent-providers.sh` runs only against temporary settings and
mock provider data. It is also called by release-preflight. It must not launch
the installed app, bind port 48193 or modify real Claude settings.

The pre-existing release gate remains mandatory before packaging or release.
Run its full runtime section only inside an isolated CI user, as specified in AGENTS.md.
