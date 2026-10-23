-- files/isf/shops/predict.lua
--
-- ISF-08 card-content prediction for ONE wild spell shop slot.
--
-- Vanilla chain this reproduces (data/scripts/items/generate_shop_item.lua):
--
--   function generate_shop_item( x, y, cheap_item, biomeid_, is_stealable )
--       SetRandomSeed( x, y )
--       ...
--       local level = biomeid          -- BEFORE biomeid is squared for pricing
--       item = GetRandomAction( x, y, level, 0 )
--       local eid = CreateItemActionEntity( item, x, y )
--
-- So the card is a pure function of (world_seed, slot_x, slot_y, level):
--   * the placement is the slot's world position (scene origin + marker offset),
--   * `level` is the biome's `biomeid_` argument (Mines 1, Coal Pits 2,
--     Snowy Depths 3 — see files/isf/data/shops.lua),
--   * the offset argument to GetRandomAction is 0,
--   * the initial SetRandomSeed(x, y) does not affect the card, because
--     GetRandomAction seeds its own PRNG from the world seed and (x, y).
--
-- SUBSTANTIAL REUSE — this module deliberately implements NO selection
-- algorithm, spell pool or unlock rule of its own:
--
--   * the weighted walk is files/isf/worldgen/spell_select.lua
--     get_random_action(), itself a port of
--     noita-telescope js/spell_generator.js GetRandomAction / GetRandomActionWithType
--     (MIT, Copyright (c) 2026 Lymm);
--   * the pool is files/isf/data/spells.lua (foundation, extracted from the
--     installed gun_actions.lua);
--   * the unlock predicate and the spell_select wiring come from
--     files/isf/providers/wild_wands.lua configure(), exactly as the chests
--     provider does — one wand/spell implementation in the project, not two;
--   * the PRNG is files/isf/random/prng.lua (one instance per draw site, no
--     shared mutable state).
--
-- What is shop-specific here is only the call shape above (level, offset 0) and
-- the refusal to guess: a walk that yields no card is reported as an
-- unresolved slot, never silently turned into "no card was sold".
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

-- GetRandomAction's offset argument in generate_shop_item is the literal 0.
M.SEED_OFFSET = 0

-- Frames this module can seed from. The vanilla shop slot comes from a pixel
-- scene placement plus an integer marker offset, so only the integer world
-- frame is modelled. Anything else is refused rather than rounded.
M.FRAME = "slot_world_position_integer"

local spell_select = nil
local wild_wands = nil
local spells = nil
local wand_cfg = nil
local configured_for = nil
local configured_unlocked = nil

local function deps()
	if ( spell_select == nil ) then
		spell_select = dofile_once(
			"mods/interesting_seed_filter/files/isf/worldgen/spell_select.lua" )
		if ( type( spell_select ) ~= "table" ) then
			error( "shops/predict: files/isf/worldgen/spell_select.lua did not return a table" )
		end
		wild_wands = dofile_once(
			"mods/interesting_seed_filter/files/isf/providers/wild_wands.lua" )
		if ( type( wild_wands ) ~= "table" ) then
			error( "shops/predict: files/isf/providers/wild_wands.lua did not return a table" )
		end
		spells = dofile_once( "mods/interesting_seed_filter/files/isf/data/spells.lua" )
		wand_cfg = dofile_once(
			"mods/interesting_seed_filter/files/isf/worldgen/data/wand_config.lua" )
		if ( type( spells ) ~= "table" or type( wand_cfg ) ~= "table" ) then
			error( "shops/predict: spell pool or wand config did not return a table" )
		end
	end
	return spell_select, wild_wands
end

-- Wire the shared spell-selection stack for one generation-condition snapshot.
-- Returns is_unlocked(spell_id) -> boolean, or nil + reason.
--
-- wild_wands.configure is the only place in the project that builds the unlock
-- predicate from a profile, so shop cards obey exactly the same snapshot as
-- wild wands and Holy Mountain stock.
function M.configure( profile )
	if ( type( profile ) ~= "table" ) then
		return nil, "profile is not a normalized snapshot table"
	end
	local _, wild = deps()
	local ok, unlocked = pcall( wild.configure, profile )
	if ( not ok or type( unlocked ) ~= "function" ) then
		return nil, "spell-selection stack failed to configure: " .. tostring( unlocked )
	end
	configured_for = "profile"
	configured_unlocked = unlocked
	return unlocked
