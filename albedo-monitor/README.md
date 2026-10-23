# Albedo Monitor

Shows working agents and remaining account quota from an existing Albedo daemon.
The panel lists sessions, subagents, models, workspaces, account limits, reset
and observation times. It targets Noctalia v5.3.0 (plugin API 34).

## Setup

Install the `albedo-monitor` package from albedo-suite and make it available on
Noctalia’s PATH. Add this repository as a plugin path source, enable
`adam0/albedo-monitor`, then add the `adam0/albedo-monitor:status` bar widget.
Infra supplies the helper’s absolute path through the `monitorPath` setting.

| Setting | Default | Purpose |
| --- | --- | --- |
| `monitorPath` | `albedo-monitor` | Helper executable, not a shell command |
| `refreshIntervalSec` | `5` | Snapshot interval, clamped to 2–300 seconds |

The helper uses `ALBEDO_HOME`, falling back to `~/.albedo`, and only connects to
an already running local daemon. It never starts a daemon or attaches a client.
The plugin receives no authentication tokens. Albedo’s ordinary `/auth` read
may assign missing stable account IDs and metadata in its credentials file.

## Indicator and panel

- The bar counts working sessions, including child agents. Waiting sessions have
  a separate count; idle sessions remain in the panel.
- The percentage is the lowest **remaining** quota across fresh, healthy account
  windows. The tooltip identifies the limiting account and window.
- Click to open the panel. Right-click or use its refresh button to read a new
  snapshot. Refreshing does not force a provider quota poll.
- Offline and failed snapshots never count last-known sessions as active.
  Retained data is explicitly stale. Quotas older than 30 minutes or past their
  reset are also stale and excluded from the bar percentage.
- Unreported or unjoinable limits show as unavailable, never as unlimited.
  Account identity matching belongs to the helper, not the UI.

The service polls once per plugin, even with several widgets. Panel lists show
at most 60 sessions (working first), 40 accounts and 20 windows per account, with
an overflow count. The helper also reports daemon pagination or quota limits.
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
