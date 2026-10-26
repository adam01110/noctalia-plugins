"""Run isolated Luau plugin checks using the real parser fixtures."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]

# Noctalia draws shell.panel borders only for floating panel surfaces.
for plugin in ("albedo-monitor", "noctaproton-vpn", "forges"):
    manifest = tomllib.loads((ROOT / plugin / "plugin.toml").read_text())
    if plugin == "forges":
        assert manifest["plugin_api"] == 34, "Forges must remain compatible with API 34"
        assert manifest["panel"][0]["height"] == 800, "Forges needs the requested taller workspace"
    panel = manifest["panel"][0]
    assert panel["placement"] == "floating", f"{plugin}: popup must use native floating borders"
    assert panel["position"] == "auto" and panel["open_near_click"] is True
print("Panel placement regression checks passed", flush=True)


def lua_value(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "nil"
    if isinstance(value, list):
        return "{" + ",".join(lua_value(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join(
            "[" + lua_value(key) + "]=" + lua_value(item)
            for key, item in value.items()
        ) + "}"
    return str(value)


with tempfile.TemporaryDirectory(prefix="noctalia-plugin-tests-") as directory:
    target = Path(directory) / "keybind-cheatsheet"
    shutil.copytree(ROOT / "keybind-cheatsheet", target)
    fixtures = {}
    for path in (target / "tests" / "fixtures").rglob("*"):
        if path.is_file():
            text = path.read_text()
            fixtures["/plugin/tests/" + str(path.relative_to(target / "tests"))] = (
                json.loads(text) if path.suffix == ".json" else text
            )
    fixtures["/plugin/tests/expected.json"] = json.loads(
        (target / "tests/expected.json").read_text()
    )
    fixtures["translations"] = json.loads((target / "translations/en.json").read_text())
    (target / "tests/fixture_data.luau").write_text("return " + lua_value(fixtures))
    result = subprocess.run(
        [sys.argv[1] if len(sys.argv) > 1 else "luau", str(target / "tests/run.luau")],
        check=False,
    )
    if result.returncode:
        sys.exit(result.returncode)
    albedo_test = Path(directory) / "albedo.luau"
    source = (ROOT / "tests/albedo.luau").read_text()
    for marker, filename in (
        ("SERVICE_SOURCE", "service.luau"),
        ("STATUS_SOURCE", "status.luau"),
        ("PANEL_SOURCE", "panel.luau"),
    ):
        source = source.replace("-- " + marker, (ROOT / "albedo-monitor" / filename).read_text())
    albedo_test.write_text(source)
    result = subprocess.run(
        [sys.argv[1] if len(sys.argv) > 1 else "luau", str(albedo_test)], check=False
    )
    if result.returncode:
        sys.exit(result.returncode)
    udiskie_test = Path(directory) / "udiskie.luau"
    source = (ROOT / "tests/udiskie.luau").read_text()
    for marker, filename in (
        ("PANEL_SOURCE", "panel.luau"),
        ("STATUS_SOURCE", "status.luau"),
    ):
        source = source.replace("-- " + marker, (ROOT / "udiskie" / filename).read_text())
    udiskie_test.write_text(source)
    result = subprocess.run(
        [sys.argv[1] if len(sys.argv) > 1 else "luau", str(udiskie_test)], check=False
    )
    if result.returncode:
        sys.exit(result.returncode)
    vpn_test = Path(directory) / "noctaproton.luau"
    source = (ROOT / "tests/noctaproton.luau").read_text()
    for marker, filename in (("PANEL_SOURCE", "panel.luau"), ("BAR_SOURCE", "bar.luau"), ("SERVICE_SOURCE", "service.luau")):
        source = source.replace("-- " + marker, (ROOT / "noctaproton-vpn" / filename).read_text())
    vpn_test.write_text(source)
    result = subprocess.run(
        [sys.argv[1] if len(sys.argv) > 1 else "luau", str(vpn_test)], check=False
    )
    if result.returncode:
        sys.exit(result.returncode)
    forges_test = Path(directory) / "forges.luau"
    source = (ROOT / "tests/forges.luau").read_text()
    for marker, filename in (
        ("GITHUB_SOURCE", "lib/github.luau"),
        ("DATA_SOURCE", "lib/data.luau"),
        ("TANGLED_SOURCE", "lib/tangled.luau"),
        ("SERVICE_SOURCE", "service.luau"),
        ("PANEL_SOURCE", "panel.luau"),
        ("WIDGET_SOURCE", "widget.luau"),
    ):
        content = (ROOT / "forges" / filename).read_text()
        if filename == "service.luau":
            for module in ("GitHub", "Data", "Tangled"):
                content = content.replace(
                    'require("./lib/' + module.lower() + '.luau")', module
                )
        source = source.replace("-- " + marker, content)
    forges_test.write_text(source)
    result = subprocess.run(
        [sys.argv[1] if len(sys.argv) > 1 else "luau", str(forges_test)], check=False
    )
    if result.returncode:
        sys.exit(result.returncode)
    world_clock_test = Path(directory) / "world-clock.luau"
    source = (ROOT / "tests/world-clock.luau").read_text()
    source = source.replace("-- PANEL_SOURCE", (ROOT / "world-clock/panel.luau").read_text())
    world_clock_test.write_text(source)
    result = subprocess.run(
        [sys.argv[1] if len(sys.argv) > 1 else "luau", str(world_clock_test)], check=False
    )
    sys.exit(result.returncode)