end

-- Wire the same shared stack around a caller-supplied unlock predicate.
--
-- This exists for tests and for a caller that already holds a snapshot in some
-- other form. It performs the same two init calls wild_wands.configure performs
-- (spell_select + wand_gen) with the same shared tables; it adds no selection
-- logic of its own, so there is still exactly one weighted walk in the project.
function M.configure_predicate( is_unlocked )
	if ( type( is_unlocked ) ~= "function" ) then
		return nil, "is_unlocked must be a function"
	end
	local select_mod, wild = deps()
	local prng_mod = dofile_once( "mods/interesting_seed_filter/files/isf/random/prng.lua" )
	local wand_gen = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/wand_gen.lua" )
	if ( type( prng_mod ) ~= "table" or type( wand_gen ) ~= "table" ) then
		return nil, "PRNG or wand generator did not return a table"
	end
	select_mod.init( {
		prng_new = prng_mod.new,
		pool = spells.pool,
		spell_types = wand_cfg.spell_types,
		type_by_id = wand_cfg.spell_type_by_id,
		is_unlocked = is_unlocked,
	} )
	-- wand_gen shares the same spell_select instance and unlock predicate, so a
	-- later wand-shaped caller observes exactly this snapshot.
	wand_gen.init( {
		prng_new = prng_mod.new,
		wand_config = wand_cfg,
		spell_select = select_mod,
		is_unlocked = is_unlocked,
	} )
	configured_for = "predicate"
	configured_unlocked = is_unlocked
	return is_unlocked
end

-- True when the shared selector has been wired in this session.
function M.is_configured()
	return configured_for ~= nil
end

-- Can this (x, y, level) be seeded exactly as the game does?
function M.check_frame( x, y, level )
	if ( type( x ) ~= "number" or type( y ) ~= "number"
		or x ~= x or y ~= y or x == math.huge or y == math.huge
		or x == -math.huge or y == -math.huge ) then
		return false, "slot coordinates must be finite numbers"
	end
	if ( x ~= math.floor( x ) or y ~= math.floor( y ) ) then
		-- The vanilla slot is a pixel-scene integer position. A fractional
		-- coordinate means the caller mixed a different frame in, and silently
		-- truncating it would predict a card the game never generated.
		return false, string.format(
			"slot coordinates must be integers in the pixel-scene frame (got %s, %s)",
			tostring( x ), tostring( y ) )
	end
	if ( type( level ) ~= "number" or level ~= math.floor( level )
		or level < 0 or level > 10 ) then
		return false, "card level must be an integer in [0, 10]"
	end
	return true
end

-- predict_slot( seed, level, x, y, is_unlocked ) -> result
--
-- result = {
--   spell_id = "..." | "",   -- "" means the weighted walk found no card
--   level, x, y, offset, frame,
--   resolved = true|false,
-- }
-- or nil, reason when the frame is not modellable.
function M.predict_slot( seed, level, x, y, is_unlocked )
	if ( type( seed ) ~= "number" or seed ~= math.floor( seed ) ) then
		return nil, "seed must be an integer"
	end
	local ok, why = M.check_frame( x, y, level )
	if ( not ok ) then
		return nil, why
	end
	local select_mod = deps()
	local predicate = is_unlocked or configured_unlocked
	if type(predicate) ~= "function" then return nil, "configure a profile or explicit unlock predicate first" end
	local card = select_mod.get_random_action(
		seed, x, y, level, M.SEED_OFFSET, predicate )
	local result = {
		spell_id = card or "",
		level = level,
		x = x,
		y = y,
		offset = M.SEED_OFFSET,
		frame = M.FRAME,
		resolved = type( card ) == "string" and card ~= "",
	}
	if ( not result.resolved ) then
		result.reason = "the weighted spell walk produced no action for this slot"
	end
	return result
end

return M
