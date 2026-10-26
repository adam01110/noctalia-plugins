# Forges

Forges is a read-only Tangled/GitHub work queue for Noctalia v5.3.0 (API 34).
It adapts Shangshui0302's MIT-licensed [GitHub Kanban](https://github.com/noctalia-dev/community-plugins/tree/63150dc53560297140164083b4d14d4aaaf59bc8/github-kanban)
0.2.6. The upstream snapshot declares MIT in its manifest and includes no separate
license file; original author attribution is retained in the manifest and
adapted helpers.

## Accounts and switching

Install `tg`, `gh`, and `xdg-open`. Authenticate outside the plugin:

```sh
tg auth login your.handle
gh auth login
```

The plugin uses each CLI's active account and never reads credentials or changes
remote records. Tangled is the startup default. The panel's Tangled/GitHub buttons
switch the current session; the Default forge setting changes the startup default.
Changing the default in settings also switches the current session.

Repositories lists up to 50 repositories returned by the CLI. Inspect a row, or
enter `owner/repository`, to view its open pull requests and issues (up to 30 each).
Tangled work is repository-scoped; the first returned repository is selected
initially. GitHub starts with open work involving your account across repositories;
All work returns to that scope. GitHub Inbox shows up to 30 unread notifications,
without marking them read. Search filters the fetched first page, not the server.
Tangled work links open the repository's pull-request/issue list: `tg` 0.6 returns
AT Protocol record keys, not the numeric AppView IDs required for item deep links.
GitHub work links open individual items.

This redesign focuses on repositories and open work. The upstream contribution
heatmap, following/release feed, Actions dashboard, notification read-state writes,
and appearance overrides are not included. It is not an editable Kanban board.
Last-good results are retained in memory for same-account/same-scope refreshes,
not persisted to disk. Switching providers clears the displayed account and rows;
late callbacks from previous providers or repositories are discarded.

## Native surfaces

All custom row radii follow `shell.corner_radius_scale`, including square corners.
Row outlines follow `shell.panel.borders`, `border_width`, and `border_color`.
Controls use Noctalia's native surfaces and palette. Panel placement uses the
shell-generated `panel_placement` setting, with floating as the manifest default;
`position = "auto"` and `open_near_click = true` keep it near the invoking widget.
Attached placement is selectable, but Noctalia v5.3.0 draws the **outer** outline
only for floating panels. The plugin does not draw a counterfeit outer frame.

Infra enables `adam0/forges` and the `adam0/forges:forges` bar widget declaratively.
Infra retains its remote flake input. Test this checkout with a temporary
`--override-input noctalia-plugins path:/absolute/path/to/noctalia-plugins`
and `--no-write-lock-file`; do not persist a local input. The remote plugin source
must contain Forges before activating that declarative configuration. No system
activation is performed by the plugin tests.
