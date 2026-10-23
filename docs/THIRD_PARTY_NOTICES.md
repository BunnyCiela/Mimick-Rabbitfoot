# Third-party attribution — worldgen / PRNG

This mod reuses substantial portions of two MIT-licensed open-source Noita
prediction projects. This file records what was reused, where it lives, and the
upstream copyright notices that must travel with it.

Both upstream projects are MIT-licensed; their notices are reproduced in full
below, as the licence requires.

---

## noita-tools (Noitool)

**Upstream:** https://github.com/TwoAbove/noita-tools
**Licence:** MIT — Copyright (c) 2022 Seva Maltsev <me@seva.dev>

Reused in this repository:

| File here | Upstream source | What was reused |
| --- | --- | --- |
| `files/isf/random/prng.lua` | `src/services/SeedInfo/wasm/core/nolla_prng.zig`, `src/services/SeedInfo/wasm/entries/rng.zig` | The position-seeded PRNG: `SetRandomSeed(x,y)` mixing, `Helper2` bit-mixing, the `diddle` correction table, `getDistribution` rejection sampling, and the f32 narrowing behaviour. |
| `tests/worldgen/fixtures/prng_vectors.json` | `src/services/SeedInfo/wasm/rng.wasm` | Reference vectors used as the numeric oracle. |

The port is plain Lua 5.1; the original is Zig compiled to WebAssembly. No
WASM, FFI or native code ships in this mod.

---

## noita-telescope

**Upstream:** https://github.com/Lymm37/noita-telescope
**Licence:** MIT — Copyright (c) 2026 Lymm

Reused in this repository:

| File here | Upstream source | What was reused |
| --- | --- | --- |
| `files/isf/random/prng.lua` | `js/nolla_prng.js` | Cross-checked numeric behaviour and the `Random`/`RandomDistribution` API shape. |
| `files/isf/worldgen/stbhw.lua` | `js/stbhw.js` | The herringbone Wang tile generator: corner-mode colour pass, repetition reduction, canonical tile chooser, and the horizontal/vertical pixel blitters. |
| `files/isf/worldgen/edge_noise.lua`, `data/edge_noise_data.lua` | `js/edge_noise.js`, `js/utils.js`, `js/poi_scanner.js` | Simplex permutation/sign tables, NG0 biome edge noise, ordered neighbor gates, scene-center lookup and terrain scan-point conversion. Biome flags/names are separately extracted from the installed game WAK. |
| `files/isf/worldgen/mines_map.lua` | `js/tile_generator.js` | Region geometry, the `calculateMapDimensions` shortcut, and the exact Wang seeding order including the 1024-repeat and 11/12 phase terms. |
| `files/isf/worldgen/spell_select.lua` | `js/spell_generator.js` | `GetRandomAction` / `GetRandomActionWithType` weighted pool walk. |
| `files/isf/worldgen/wand_gen.lua` | `js/gun_generation.js`, `js/wand_generation.js` | Wand stat generation, shuffle behaviour, Always Cast and in-deck card generation, and the sprite/name rolls that consume RNG. |
| `files/isf/worldgen/data/wand_config.lua` | `js/wand_config.js`, `js/spawn_config.js` | Wand archetypes, stat probability tables, premade wands, sprite shapes, name list, per-biome wand lotteries, altar gates. |

Generated data modules are marked `GENERATED FILE` and carry the upstream notice
in their header.

---

## Spell Lab mechanism inspection (test protection only)

The locally installed Workshop item 2297568811, `files/scripts/player_no_kill.lua`,
was inspected to understand Noita's `damage_about_to_be_received` hook. Our
test-only diagnostic callback independently blocks positive damage and preserves
healing; Spell Lab instead caps damage to leave 0.04 internal HP. No Spell Lab
implementation, GUI, laboratory, gun patches or unlock code is vendored. No
LICENSE was found in the installed item root; no MIT licence is asserted for it.
See `JOINT-TEST-PLAYER-PROTECTION.md` for test scope and cleanup.

---

## Game data

The PNG files listed in `files/isf/worldgen/data/asset_manifest.lua` (all five
regional tilesets, the overlay, biome map and pixel-scene bitmaps) are extracted from the installed Noita
game. They are Nolla Games' assets, used here as data for prediction. They are
not relicensed by this project. The public source repository omits these PNGs
and their generated `png_bytes.lua` representation. `tools/release/build.py`
extracts the required images from the builder's locally owned `data.wak` and
verifies all 167 SHA-256 hashes. The ready-to-play Workshop mod includes the
prediction data for use with Noita; no MIT license is granted to game assets.

## Original work and supplied artwork

Original project code and translations are MIT licensed, Copyright (c) 2026
CloudChaan. Supplied artwork, including `workshop_preview_image.png` and the
charm sprites under `files/isf/cosmetics`, is excluded from the code license.
The mod name and concept are inspired by Rabbit & Steel. This fan mod is not
affiliated with that game's developers or Nolla Games.

---

## FastLZ format reference (offline diagnostic reader)

`tools/validation/read_native_autosave.py` implements bounded decoding of the
observed engine autosave blocks. Level 1/2 token semantics were checked against
[FastLZ's reference source](https://github.com/ariya/FastLZ/blob/master/fastlz.c).
Copyright (C) 2005-2020 Ariya Hidayat. MIT licence; the text below applies.
No native FastLZ binary is bundled by the mod.

## MIT licence text (applies to the upstream projects above)

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
