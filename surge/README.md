# Surge

A Noctalia widget for Surge activity and download history. The launcher stays
visible; its count and progress meter disappear when nothing is downloading.
The compact meter and text sizing match Albedo Monitor.

## Setup

Enable `adam0/surge` and add `adam0/surge:status` to a Noctalia bar.
Requires Noctalia v5.3.0 (API 34), Surge v0.12.2 or later, and `timeout`.

Run Surge with its server enabled on a fixed port, for example
`surge server --port 1700`. Set the plugin's **Surge server** address to match
(default: `127.0.0.1:1700`). The Surge CLI discovers its managed token; this
plugin does not store credentials. Remote authentication uses Surge's own
configuration/environment. The plugin never starts a server or modifies the queue.

## Bar and panel

Only `downloading` entries show the bar's count and progress meter. When idle,
paused, queued, or disconnected, the Surge icon remains clickable so the panel
and history stay accessible. Finishing a download does not close the panel.
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
snapshot, but retain the last successful history with an offline warning.
The panel shows a generic error rather than raw CLI diagnostics, which may
include sensitive addresses.

The **Active** tab contains downloading, queued, and paused entries. **History**
contains completed and failed entries returned by Surge, newest-added first
(up to 100 records; 40 rendered at once). History is owned by Surge's server,
not a second plugin database: clearing records in Surge removes them here after
the next successful poll. Cached history survives connection failures but not a
plugin restart without a successful server poll. Tabs retain their selection
while the panel is closed.
