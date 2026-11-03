# Quota reads — build 63

The desktop panel, app, menu and Insights use one account-owned coordinator.
There is no second connection, fabricated reset date, reset-card assumption,
or cache deletion in this fix.

## Contract

- A validated `account/rateLimits/read` response replaces both complete windows
  in one published snapshot immediately. Percentage, duration, reset time and
  receipt time belong to that response, even when only the reset date changed.
  An omitted/null reset stays unknown; the previous date is not merged back.
- Accepted unchanged reads persist their new receipt time, not a made-up data
  change. Timers, glass settings and the system clock do not create observations.
- Token trend reads are optional and independent. Late, missing, malformed or
  unsupported responses cannot hold quota publication or clear good history.
- Manual requests coalesce while a quota read is pending. A completed quota
  read does not make the user wait for optional trend data before reading again.
  Duplicate/expired request IDs and previous-account/process results stay inert.
- Read errors and the 10-second quota timeout retain the last valid data and
  report failure. The next refresh can retry. Initialization/account reads have
  a 12-second timeout instead of remaining stuck on Connecting indefinitely.
  A timed-out connection is invalidated so the next refresh starts a replacement
  process rather than repeatedly querying the same unresponsive connection.
- App and panel refresh actions display a busy state while the quota read is
  outstanding, then become available again on success, failure or timeout.
- Quota polling sends `excludeResetCreditDetails: true`: the panel needs the
  authoritative window snapshot, not the separate reset-credit inventory.
  Verified against the installed CLI 0.166.0-alpha.5.1 generated protocol.

## Primary source verification

OpenAI Codex source pinned to `61635845491fd720bb49909466aa19fe5633c773`:

- [Account rate-limit read](https://github.com/openai/codex/blob/61635845491fd720bb49909466aa19fe5633c773/codex-rs/app-server/src/request_processors/account_processor.rs#L1171-L1277)
  performs a backend read, but otherwise joins the optional credit-detail fetch.
- [Read parameters](https://github.com/openai/codex/blob/61635845491fd720bb49909466aa19fe5633c773/codex-rs/app-server-protocol/src/protocol/v2/account.rs#L341-L374)
  explicitly support skipping credit details for monitoring/background polls.
- [Backend usage request](https://github.com/openai/codex/blob/61635845491fd720bb49909466aa19fe5633c773/codex-rs/backend-client/src/client/rate_limit_resets.rs#L16-L84)
  reads the service. A reset-card outcome does not promise a new reset deadline.

`Gate/ModelCatalogProbe.swift` runs the production coordinator against the local
protocol fixture only in an isolated CI user, including reset-only updates,
null dates, source errors, optional-trend failure, queued requests, timeout,
unchanged receipts, stale responses and account isolation. The full signed-app
preflight remains mandatory; pure source checks do not replace runtime checks.

Real account/server behavior is separate from deterministic fixture coverage.
If the service itself returns an unchanged deadline, display it as returned;
never calculate a replacement from a jump in remaining percentage.
