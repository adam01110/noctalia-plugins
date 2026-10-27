# Forges

Forges is a read-only Tangled/GitHub/GitLab work queue for Noctalia v5.3.0 (API 34).
It adapts Shangshui0302's MIT-licensed [GitHub Kanban](https://github.com/noctalia-dev/community-plugins/tree/63150dc53560297140164083b4d14d4aaaf59bc8/github-kanban)
0.2.6. The upstream snapshot declares MIT in its manifest and includes no separate
license file; original author attribution is retained in the manifest and
adapted helpers.

## Accounts and switching

Install `tg`, `gh`, `glab`, and `xdg-open`. Authenticate outside the plugin:

```sh
tg auth login your.handle
gh auth login
glab auth login --hostname gitlab.school.edu
```

Select **GitLab** in the panel or as the Default forge. Set **GitLab instance URL
(HTTPS)** to your school's origin, for example `https://gitlab.school.edu`;
the default is `https://gitlab.com`. Do not include `/api/v4`, a project path,
credentials, or query parameters. HTTP and subpath installations are not supported.
Authenticate `glab` against the same hostname (including port when applicable),
using a token with `read_api` access. Credentials remain managed by `glab`.
GitLab lists up to 50 membership projects and 30 open merge requests/issues per
project. Nested groups such as `school/course/project` are supported. Contribution
activity opens the GitLab profile; the calendar and inbox remain GitHub-only.
Changing the instance clears GitLab's private caches and rejects pending responses
from the previous instance. No credentials are stored in plugin settings.

The plugin uses each CLI's active account and never reads credentials or changes
remote records. Tangled is the startup default. The panel's forge buttons
switch the current session; the Default forge setting changes the startup default.
Changing the default in settings also switches the current session.

Repositories lists up to 50 repositories returned by the CLI. Inspect a row, or
enter `owner/repository`, to view its open pull requests and issues (up to 30 each).
Tangled work is repository-scoped; the first returned repository is selected
initially. All forges open on Repositories. GitHub's full-year contribution
calendar stays directly below the forge selector, above every queue, with
today/current/best-streak metrics. Graph construction is staged and reused across
renders. Day tooltips and clicks show the date and contribution count; missing
and future slots remain transparent rather than inheriting a black box fill.
Tangled's `tg` CLI has no contribution-calendar endpoint; the contribution button
in the same header position opens native profile activity instead.

The separate Tangled, GitHub, and GitLab buttons immediately left of Reload open the
corresponding profiles without switching forge or loading queues. An unvisited
forge resolves only its account when its profile button is clicked. The panel is
580 pixels wide and 800 pixels tall.
GitHub's All work scope shows open PRs/issues involving your account across repos.

GitHub Inbox includes read **and** unread notifications, without marking them
read. All/Unread/Read filters and 20-row display pages are local and issue no
requests. Load older notifications fetches the next 50-item server page, retaining
up to 500 available notifications. The UI labels these as loaded history, not a
complete archive. Search filters loaded results, not the server.
Tangled work links open the repository's pull-request/issue list: `tg` 0.6 returns
AT Protocol record keys, not the numeric AppView IDs required for item deep links.
GitHub and GitLab work links open individual items.

## Fetching and caches

Each forge retains its own verified account and independent in-memory caches for
repositories, contributions, inbox history, and repository-scoped PR/issue lists.
Switching providers or revisiting a fresh view reuses these results immediately;
it does not refetch other lists. The first visit loads only the selected queue
plus GitHub's visible contribution header. Repository changes reuse the fresh
calendar and fetch only the requested work list. Up to eight repository
scopes are retained per forge. Valid empty results are cached too.

Refresh explicitly reloads the selected queue and GitHub's visible contribution
header, not every resource. The configured interval controls freshness; stale
visible resources revalidate in the background
while its last-good results remain visible. Inactive providers do not poll. A
failed request neither erases successful results nor advances their freshness.
Caches are session-local and are not written to disk.

Tangled requests are pinned with `tg --account` to the verified account. GitLab requests target the configured host and verify account identity after REST requests.
GitHub requests target github.com explicitly; REST data is withheld until a postflight
account check, and GraphQL calendars include their viewer identity. A detected
account change or logout clears private caches and invalidates pending callbacks.
The separate `gh` processes cannot make credentials atomic against an account
switch and switch-back during a single request; no tokens are read or passed in
arguments. Late same-account responses can fill their own provider/repository
cache without changing the active view.

The following/release feed, Actions dashboard, notification read-state writes,
and independent appearance overrides are still not included. It is not an
editable Kanban board.

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
