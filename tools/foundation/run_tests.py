"""Development-only Lua test harness for the ISF foundation modules (ISF-01).

Loads the *production* Lua files into a Lua 5.1 sandbox (via lupa) and exercises
them through their documented external interfaces. Nothing here is shipped and
the runtime modules never call into Python.

Path handling is deliberately strict: Noita's `dofile_once` addresses the game's
virtual filesystem root, where the mod's own files live under
`mods/interesting_seed_filter/...`. The harness therefore rejects a bare
`files/isf/...` path instead of silently mapping it to the project directory,
because such a path would work in tests and fail in the game.

Usage:
    python tools/foundation/run_tests.py                 # all foundation specs
    python tools/foundation/run_tests.py spell_score_spec  # one spec
    python tools/foundation/run_tests.py --verbose
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from lupa import lua51

PROJECT_ROOT = Path(__file__).resolve().parents[2]
FILES_DIR = PROJECT_ROOT / "files"
TESTS_DIR = PROJECT_ROOT / "tests" / "foundation"
FIXTURES_DIR = TESTS_DIR / "fixtures"

MOD_ID = "interesting_seed_filter"
MOD_PREFIX = f"mods/{MOD_ID}/"


class PathPolicyError(Exception):
    """Raised when Lua asks for a path that would not resolve in the game."""


class LuaTestEnv:
    """A Lua 5.1 sandbox with a strict, mod-namespaced module loader."""

    def __init__(self, verbose: bool = False) -> None:
        self.verbose = verbose
        self.loaded_paths: list[str] = []
        self.rejected_paths: list[str] = []
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self._install_loader()
        self._install_globals()

    # -- loading -----------------------------------------------------------
    def _install_loader(self) -> None:
        # The mod prefix is stripped and the remainder is resolved from the
        # project root, so "mods/<mod>/files/isf/core/units.lua" maps onto
        # <project>/files/isf/core/units.lua -- exactly the game's layout.
        self.lua.globals()["ISF_PROJECT_ROOT"] = str(PROJECT_ROOT).replace("\\", "/")
        self.lua.globals()["ISF_MOD_PREFIX"] = MOD_PREFIX
        self.lua.execute(
            """
            local ROOT = ISF_PROJECT_ROOT
            local PREFIX = ISF_MOD_PREFIX
            local loaded = {}
            local order = {}

            -- Record what the harness has been asked for, so Python can assert
            -- on the exact dofile_once paths the production code used.
            __isf_requests = {}
            -- Set to true by the harness once it wants a recorded request list.
            __isf_record = true

            function __isf_resolve(path)
                if type(path) ~= "string" or path == "" then
                    error("load: path must be a non-empty string", 3)
                end
                -- A game-virtual path must start with the mod prefix. A bare
                -- project-relative path would resolve here but NOT in the game,
                -- so it is rejected loudly instead of being papered over.
                if string.sub(path, 1, #PREFIX) ~= PREFIX then
                    error("load: path '" .. path .. "' is not under '" .. PREFIX ..
                          "' (Noita's dofile_once resolves the game virtual root, " ..
                          "not the project directory)", 3)
                end
                local rel = string.sub(path, #PREFIX + 1)
                return ROOT .. "/" .. rel, rel
            end

            function __isf_load(path)
                local abs, rel = __isf_resolve(path)
                if __isf_record then
                    __isf_requests[#__isf_requests + 1] = { path = path, rel = rel }
                end
                if loaded[rel] ~= nil then return loaded[rel] end
                local chunk, err = loadfile(abs)
                if not chunk then
                    error("load: cannot open " .. abs .. ": " .. tostring(err), 2)
                end
                local value = chunk()
                if value == nil then
                    value = true   -- Lua caches `true` when a chunk returns nil
                end
                loaded[rel] = value
                order[#order + 1] = rel
                return value
            end

            function __isf_loaded()
                return order
            end

            -- Noita only exposes dofile_once in scripts; provide exactly that
            -- name so production code paths are exercised unchanged.
            function dofile_once(path)
                return __isf_load(path)
            end
            """
        )

    def _install_globals(self) -> None:
        # Noita exposes a handful of globals that modules may touch defensively.
        # Provide recording stand-ins so tests can prove no game state is written.
        self.lua.execute(
            """
            __game_state_calls = {}
            local function record(name, ret)
                return function(...)
                    __game_state_calls[#__game_state_calls + 1] = {
                        name = name, n = select('#', ...),
                    }
                    return ret
                end
            end
            SetWorldSeed       = record("SetWorldSeed", nil)
            SetRandomSeed      = record("SetRandomSeed", nil)
            Random             = record("Random", 0)
            AddFlagPersistent  = record("AddFlagPersistent", false)
            RemoveFlagPersistent = record("RemoveFlagPersistent", nil)
            GlobalsSetValue    = record("GlobalsSetValue", nil)
            GameAddFlagRun     = record("GameAddFlagRun", nil)
            GamePrint          = function(...) end
            print             = function(...) end
            """
        )

    # -- helpers -----------------------------------------------------------
    def load(self, relpath: str):
        if not relpath.startswith(MOD_PREFIX):
            raise PathPolicyError(
                f"harness caller must pass a mod-namespaced path, got {relpath!r}"
            )
        # Index explicitly: a `.__isf_load` attribute would be mangled by Python
        # inside this class body.
        return self.lua.globals()["__isf_load"](relpath)

    def run_file(self, path: Path) -> None:
        chunk = self.lua.eval(
            "function(p) local f, err = loadfile(p); if not f then error(err, 0) end; return f end"
        )
        chunk(str(path).replace("\\", "/"))()

    def requests(self) -> list[dict]:
        reqs = self.lua.globals()["__isf_requests"]
        out = []
        if reqs is None:
            return out
        for i in range(1, len(reqs) + 1):
            item = reqs[i]
            out.append({"path": item.path, "rel": item.rel})
        return out

    def game_state_calls(self) -> list[str]:
        calls = self.lua.globals()["__game_state_calls"]
        out = []
        if calls is None:
            return out
        for i in range(1, len(calls) + 1):
            out.append(calls[i].name)
        return out

    def loaded_modules(self) -> list[str]:
        fn = self.lua.globals()["__isf_loaded"]
        if fn is None:
            return []
        return _lua_to_py(fn()) or []


class Registry:
    def __init__(self) -> None:
        self.passed = 0
        self.failed = 0
        self.failures: list[str] = []
        self.current = "<none>"

    def check(self, condition: bool, message: str) -> None:
        if condition:
            self.passed += 1
            return
        self.failed += 1
        self.failures.append(f"[{self.current}] {message}")

    def equal(self, actual, expected, message: str) -> None:
        ok = actual == expected
        if not ok and isinstance(actual, float) and isinstance(expected, float):
            ok = math.isclose(actual, expected, rel_tol=0.0, abs_tol=1e-9)
        self.check(ok, f"{message}: expected {expected!r}, got {actual!r}")


REG = Registry()


def _py_to_lua(lua, value):
    if isinstance(value, dict):
        tbl = lua.table()
        for k, v in value.items():
            tbl[k] = _py_to_lua(lua, v)
        return tbl
    if isinstance(value, list):
        tbl = lua.table()
        for i, v in enumerate(value, start=1):
            tbl[i] = _py_to_lua(lua, v)
        return tbl
    return value


def _lua_to_py(value):
    if value is None:
        return None
    t = type(value).__name__
    if t in ("_LuaTable", "LuaTable"):
        # Array-like tables become lists, maps become dicts.
        keys = list(value.keys())
        if keys and all(isinstance(k, int) for k in keys):
            if keys == list(range(1, len(keys) + 1)):
                return [_lua_to_py(value[i]) for i in range(1, len(keys) + 1)]
        return {k: _lua_to_py(value[k]) for k in keys}
    return value


def _make_test_api(env: LuaTestEnv):
    lua = env.lua

    def check(condition, message):
        REG.check(bool(condition), message)

    def equal(actual, expected, message):
        REG.equal(actual, expected, message)

    def equal_int(actual, expected, message):
        if actual is None:
            REG.check(False, f"{message}: nil actual")
            return
        REG.check(int(actual) == int(expected), f"{message}: expected {expected!r}, got {actual!r}")

    def describe(name):
        REG.current = name
        return _NullCtx()

    fixture_cache: dict[str, object] = {}

    def fixture(name):
        if name not in fixture_cache:
            data = json.loads((FIXTURES_DIR / name).read_text(encoding="utf-8"))
            fixture_cache[name] = _py_to_lua(lua, data)
        return fixture_cache[name]

    def load(relpath):
        return env.load(relpath)

    def assert_path_rejected(relpath):
        """Prove the harness rejects game-invalid paths instead of mapping them."""
        try:
            env.load(relpath)
        except Exception:  # noqa: BLE001 - any refusal is the point
            return True
        return False

    def to_py(value):
        return _lua_to_py(value)

    def read_bytes(relpath):
        """Raw bytes of a project file, for binary assets like worldgen PNGs.

        Returns Python `bytes`; lupa hands that to Lua as a byte string, which is
        what `png.decode` expects (a latin-1 `str` round-trip mangles the PNG
        signature). Development only: production injects a game-backed reader
        into files/isf/core/assets.lua instead.
        """
        return (PROJECT_ROOT / relpath).read_bytes()

    return lua.table(
        check=check,
        equal=equal,
        equal_int=equal_int,
        describe=describe,
        fixture=fixture,
        load=load,
        assert_path_rejected=assert_path_rejected,
        to_py=to_py,
        read_bytes=read_bytes,
        fail=lambda message: REG.check(False, message),
        log=lambda message: print(f"   - {message}"),
    )


class _NullCtx:
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


POLICY_SPEC = "_policy_spec.lua"


def write_policy_spec() -> Path:
    """Emit the path-policy spec: bare project paths must be rejected."""
    TESTS_DIR.mkdir(parents=True, exist_ok=True)
    path = TESTS_DIR / POLICY_SPEC
    path.write_text(
        """-- tests/foundation/_policy_spec.lua
--
-- Generated by tools/foundation/run_tests.py. Guards the Noita filesystem
-- namespace rule: production code must address the game virtual root through
-- "mods/interesting_seed_filter/...", never a bare project-relative path.

T.describe("path policy: mod-namespaced dofile_once")
T.check(T.assert_path_rejected("files/isf/core/units.lua"),
  "bare project-relative path is rejected, not silently remapped")
T.check(T.assert_path_rejected("isf/core/units.lua"),
  "unprefixed project path is rejected")
T.check(T.assert_path_rejected("mods/other_mod/files/isf/core/units.lua"),
  "another mod's namespace is not substituted for ours")
do
  local mod = T.load("mods/interesting_seed_filter/files/isf/core/units.lua")
  T.check(type(mod) == "table", "mod-namespaced path loads the production module")
  T.check(mod.UNITS_PER_POINT == 4, "units module reports 4 units per point")
end
""",
        encoding="utf-8",
    )
    return path


def main(argv: list[str]) -> int:
    verbose = "--verbose" in argv
    selected = [a for a in argv[1:] if not a.startswith("--")] or None

    write_policy_spec()
    spec_files = sorted(TESTS_DIR.glob("*_spec.lua"))
    if selected:
        spec_files = [p for p in spec_files if p.stem in selected]
        if not spec_files:
            print(f"no spec files matched {selected}", file=sys.stderr)
            return 2

    env = LuaTestEnv(verbose=verbose)
    env.lua.globals()["T"] = _make_test_api(env)
    env.lua.globals()["FIXTURES"] = str(FIXTURES_DIR).replace("\\", "/")

    for path in spec_files:
        print(f"\n=== {path.name} ===")
        try:
            env.run_file(path)
        except Exception as exc:  # noqa: BLE001
            REG.failed += 1
            REG.failures.append(f"[{path.name}] uncaught Lua error: {exc}")

    # Cross-cutting invariant: production code only ever asked for
    # mod-namespaced paths.
    reqs = env.requests()
    bad = [r for r in reqs if not r["path"].startswith(MOD_PREFIX)]
    REG.check(not bad, f"all dofile_once paths are mod-namespaced (offenders: {bad})")
    REG.check(len(reqs) > 0, "production code performed at least one dofile_once")

    writes = env.game_state_calls()
    forbidden = {
        "SetWorldSeed",
        "SetRandomSeed",
        "AddFlagPersistent",
        "RemoveFlagPersistent",
        "GlobalsSetValue",
        "GameAddFlagRun",
    }
    touched = sorted(set(writes) & forbidden)
    REG.check(not touched, f"no game-RNG or persistent-state writes (offenders: {touched})")

    if verbose:
        print("\nloaded modules:")
        for name in env.loaded_modules():
            print(f"  - {name}")

    print(f"\n{REG.passed} checks passed, {REG.failed} failed")
    if REG.failures:
        print("\nFailures:")
        for f in REG.failures:
            print(f"  - {f}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
