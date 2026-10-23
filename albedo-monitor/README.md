# Albedo Monitor

Shows working agents and remaining account quota from the local Albedo daemon.
The panel lists active sessions, subagents, models, workspaces, account limits
and reset countdowns. It targets Noctalia v5.3.0 (plugin API 34).

## Setup

Install the `albedo-monitor` package from albedo-suite and make it available on
Noctalia’s PATH. Add this repository as a plugin path source, enable
`adam0/albedo-monitor`, then add the `adam0/albedo-monitor:status` bar widget.
Infra supplies the helper’s absolute path through the `monitorPath` setting.

| Setting | Default | Purpose |
| --- | --- | --- |
| `monitorPath` | `albedo-monitor` | Helper executable, not a shell command |
| `refreshIntervalSec` | `60` | Snapshot interval, clamped to 2–300 seconds |

The helper uses `ALBEDO_HOME`, falling back to `~/.albedo`. The widget passes
`--start-daemon`, allowing the helper to start a missing daemon through Albedo’s
native CLI without attaching a client. Running the helper without that flag
remains read-only. The plugin receives no authentication tokens. Albedo’s ordinary
`/auth` read may assign missing stable account IDs and metadata in its credentials
file.

## Indicator and panel

- The bar shows a bare working-session count: muted at zero, primary when busy.
- Each account gets one compact meter and **remaining** percentage, choosing the
  lowest fresh, healthy quota window. Provider/account names and other windows
  stay in the tooltip and panel rather than filling the bar.
- The panel shows only working or waiting sessions, including child agents.
  Session and account cards follow the shell’s corner-radius setting. Account
  limits show reset countdowns instead of dates; observation timestamps are hidden.
- Hover for account/window identities, quota errors and snapshot time.
- Click to open the panel. Right-click or use its refresh button to read a new
  snapshot. Refreshing does not force a provider quota poll.
- Offline and failed snapshots never count last-known sessions as active.
  Retained data is explicitly stale. Quotas older than 30 minutes or past their
  reset show as stale in the bar, without a live percentage or meter. The tooltip
  and panel retain explicitly labeled last-known percentages.
- Unreported or unjoinable limits show as unavailable, never as unlimited.
  Account identity matching belongs to the helper, not the UI.

The service reads a snapshot every minute by default, once per plugin even with
several widgets. All returned accounts appear in the bar, with one relevant
window each; its width grows with the connected inventory. Infra uses this widget
instead of CodexBar.
Panel lists show at most 60 active sessions (working first), 40 accounts and
20 windows per account, with an overflow count. The helper also reports daemon
pagination or quota limits.
Client counts aren’t exposed by the daemon API and aren’t displayed.

## Checks

From the repository root:

```sh
noctalia plugins lint albedo-monitor
python3 tests/run.py /path/to/luau
```

The Luau tests execute the actual service, widget and panel against an isolated
host mock. Helper HTTP/authentication tests live in albedo-suite. These checks
don’t verify compositor rendering or activate the system configuration.
