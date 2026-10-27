# Surge

A Noctalia widget for active Surge downloads. It disappears when nothing is
downloading and uses the same compact meter and text sizing as Albedo Monitor.

## Setup

Enable `adam0/surge` and add `adam0/surge:status` to a Noctalia bar.
Requires Noctalia v5.3.0 (API 34), Surge v0.12.2 or later, and `timeout`.

Run Surge with its server enabled on a fixed port, for example
`surge server --port 1700`. Set the plugin's **Surge server** address to match
(default: `127.0.0.1:1700`). The Surge CLI discovers its managed token; this
plugin does not store credentials. Remote authentication uses Surge's own
configuration/environment. The plugin never starts a server or modifies the queue.

## Bar and panel

Only `downloading` entries show the bar. Paused, queued, completed, failed,
and unreachable-server states hide the entire capsule, including its spacing.
Click for a speed-history graph and individual download cards with progress,
transferred sizes, transfer rates, and estimated time remaining; right-click to
refresh. The graph uses the latest 60 successful polls, including zero-speed idle
samples, and scales to the visible peak. Samples are kept in memory while the
panel is closed; a connection error clears them rather than drawing across an
unknown interval. The horizontal axis is polls, not elapsed time; manual refreshes
also add samples. Cards follow the shell's corner and border settings.
The meter is 26×4, matching Albedo Monitor, with a byte-weighted aggregate
percentage. If any active download has an unknown size, show a dash instead of
a misleading percentage. Corner radius follows the shell setting.

An explicit server address prevents stale database records from keeping the
widget visible after Surge exits. Connection errors also clear the last active
snapshot. The panel shows a generic error rather than raw CLI diagnostics,
which may include sensitive addresses. Idle state and connection failures are
both intentionally hidden in the bar.
