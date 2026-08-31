# Noctalia plugins

Customized [Noctalia](https://github.com/noctalia-dev/noctalia) plugins used
by Adam's system configuration.

## Plugins

| Directory | Plugin ID | Origin |
| --- | --- | --- |
| `codexbar-meter` | `salemsayed/codexbar-meter` | [Noctalia community plugins](https://github.com/noctalia-dev/community-plugins/tree/main/codexbar-meter) |
| `keybind-cheatsheet` | `kenn/keybind-cheatsheet` | [Noctalia community plugins](https://github.com/noctalia-dev/community-plugins/tree/main/keybind-cheatsheet) |
| `nix-monitor` | `avivbintangaringga/nix-monitor` | Debloated fork of [the community plugin](https://github.com/noctalia-dev/community-plugins/tree/main/nix-monitor) |
| `performance` | `adam0/performance` | Original plugin |
| `udiskie` | `aristides/udiskie` | [Noctalia community plugins](https://github.com/noctalia-dev/community-plugins/tree/main/udiskie) |

Performance is original. Every other plugin is a fork with local modifications.
Upstream author identities are retained; Nix Monitor is primarily a debloated
variant.

## Use as a source

Add the repository root as a Noctalia path source:

```sh
noctalia msg plugins source add local path ~/Projects/noctalia-plugins
```
