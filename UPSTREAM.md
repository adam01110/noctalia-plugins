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
Albedo daemon, not Bloom’s code or Claude Code hooks.

## Fork changes

- **CodexBar Meter:** ported upstream's compact/standard/tall panel selection.
  The existing public `panel` ID remains available. The compact tier retains
  the local 404-pixel height; standard and tall tiers use 560 and 720 pixels.
  Kept local corner-radius scaling, glyph sizing, and pace-label layout.
  Content-driven height is not used because it requires API 42.
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
  gives the Settings button an outline when idle. API 34 remains the latest
  released API supported by Noctalia v5.3.0.
- **NoctaProton VPN:** forked community 1.0.1 as `adam0/noctaproton-vpn`.
  Custom surfaces scale their radii with `shell.corner_radius_scale`, including
  square corners. The popup and cards use `shell.panel.borders`, `border_width`,
  and `border_color`; native controls retain shell styling. Targets API 34.

## Checks

```sh
noctalia plugins lint .
python3 tests/run.py /path/to/luau
nix fmt
nix flake check --no-update-lock-file
```

The isolated Luau tests cover the five upstream parser fixture cases, a
180-binding staged Niri refresh, last-good recovery after a failed refresh,
progressive panel opening/closing, keyboard names, and CodexBar panel tiers.
Albedo checks cover the poller, literal command arguments, active/waiting
subagents, quota windows, stale data, failure recovery, and bounded panel lists.
They do not exercise compositor surfaces or real device/rebuild actions.
