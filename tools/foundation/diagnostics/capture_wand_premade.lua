-- Appended after vanilla do_level1(); observer failure cannot change generation.
pcall(function()
 dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/wand_probe.lua").observe_premade(_G)
end)
