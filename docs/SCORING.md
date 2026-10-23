# Prediction and scoring scope

Mimick Rabbitfoot searches the main world's normal NG0 seeds before generation.
It uses a read-only snapshot of the player's unlocks, persistent generation
conditions and game calendar. Continuing a save does not run another search.

The model considers selected natural wands and their spells, Always Cast,
known chests and puzzle rewards, selected potion/powder contents, Holy Mountain
shops and perk opportunities. Default depth includes three Holy Mountain shops
and two Holy Mountain perk rows; the depth setting extends both through the
selected mountain, up to the Laboratory.

This is a practical resource model, not an exhaustive simulation of every
resource in Noita. Natural liquid pools, special containers and unvalidated
puzzle variants are outside the accepted scoring scope. The current version only works with vanilla Noita and is incompatible with any mods that add or modify game content. A good total does not
guarantee an easy start or that all counted opportunities can be collected.

Rule version 2.0 deduplicates physical resources first. For each normal spell
ID across all scored sources, occurrences are sorted by descending base value
and then stable resource ID. Each successive occurrence retains half the
previous weight: 1, 1/2, 1/4, 1/8, and so on. Always Cast is excluded from this
decay. Perk opportunities are deduplicated by perk type. Candidate state is
reset between seeds.

Luck gates use empirical calibration from one million candidate seeds at each
of five search depths. The game profile is read for actual prediction; the
existing reference gates apply across unlock/calendar profiles. Distribution
percentiles for a different profile are not guaranteed. Gate data and its
reference profile remain inspectable in `files/isf/data/luck_calibration.lua`.

The predictor is deterministic and does not consume the game's RNG. Only the
selected world seed is committed through the official pre-generation hook.
The rabbit foot is a separate cosmetic effect with its own local random stream.
