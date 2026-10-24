<!-- rumdl-disable MD033 MD041 -->

<div align="center">

# noctalia-plugins

Customized [Noctalia](https://github.com/noctalia-dev/noctalia) plugins used
by my system configuration.

[![Noctalia](https://img.shields.io/badge/Noctalia-plugins-458588?style=flat-square&labelColor=504945)](https://github.com/noctalia-dev/noctalia)
[![Nix](https://img.shields.io/badge/Nix-flake-689d6a?style=flat-square&labelColor=504945&logo=nixos&logoColor=ebdbb2)](https://nixos.org)

[Plugins](#plugins) - [Usage](#usage) - [Dependencies](#dependencies) - [Development](#development)

</div>

<!-- rumdl-enable MD033 MD041 -->

This collection contains community Noctalia plugin forks and a custom Albedo
monitor.

## Plugins

| Plugin | ID | Origin |
| --- | --- | --- |
| [Albedo Monitor](./albedo-monitor) | `adam0/albedo-monitor` | Custom plugin, inspired by [Bloom](https://noctalia.dev/plugins/community/bloom) |
| [CodexBar Meter](./codexbar-meter) | `salemsayed/codexbar-meter` | [Community plugin](https://github.com/noctalia-dev/community-plugins/tree/main/codexbar-meter) |
| [Keybind Cheatsheet](./keybind-cheatsheet) | `kenn/keybind-cheatsheet` | [Community plugin](https://github.com/noctalia-dev/community-plugins/tree/main/keybind-cheatsheet) |
| [Nix Monitor](./nix-monitor) | `avivbintangaringga/nix-monitor` | [community plugin](https://github.com/noctalia-dev/community-plugins/tree/main/nix-monitor) |
| [Udiskie Manager](./udiskie) | `adam0/udiskie` | [Community plugin](https://github.com/noctalia-dev/community-plugins/tree/main/udiskie) |

Forks retain upstream author identities. Udiskie Manager uses `adam0/udiskie`
to distinguish it from the community copy. Albedo Monitor uses its own ID and
reads Albedo directly rather than Claude Code hooks.

## Usage

### Nix flake

Add the repository as a flake input:

```nix
{
  inputs.noctalia-plugins.url = "path:/absolute/path/to/noctalia-plugins";
}
```

Use `inputs.noctalia-plugins.lib.source` wherever the configuration expects the
plugin source path.

### Noctalia path source

Clone the repository, then add its root directly as a local Noctalia path source:

```bash
noctalia msg plugins source add local path /absolute/path/to/noctalia-plugins
```

The plugins can then be enabled and configured through Noctalia's plugin settings.

## Dependencies

Noctalia resolves each plugin's declared command dependencies. The main
external tools are:

| Plugin | Commands |
| --- | --- |
| Albedo Monitor | `albedo-monitor` from albedo-suite, `timeout` |
| CodexBar Meter | `codexbar`, `timeout` |
| Keybind Cheatsheet | `hyprctl` |
| Nix Monitor | `nix`, `nix-store`, `nixos-rebuild`, plus standard shell utilities |
| Udiskie Manager | `udiskie`, `udisks2`, `xdg-open` |

## Development

From the repository root:

```bash
# Format every supported file
nix fmt

# Run flake and formatter checks
nix flake check
```
