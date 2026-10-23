-- files/isf/shops/score.lua
--
-- ISF-08 / PRD R4 scoring: turns one REAL wild spell shop scene into exact
-- per-rule report entries.
--
-- This module owns R4 ARITHMETIC ONLY. It deliberately does not:
--   * reimplement normal-spell values -> shared files/isf/core/spell_score.lua
--     with context "wild_direct" (G10 +10, G20 +20, G50 +50, full value);
--   * reimplement spell selection    -> files/isf/shops/predict.lua, which
--     reuses the worldgen weighted walk;
--   * reuse a chest's "+5 direct spell drop" bonus -> that is R2.2 and belongs
--     to the chests provider. A shop scene's base award is R4.1 and is awarded
--     by scene identity, not by "dropped a card".
--
-- PRD R4, verbatim requirements this file implements:
--   R4.1  each real wild spell shop SCENE in Mines / Coal Pits / Snowy Depths:
--         +5, ONCE, however many sale slots it has.
--   R4.2  each target card actually sold: full G10/G20/G50 wild-direct value.
--         A card that is not on the whitelist scores nothing extra.
--   R4.3  the same card at two different real slots accumulates; one slot seen
--         twice does not.
--   R4.4  Collapsed Mines / Holy Mountain shops are not R4 (handled upstream by
--         validation, and re-checked here so a bypass cannot score them).
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
if ( type( units ) ~= "table" ) then
	error( "shops/score: files/isf/core/units.lua did not return a table" )
end

local spell_score = dofile_once( "mods/interesting_seed_filter/files/isf/core/spell_score.lua" )
if ( type( spell_score ) ~= "table" ) then
	error( "shops/score: files/isf/core/spell_score.lua did not return a table" )
end

