"""Run isolated Luau plugin checks using the real parser fixtures."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


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
    sys.exit(result.returncode)
