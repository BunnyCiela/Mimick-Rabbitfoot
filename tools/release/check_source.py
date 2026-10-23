"""Validate public Lua source, language coverage and translation placeholders."""
import csv
import json
import re
import sys
from pathlib import Path
from xml.etree import ElementTree

from lupa import lua51, luajit20

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from generate_locales import render, DEST

LANGUAGES = ["en", "ru", "pt-br", "es-es", "de", "fr-fr", "it", "pl", "zh-cn", "jp", "ko"]
NAMES = ["English", "русский", "Português (Brasil)", "Español", "Deutsch", "Français", "Italiano", "Polska", "简体中文", "日本語", "한국어"]


def main():
    source = json.loads((ROOT / "tools/release/locales.json").read_text(encoding="utf-8"))
    assert set(source["languages"]) == set(LANGUAGES)
    assert DEST.read_text(encoding="utf-8") == render()
    for code, values in source["languages"].items():
        for key, value, reference in zip(source["keys"], values, source["languages"]["en"]):
            assert sorted(re.findall(r"\{\w+\}", value)) == sorted(re.findall(r"\{\w+\}", reference)), (code, key)
    for runtime in (lua51, luajit20):
        lua = runtime.LuaRuntime(unpack_returned_tuples=True)
        compile_lua = lua.eval("function(s) local f,e=loadstring(s);return f~=nil,e end")
        paths = [ROOT / "init.lua", ROOT / "settings.lua"] + list((ROOT / "files").rglob("*.lua")) + list((ROOT / "tools/foundation/diagnostics").glob("*.lua"))
        for path in paths:
            ok, error = compile_lua(path.read_text(encoding="utf-8"))
            assert ok, (str(path), error)
        cache = {}
        def load(path):
            prefix = "mods/interesting_seed_filter/"
            assert path.startswith(prefix), path
            if path not in cache:
                cache[path] = lua.execute((ROOT / path[len(prefix):]).read_text(encoding="utf-8"))
            return cache[path]
        lua.globals().dofile_once = load
        i18n = load("mods/interesting_seed_filter/files/isf/i18n.lua")
        for code, name in zip(LANGUAGES, NAMES):
            api = lua.eval("function(name)return {GameTextGetTranslatedOrNot=function()return name end}end")(name)
            assert i18n.language(api) == code
            for key, value in zip(source["keys"], source["languages"][code]):
                assert i18n.text(key, None, api) == value
            message = i18n.text("success", lua.table(seed=123, attempts=456), api)
            assert "123" in message and "456" in message and "{" not in message
        assert i18n.language(lua.table()) == "en"
        print(runtime.__name__ + ": syntax and all 418 localized strings verified")
    for name in ("mod.xml", "workshop.xml"):
        ElementTree.parse(ROOT / name)
    # If run in an installed game, verify coverage against its actual CSV.
    game_csv = ROOT.parent.parent / "data/translations/common.csv"
    if game_csv.is_file():
        with game_csv.open(encoding="utf-8-sig", newline="") as stream:
            header = next(csv.reader(stream))
        assert header[1:12] == LANGUAGES
        print("Language coverage matches the installed game's translation header")
    print("Source checks passed")


if __name__ == "__main__":
    main()
