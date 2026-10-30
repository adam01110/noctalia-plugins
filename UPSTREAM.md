# Compatibility and upstream review

These forks target Noctalia **v5.3.0**, plugin API **34**. All manifests
require API 34; older shells must use an earlier repository revision.
API levels are cumulative minimum requirements, not migration versions.
APIs 29–34 add optional capabilities and require no breaking source migration.
API 35 and later are not available in the installed v5.3.0 shell.

References:

- [API compatibility table](https://docs.noctalia.dev/noctalia/plugins/development/plugin-api/)
- [Noctalia v5.3.0](https://github.com/noctalia-dev/noctalia/releases/tag/v5.3.0)
- [Reviewed community snapshot](https://github.com/noctalia-dev/community-plugins/tree/a5b079de458e68874a3222eeab3345d8d3d28db8)

## Custom plugin

**Albedo Monitor** (`adam0/albedo-monitor`) is an original API-34 plugin inspired
by Bloom’s session and usage indicator. It uses an albedo-suite helper and the
Albedo daemon, not Bloom’s code or Claude Code hooks. The shell owns the outer
popup outline; the panel defaults to floating placement so that outline is
visible. Session/account cards retain configured outlines. Header buttons
use native default surfaces, matching Color Picker. Secondary and bar text use
a 12px base; section and card headings use 14px, before native accessibility
scaling.

## Fork changes

- **Forges:** adapted Shangshui0302's GitHub Kanban 0.2.6 from
  [`63150dc53560297140164083b4d14d4aaaf59bc8`](https://github.com/noctalia-dev/community-plugins/tree/63150dc53560297140164083b4d14d4aaaf59bc8/github-kanban)
  as `adam0/forges`, targeting API 34 rather than upstream API 43. Tangled via
  `tg` is the startup default, with a session provider switch and shared
  repository/PR/issue lists, plus native monthly activity. GitHub also has a
  paged read/all/unread inbox. Per-provider/resource caches avoid unrelated
  refetches on navigation. Custom radii and
  outlines follow shell settings, and the panel defaults to floating near-click
  placement. See [Forges setup and scope](forges/SETUP.md) for retained features
  and intentional differences. Upstream declares MIT but supplies no separate
  license file in this snapshot. The native six-month activity model is adapted
  from Tangled's `ProfileActivityChart.svelte` / `profileActivityChart.ts` at
  [`6598d2fc5d76dbdee20fae59801b6b35973d8836`](https://tangled.org/tangled.org/core/tree/6598d2fc5d76dbdee20fae59801b6b35973d8836/web/src/lib/components/profile).
  The original MIT notice is retained in `forges/TANGLED-LICENSE`. The Luau adaptation
  preserves Tangled's layout with transparent native graph layers beneath a
  six-column native label/glyph table;
  it imports neither SVG images nor Svelte/web scaffolding.
- **Keybind Cheatsheet:** synchronized the upstream 0.3.2 parser and panel,
  including staged parsing and progressive rendering to stay within callback
  CPU budgets, Fcitx5 hotkeys, sequential-binding grouping, modifier labels,
  keyboard names, and fixture files. Retained the local five-column cap.
  Also invalidate cached rows when settings change, so modifier labels update.
- **Nix Monitor:** retained the local 2.0 generation/store-only fork. Upstream
  1.3.1's nixpkgs branch polling and update controls are intentionally excluded;
  restoring them would undo the local scope reduction. Upstream entry names
  `nix_monitor.luau` and `nix_monitor_service.luau` map to local `widget.luau`
  and `service.luau`.
- **Udiskie Manager:** uses the distinct `adam0/udiskie` ID, including its panel
  and service IPC targets. The panel retains local corner-radius scaling and
  uses native default button surfaces for Settings. API 34 remains the latest
  released API supported by Noctalia v5.3.0.
- **NoctaProton VPN:** forked community 1.0.1 as `adam0/noctaproton-vpn`.
  Custom surfaces scale their radii with `shell.corner_radius_scale`, including
  square corners. Floating placement enables Noctalia’s outer popup outline;
  card outlines use `shell.panel.borders`, `border_width`, and `border_color`.
  Buttons use native surface styling rather than transparent outlined variants.
  Targets API 34.
- **World Clock:** imported official 1.2.1 from
  [`e1eac19947d4dbb7adb5a22c1de41ec348c4ca3d`](https://github.com/noctalia-dev/official-plugins/tree/e1eac19947d4dbb7adb5a22c1de41ec348c4ca3d/world_clock)
  as 1.2.2 targeting API 34. Retains the `noctalia/world_clock` ID and Noctalia
  attribution so existing settings and persisted zones remain compatible.
  Upstream declares MIT in its manifest; that snapshot ships no separate license
  file. Only runtime files and the English translation are imported. Zone cards
  and drop targets follow the shell corner-radius scale, cards have outlines,
  and the Add button and input share the native `md` control-height tier.

## Checks

```sh
noctalia plugins lint .
python3 tests/run.py /path/to/luau
nix fmt
nix flake check --no-update-lock-file
```

The isolated Luau tests cover the five upstream parser fixture cases, a
180-binding staged Niri refresh, last-good recovery after a failed refresh,
progressive panel opening/closing, and keyboard names.
Albedo checks cover the poller, literal command arguments, active/waiting
subagents, quota windows, stale data, failure recovery, and bounded panel lists.
World Clock checks cover card outlines, radius settings, matched control heights,
and zone commands. They do not exercise compositor surfaces or real
device/rebuild actions.
