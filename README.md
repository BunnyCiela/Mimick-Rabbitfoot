# 假兔脚 · Mimick Rabbitfoot

*灵感来自游戏《兔子与钢铁》的同名战利品。*

令你运气显著变好。<br>
不是真的兔脚。

**Makes you significantly luckier.<br>
Not a real rabbit's foot.**

![Mimick Rabbitfoot](workshop_preview_image.png)

[Steam Workshop / 创意工坊](https://steamcommunity.com/sharedfiles/filedetails/?id=3825300539) · [Source / 开源代码](https://github.com/CloudChaan/Mimick-Rabbitfoot)

假兔脚为 Noita 的普通新游戏筛选更幸运的随机种子。它预测种子中的资源并选择达到目标幸运度的世界，不修改法术、天赋、掉落概率、敌人或玩家属性。腰间的兔脚只提供外观效果，可以在设置中关闭。

在模组设置中选择 **Lv0–Lv6 幸运度**，也可以增加圣山探查深度。设置在下次新游戏生效，继续已有游戏不会重新筛种。高幸运度可能延长新游戏加载时间；深处奖励较好不保证开局更容易。

Mimick Rabbitfoot searches for luckier random world seeds before a normal Noita run starts. It predicts resources and chooses a seed that meets your selected luck level. It does not change spells, perks, drop rates, enemies, or player stats. The belt charm is cosmetic and can be disabled.

Choose **Lv0–Lv6** in Mod Settings, with optional deeper Holy Mountain searches. Search settings apply to your next new game. Continuing a save preserves its seed. Higher luck can take longer to load; better rewards deeper down do not guarantee an easier start. Intended for normal NG0 runs in the main world; other world-generation mods may affect prediction accuracy.

## Languages

Follows the game's current language, including live changes in Mod Settings: English, русский, Português (Brasil), Español, Deutsch, Français, Italiano, Polski, 简体中文, 日本語, 한국어. All 11 languages include setting labels, descriptions, luck levels, warnings and runtime messages. English is the fallback when the game language cannot be read.

## Build from source

Requires Python 3.10+ and your own installed copy of Noita. This repository contains the Lua predictor, scoring and calibration, game adapters, cosmetic charm, translations, and opt-in diagnostic scripts. Runtime code uses Lua 5.1; no Python, native library or unrestricted API access is needed while playing.

The game's 167 map images and generated `png_bytes.lua` are deliberately omitted from Git. Build them locally from your game's `data/data.wak`:

```powershell
python tools/release/generate_locales.py --check
python tools/release/build.py --wak "D:/SteamLibrary/steamapps/common/Noita/data/data.wak"
```

The builder verifies each extracted image's SHA-256 before creating `dist/interesting_seed_filter` and a ZIP. It refuses to overwrite an existing output folder. Copy the resulting `interesting_seed_filter` folder into Noita's `mods` directory and enable **假兔脚 (Mimick Rabbitfoot)**. Keep this folder name because Noita's virtual paths use it. Use a fresh output folder for each build. Workshop subscribers receive the ready-to-play package.

## Code map

- `files/isf/core`, `providers`, `items`, `chests`, `worldgen`, `random`: deterministic resource prediction and scoring.
- `files/isf/runtime`, `adapters`, `data/luck_calibration.lua`: pre-generation search, game profile and calibrated gates.
- `files/isf/cosmetics`: independent visual charm; does not consume the game's random stream.
- `files/isf/i18n.lua`, `i18n/catalog.lua`: language resolution and generated locale catalog.
- `tools/release/locales.json`: translation source; run `generate_locales.py` after edits.
- `tools/foundation/diagnostics`: developer capture, disabled by default; not required to play.

The practical model covers selected resources and known puzzle variants; it does not claim exhaustive world prediction. See [scoring scope](docs/SCORING.md).

## License and credits

Original code and translations are [MIT licensed](LICENSE). Upstream MIT notices are retained in [THIRD_PARTY_NOTICES](docs/THIRD_PARTY_NOTICES.md). Noita and its game assets belong to Nolla Games and are not relicensed under MIT. Artwork, including the supplied Workshop preview and charm sprites, is excluded from the code license. Rabbit & Steel is credited as inspiration; this project is an independent fan mod.

Source: https://github.com/CloudChaan/Mimick-Rabbitfoot