local shops_data = dofile_once( "mods/interesting_seed_filter/files/isf/data/shops.lua" )
if ( type( shops_data ) ~= "table" ) then
	error( "shops/score: files/isf/data/shops.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.CATEGORY = shops_data.CATEGORIES.AGGREGATE

M.RULES = shops_data.RULES

M.ERRORS = {
	bad_shop = "shop record is not a table",
	missing_scene_identity = "shop record has no stable scene identity",
	missing_region = "shop record is not in an R4 region",
	excluded_region = "shop record is in a region PRD R4 excludes",
	unknown_scene = "shop record names a scene that is not a wild spell shop",
	missing_coordinates = "shop record has no integer scene position",
	no_slots = "shop record has no resolved sale slot",
	slot_unresolved = "a shop slot's card could not be determined",
	duplicate_scene = "the same physical shop scene was already scored",
	duplicate_slot = "the same physical sale slot was already scored",
	out_of_scope_card = "the slot's card is not a PRD target (no target award)",
}

-- Scene identity of a shop record, preferring an explicit object_id (which the
-- discovery adapter already set from the same formula).
function M.scene_identity( shop )
	if ( type( shop ) == "table" ) then
		if ( type( shop.object_id ) == "string" and shop.object_id ~= "" ) then
			return "scene:" .. shop.object_id
		end
		local region, _ = shops_data.region( shop.region )
		if ( region ~= nil and type( shop.scene_name ) == "string" ) then
			return "scene:" .. string.format( "%s/scene/%s/%s,%s", region.biome_key,
				shop.scene_name, tostring( shop.scene_x ), tostring( shop.scene_y ) )
		end
		if ( type( shop.id ) == "string" and shop.id ~= "" ) then
			return "shop:" .. shop.id
		end
	end
	return "scene:<invalid>"
end

-- Slot identity within an already-identified scene.
function M.slot_identity( shop, slot )
	if ( type( slot ) == "table" ) then
		if ( type( slot.object_id ) == "string" and slot.object_id ~= "" ) then
			return "slot:" .. slot.object_id
		end
		if ( type( shop ) == "table" and type( shop.object_id ) == "string" ) then
			return string.format( "slot:%s/%s,%s", shop.object_id,
				tostring( slot.x ), tostring( slot.y ) )
		end
	end
	return "slot:<invalid>"
end

-- score_shop( shop, options ) -> { entries, score_units, errors, warnings,
--                                 counts, unresolved }
--
-- shop is a validated shop table (see shops/validate.lua and
-- shops/discovery.lua):
--   region, biome_key, scene_name, scene_x, scene_y, scene_width, scene_height,
--   level, object_id, slots = { { x, y, spell_id?, object_id? }, ... }
--
-- options:
--   claimed         a registry from shops/score.lua M.new_registry() (required,
--                   so re-entering the same scene cannot pay twice)
--   predict(card)   function(slot, shop) -> spell_id | nil, reason
--                   When absent a slot must carry an explicit spell_id.
--   is_unlocked     unlock predicate handed to `predict`
function M.score_shop( shop, options )
	options = options or {}
	local entries = {}
	local errors = {}
	local warnings = {}
	local unresolved = {}
	local counts = {
		scene_award = 0,
		slots = 0,
		scored_slots = 0,
		target_cards = 0,
		non_target_cards = 0,
		unresolved_slots = 0,
		duplicate_slots = 0,
	}
	-- Every DETERMINED sale slot, target or not, so a caller can show what the
	-- shop actually sold. Scoring entries stay target-only: an unlisted card
	-- earns nothing (PRD R4).
	local cards = {}

	local function add( entry )
		entries[ #entries + 1 ] = entry
	end

	-- ---- validation -------------------------------------------------------
	if ( type( shop ) ~= "table" ) then
		errors[ #errors + 1 ] = { code = "bad_shop", message = M.ERRORS.bad_shop }
		return { entries = entries, score_units = 0, errors = errors, warnings = warnings,
			counts = counts, unresolved = unresolved }
	end

	local region, region_name = shops_data.region( shop.region )
	if ( region == nil ) then
		local excluded = shops_data.EXCLUDED_REGIONS[ tostring( shop.region ) ]
		if ( excluded ~= nil ) then
			errors[ #errors + 1 ] = { code = "excluded_region", message = string.format(
				"%s: %s", tostring( shop.region ), excluded.reason ) }
		else
			errors[ #errors + 1 ] = { code = "missing_region", message = string.format(
				"%s: %s", M.ERRORS.missing_region, tostring( shop.region ) ) }
		end
		return { entries = entries, score_units = 0, errors = errors, warnings = warnings,
			counts = counts, unresolved = unresolved }
	end

	if ( type( shop.scene_name ) ~= "string"
		or not shops_data.is_wild_shop_scene( region, shop.scene_name ) ) then
		errors[ #errors + 1 ] = { code = "unknown_scene", message = string.format(
			"%s: %s (%s)", M.ERRORS.unknown_scene, tostring( shop.scene_name ),
			shops_data.region_scope_note( region_name ) ) }
		return { entries = entries, score_units = 0, errors = errors, warnings = warnings,
			counts = counts, unresolved = unresolved }
	end

	if ( type( shop.scene_x ) ~= "number" or type( shop.scene_y ) ~= "number"
		or shop.scene_x ~= math.floor( shop.scene_x )
		or shop.scene_y ~= math.floor( shop.scene_y ) ) then
		errors[ #errors + 1 ] = { code = "missing_coordinates",
			message = M.ERRORS.missing_coordinates }
		return { entries = entries, score_units = 0, errors = errors, warnings = warnings,
			counts = counts, unresolved = unresolved }
	end

	local scene_id = M.scene_identity( shop )
	local claimed = options.claimed
	if ( type( claimed ) ~= "table" ) then
		error( "shops/score.score_shop requires options.claimed (see M.new_registry)" )
	end
	local owns_scene, previous = claimed:claim_scene( scene_id, shop )
	if ( not owns_scene ) then
		-- A second view of one physical scene: R4.1 must not be paid twice, and
		-- the scene's slots are not re-walked either.
		warnings[ #warnings + 1 ] = { code = "duplicate_scene", message = string.format(
			"%s: scene %s was already scored; not counted again",
			M.ERRORS.duplicate_scene, scene_id ) }
		counts.duplicate_scene = true
		return { entries = entries, score_units = 0, errors = errors, warnings = warnings,
			counts = counts, unresolved = unresolved }
	end

	-- ---- R4.1: one base award per real scene ------------------------------
	local base = shops_data.RULES.R4_1
	add( {
		id = scene_id .. "/base",
		rule_id = base.rule_id,
		category = M.CATEGORY,
		biome = region_name,
		source_id = shop.object_id or scene_id,
		x = shop.scene_x,
		y = shop.scene_y,
		score_units = base.score_units,
		reason = string.format( "%s (%s scene '%s')", base.reason, region_name,
			shop.scene_name ),
		scene_name = shop.scene_name,
		scene_x = shop.scene_x,
		scene_y = shop.scene_y,
		shop_object_id = shop.object_id,
		scene_identity = scene_id,
	} )
	counts.scene_award = 1

	-- ---- R4.2/R4.3: per real slot ----------------------------------------
	local slots = shop.slots or {}
	counts.slots = #slots

	if ( #slots == 0 ) then
		-- The scene exists, so its +5 stands; the absence of slot records means
		-- its contents are unknown, not that it sold nothing.
		errors[ #errors + 1 ] = { code = "no_slots", message = string.format(
			"%s (scene %s at %d,%d)", M.ERRORS.no_slots, shop.scene_name,
			shop.scene_x, shop.scene_y ) }
		return { entries = entries, score_units = base.score_units, errors = errors,
			warnings = warnings, counts = counts, unresolved = unresolved }
	end

	for i = 1, #slots do
		local slot = slots[ i ]
		local slot_id = M.slot_identity( shop, slot )
		local owns_slot, _ = claimed:claim_slot( slot_id, slot )
		if ( not owns_slot ) then
			counts.duplicate_slots = counts.duplicate_slots + 1
			warnings[ #warnings + 1 ] = { code = "duplicate_slot", message = string.format(
				"%s: %s was already scored; not counted again",
				M.ERRORS.duplicate_slot, slot_id ) }
		else
			local card = slot.spell_id
			local source = slot.content_source or "supplied"
			if ( card == nil ) then
				if ( type( options.predict ) == "function" ) then
					local predicted, why = options.predict( slot, shop )
					if ( predicted == nil ) then
						counts.unresolved_slots = counts.unresolved_slots + 1
						unresolved[ #unresolved + 1 ] = {
							slot_id = slot_id,
							x = slot.x,
							y = slot.y,
							reason = why or M.ERRORS.slot_unresolved,
						}
						errors[ #errors + 1 ] = { code = "slot_unresolved", message = string.format(
							"%s: slot %s at (%s, %s): %s", M.ERRORS.slot_unresolved, slot_id,
							tostring( slot.x ), tostring( slot.y ), tostring( why ) ) }
					else
						card = predicted
						source = "predicted"
					end
				else
					counts.unresolved_slots = counts.unresolved_slots + 1
					unresolved[ #unresolved + 1 ] = {
						slot_id = slot_id, x = slot.x, y = slot.y,
						reason = "no card and no predictor",
					}
					errors[ #errors + 1 ] = { code = "slot_unresolved", message = string.format(
						"%s: slot %s has no card and no predictor was supplied",
						M.ERRORS.slot_unresolved, slot_id ) }
				end
			end

			if ( card ~= nil ) then
				counts.scored_slots = counts.scored_slots + 1
				local card_units = spell_score.score_spell( card,
					spell_score.CONTEXT_WILD_DIRECT )
				local info = spell_score.classify( card, spell_score.CONTEXT_WILD_DIRECT )
				cards[ #cards + 1 ] = {
					slot_identity = slot_id,
					x = slot.x,
					y = slot.y,
					spell_id = card,
					spell_group = info and info.group or nil,
					score_units = card_units,
					is_target = card_units > 0,
					content_source = source,
				}
				if ( card_units > 0 ) then
					counts.target_cards = counts.target_cards + 1
					add( {
						id = slot_id .. "/card",
						rule_id = shops_data.RULES.R4_2.rule_id,
						category = M.CATEGORY,
						biome = region_name,
						source_id = slot.object_id or slot_id,
						x = slot.x,
						y = slot.y,
						score_units = card_units,
						reason = string.format( "%s: %s (%s, %s)", shops_data.RULES.R4_2.reason,
							tostring( card ), info and info.group or "target",
							units.to_string( card_units ) ),
						spell_id = card,
						spell_group = info and info.group or nil,
						scene_name = shop.scene_name,
						scene_x = shop.scene_x,
						scene_y = shop.scene_y,
						slot_identity = slot_id,
						content_source = source,
						shop_object_id = shop.object_id,
					} )
				else
					counts.non_target_cards = counts.non_target_cards + 1
					warnings[ #warnings + 1 ] = { code = "out_of_scope_card", message = string.format(
						"%s: slot %s sold '%s' (%s)", M.ERRORS.out_of_scope_card,
						slot_id, tostring( card ), source ) }
				end
			end
		end
	end

	local total = 0
	for i = 1, #entries do
		total = total + entries[ i ].score_units
	end

	return {
		entries = entries,
		score_units = total,
		errors = errors,
		warnings = warnings,
		counts = counts,
		unresolved = unresolved,
		cards = cards,
	}
end

-- A registry that keeps "already scored" state for one evaluation.
--
-- Separate from the report's own duplicate-id check because a shop scene can be
-- reached through two different record sets (a scan result and an explicit
-- supplied record) before any entry is added: the registry answers the question
-- "is this the same PHYSICAL object", which the report cannot know.
local Registry = {}
Registry.__index = Registry

function Registry:claim_scene( identity, shop )
	local previous = self.scenes[ identity ]
	if ( previous ~= nil ) then
		return false, previous
	end
	self.scenes[ identity ] = shop
	return true
end

function Registry:claim_slot( identity, slot )
	local previous = self.slots[ identity ]
	if ( previous ~= nil ) then
		return false, previous
	end
	self.slots[ identity ] = slot
	return true
end

function M.new_registry()
	return setmetatable( { scenes = {}, slots = {} }, Registry )
end

return M
