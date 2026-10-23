-- files/isf/chests/discovery.lua
--
-- ISF-05 read-only discovery adapter: turns REAL worldgen scan records into
-- chest objects, and nothing else.
--
-- ---------------------------------------------------------------------------
-- Why this file is so defensive
-- ---------------------------------------------------------------------------
--
-- A "scene_marker" or a spawn pixel is NOT a chest. In Mines the same biome can
-- emit
--     spawn_chest      -> always a real chest (type comes from a probability)
--     spawn_heart      -> a heart, a chest, a chest mimic, a leggy chest, or
--                         nothing at all, depending on three RNG draws
--     spawn_bbqbox     -> enemies + a *nested* spawn_heart two tiles over
--     spawn_items      -> a pixel scene (which may itself contain markers)
-- so presence alone proves nothing. Every candidate source is therefore put
-- through the vanilla probability/type function, and only a confirmed chest is
-- emitted. An unconfirmed source is not a chest and is never counted.
--
-- Coverage honesty:
--   * this adapter only understands spawn functions it has actually verified
--     against the installed biome scripts;
--   * it can only be as complete as the scan result it was given, and the
--     worldgen workflow currently publishes Mines only;
--   * a scan result WITHOUT any chest-bearing spawn function is reported as
--     `partial` with an explicit reason, never as "this seed has no chests".
--
-- The adapter never writes to the scan result, never re-runs worldgen, and
-- never moves or opens an entity.
--
-- Sources: data/scripts/biomes/coalmine.lua (spawn_chest, spawn_bbqbox),
--          data/scripts/biome_scripts.lua (spawn_heart),
--          files/isf/worldgen/scan.lua (record shape, read-only).
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local loot = dofile_once( "mods/interesting_seed_filter/files/isf/chests/loot.lua" )
if ( type( loot ) ~= "table" ) then
	error( "chests/discovery: files/isf/chests/loot.lua did not return a table" )
end

local chest_data = dofile_once( "mods/interesting_seed_filter/files/isf/data/chests.lua" )
if ( type( chest_data ) ~= "table" ) then
	error( "chests/discovery: files/isf/data/chests.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

-- Spawn functions whose chest-bearing behaviour is verified against the
-- installed biome scripts.
--
-- `expected` documents what each one can yield, so a reader can see why the
-- adapter does not simply count markers.
M.SUPPORTED_SPAWN_FUNCTIONS = {
	spawn_chest = {
		supported = true,
		always_chest = true,
		note = "coalmine.lua spawn_chest: type from Random(1,2000), great chest when roll >= 1999",
	},
	spawn_heart = {
		supported = true,
		always_chest = false,
		note = "biome_scripts.lua spawn_heart: heart / chest / chest_mimic / leggy / nothing",
	},
	spawn_bbqbox = {
		supported = true,
		always_chest = false,
		note = "coalmine.lua spawn_bbqbox: nested spawn_heart at (x+10, y+10) when roll <= 99",
	},
}

-- Spawn KINDS that are conclusively NOT a chest, so a record of that kind is a
-- documented zero rather than an unknown. This is the difference between "this
-- build knows a trap wand is not a chest" and "this build has never heard of
-- this marker": only the latter may keep coverage partial.
--
-- `heart` and `bbqbox` are deliberately ABSENT because vanilla `spawn_heart` can
-- produce a chest -- they must be re-derived, never dismissed. `gate_blocked` is
-- also absent: it is a proven ABSENCE of an object, which is a different answer
-- from "this marker yields no chest", and it is handled explicitly below.
--
-- The kinds below are the ones `files/isf/worldgen/scan.lua` emits today
-- (DISCOVERY_CONTRACT.md §5).
M.KNOWN_NON_CHEST_SPAWN_KINDS = {
	trap_wand = "a terrain wand, not a chest",
	wild_wand = "a free-standing wand, not a chest",
	scene_wand = "a scene wand, not a chest",
	altar_wand = "a wand on an altar, not a chest",
	wand_altar = "a wand altar, not a chest",
	pixel_scene = "a pixel scene; its own markers arrive as separate records",
	utility_box = "a utility box, not a chest",
	shop_item = "a shop slot, not a chest",
	potion = "a loose potion marker, not a chest",
	potion_altar = "a potion altar, not a chest",
	scene_marker = "a recognised scene marker with no chest resolver",
}

-- Spawn functions this adapter knows about and that are conclusively not a
-- chest source.
M.KNOWN_NON_CHEST_SPAWN_FUNCTIONS = {
	spawn_items = "pixel scene / wand altar path; its markers are separate records",
	spawn_wand_altar = "wand altar path, not a chest",
	load_pixel_scene = "pixel scene; its markers are separate records",
	load_pixel_scene2 = "pixel scene; its markers are separate records",
	load_pixel_scene4 = "pixel scene; its markers are separate records",
	load_pixel_scene4_alt = "pixel scene; its markers are separate records",
	load_puzzleroom = "puzzle room scene, not a chest",
	load_gunpowderpool_01 = "liquid pool scene, not a chest",
	load_gunpowderpool_02 = "liquid pool scene, not a chest",
	load_gunpowderpool_03 = "liquid pool scene, not a chest",
	load_gunpowderpool_04 = "liquid pool scene, not a chest",
	load_oiltank = "oil tank scene, not a chest",
	load_oiltank_alt = "oil tank scene, not a chest",
	load_altar = "wand altar scene, not a chest",
	load_structures = "structure scene, not a chest",
	spawn_wands = "wand drop, not a chest",
	spawn_wand = "wand drop, not a chest",
	spawn_trapwand = "wand drop, not a chest",
	spawn_shopitem = "shop item, not a chest",
	spawn_potions = "loose potion spawn, not a chest",
	spawn_potion = "loose potion spawn, not a chest",
	spawn_potion_altar = "potion altar pixel scene, not a chest",
	spawn_wand_trap = "hazard trap, not a chest",
	spawn_wand_trap_ignite = "hazard trap, not a chest",
	spawn_wand_trap_electricity = "hazard trap, not a chest",
	spawn_wand_trap_electricity_source = "hazard trap, not a chest",
}

-- Reason strings used in coverage claims.
M.REASONS = {
	no_records = "the scan result contains no records, so no chest source was examined",
	unsupported_only = "the scan result contains no verified chest-bearing spawn function",
	partial_functions = "the scan result contains spawn functions this adapter cannot model",
	no_biome = "the scan result does not name its biome",
}

-- KNOWN SOURCE OMISSIONS in the worldgen scan, per biome.
--
-- These are chest SOURCES that the vanilla biome script registers but that the
-- scan does not emit a record for. Because such a source can hide a chest, no
-- record set from that region can be called exhaustive while it is missing --
-- not even with a caller's `scan_complete = true`.
--
-- This table is the chest workflow's own evidence about a file it does not own.
-- Every entry must be re-checked against the CURRENT scan whenever worldgen
-- lands a change: a stale entry that claims an emission is missing is a lie that
-- permanently caps coverage, which is worse than a conservative partial.
--
-- HISTORY: `coalmine.spawn_bbqbox` was listed here because the scan emitted no
-- record for it. Worldgen fixed that (DISCOVERY_CONTRACT.md §5.4, "Resolved"),
-- verified independently against the actual pipeline with
-- tools/chests/probe_bbqbox_cases.lua, so the entry was REMOVED. Do not
-- re-add it without re-verifying that the emission is gone.
M.KNOWN_SOURCE_OMISSIONS = {
	-- Intentionally empty. Sources verified as EMITTED must not be listed.
}

-- Chest sources each biome's vanilla script registers, as EVIDENCE for what a
-- complete enumeration must cover. This is not an omission table: it records the
-- expected source set so a region whose records cannot account for one of these
-- is reported as unverifiable rather than silently complete.
--
-- Transcribed from the installed biome scripts (read out of data.wak):
--   coalmine.lua          RegisterSpawnFunction -> spawn_chest, spawn_bbqbox
--   coalmine_alt.lua      (no spawn_chest / spawn_bbqbox registration)
--   excavationsite.lua    (no spawn_chest / spawn_bbqbox registration)
--   fungicave.lua         (no spawn_chest / spawn_bbqbox registration)
--   snowcave.lua          (no spawn_chest / spawn_bbqbox registration)
-- and biome_scripts.lua registers spawn_heart for every biome (no biome
-- overrides it -- verified by grepping all five biome scripts).
M.EXPECTED_CHEST_SOURCES = {
	coalmine = { "spawn_chest", "spawn_bbqbox", "spawn_heart" },
	coalmine_alt = { "spawn_heart" },
	excavationsite = { "spawn_heart" },
	fungicave = { "spawn_heart" },
	snowcave = { "spawn_heart" },
}

-- Omissions for a region key or display name, or an empty array.
function M.known_omissions( biome )
	local list = M.KNOWN_SOURCE_OMISSIONS[ biome ]
	if ( list ~= nil ) then
		return list
	end
	local _, info = chest_data.region( biome )
	if ( info ~= nil and info.key ~= nil
		and M.KNOWN_SOURCE_OMISSIONS[ info.key ] ~= nil ) then
		return M.KNOWN_SOURCE_OMISSIONS[ info.key ]
	end
	return {}
end

local function is_number( v )
	return type( v ) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Classify one scan record.
--
-- Returns one of:
--   { status = "chest", chest = <raw chest>, reason = ... }
--   { status = "not_chest", reason = ... }   -- conclusively not a chest
--   { status = "unsupported", reason = ... } -- this build cannot model it
--   { status = "invalid", reason = ... }
--
-- The record shapes it accepts, in the order the REAL worldgen scan produces
-- them (files/isf/worldgen/scan.lua, DISCOVERY_CONTRACT.md §4/§5):
--
--   chest   / spawn_chest   generated = false  -> POTENTIAL marker (resolved here)
--   heart   / spawn_heart   generated = true|false + `outcome` dispatch
--   bbqbox  / spawn_bbqbox  generated = true|false + `nested_heart`
--   gate_blocked            proven ABSENCE (no object exists)
--   <other> / <any>         documented non-chest kind
--
-- INDEPENDENCE: this adapter does NOT trust the scan's own `outcome` /
-- `generated` / `entity_file` for the chest question. It re-derives the vanilla
-- dispatch from `spawn_function` + coordinates + calendar, exactly as before the
-- scan learned to resolve them. The scan's fields are used only to CONFIRM and to
-- supply provenance; a disagreement is reported, never silently adopted.
--
-- CALENDAR: `spawn_heart`'s threshold is 0.35 on 14 February, so the band
-- (0.35, 0.7] is a heart on that date and a chest otherwise. With no calendar
-- supplied the adapter returns status "unresolved" for that band -- never a guess.
function M.classify_record( seed, record, region, opts )
	opts = opts or {}
	if ( type( record ) ~= "table" ) then
		return { status = "invalid", reason = "record is not a table" }
	end

	local func = record.spawn_function
	local kind = record.spawn_kind
	local x = record.world_x or record.x
	local y = record.world_y or record.y

	-- A proven ABSENCE is a definitive negative answer, not an unknown: the gate
	-- was evaluated from source facts and failed, so no object exists there.
	if ( kind == "gate_blocked" or record.absence_proven == true
		and record.generated == false and kind ~= "chest" and kind ~= "heart"
		and kind ~= "bbqbox" ) then
		return { status = "not_chest",
			reason = string.format(
				"record is a proven absence (gate %s, roll %s vs threshold %s); "
					.. "no object exists",
				tostring( record.gate ), tostring( record.gate_roll ),
				tostring( record.gate_threshold ) ) }
	end

	-- A documented non-chest kind is a conclusive zero, even without a
	-- recognised spawn_function. This must be checked before the function table
	-- so that e.g. a trap_wand record whose function name changed is still
	-- correctly dismissed instead of poisoning coverage.
	if ( kind ~= nil and kind ~= "chest" and kind ~= "heart" and kind ~= "bbqbox" ) then
		local why = M.KNOWN_NON_CHEST_SPAWN_KINDS[ kind ]
		if ( why ~= nil ) then
			return { status = "not_chest",
				reason = string.format( "record kind '%s' is not a chest: %s",
					tostring( kind ), why ) }
		end
	end

	if ( func == nil ) then
		if ( kind == "chest" ) then
			func = "spawn_chest"
		elseif ( kind == "heart" ) then
			func = "spawn_heart"
		elseif ( kind == "bbqbox" ) then
			func = "spawn_bbqbox"
		else
			return { status = "unsupported",
				reason = "record names neither a spawn_function nor a chest/heart/"
					.. "bbqbox spawn_kind" }
		end
	end

	if ( not is_number( x ) or not is_number( y ) ) then
		return { status = "invalid",
			reason = "record has no numeric world_x/world_y" }
	end

	local support = M.SUPPORTED_SPAWN_FUNCTIONS[ func ]
	if ( support == nil ) then
		local known_func = M.KNOWN_NON_CHEST_SPAWN_FUNCTIONS[ func ]
		if ( known_func ~= nil ) then
			return { status = "not_chest",
				reason = string.format( "spawn function '%s' is not a chest source: %s",
					tostring( func ), known_func ) }
		end
		-- A genuinely unknown function: this build has never modelled it, so it
		-- must keep coverage partial rather than be assumed harmless.
		return {
			status = "unsupported",
			reason = "spawn function '" .. tostring( func )
				.. "' is not verified as a chest source",
		}
	end

	local source_id = record.source_id
		or string.format( "%s/%s/%s", tostring( region ), tostring( func ),
			tostring( x ) .. "," .. tostring( y ) )
	-- Prefer the scan's stable object identity so an entity scan and a marker
	-- resolve to ONE object. Fall back to source_id when it is absent.
	local object_id = record.object_id or source_id

	if ( func == "spawn_chest" ) then
		local roll = loot.roll_spawn_chest_type( seed, x, y )
		return {
			status = "chest",
			reason = string.format(
				"spawn_chest marker resolved to a %s chest (type roll %s/%s)",
				roll.kind, tostring( roll.roll ), tostring( roll.rate ) ),
			chest = {
				id = source_id,
				object_id = object_id,
				kind = roll.kind,
				biome = region,
				provenance = "biome_spawn",
				x = x,
				y = y,
			},
		}
	end

	if ( func == "spawn_bbqbox" ) then
		-- ONE bbqbox yields at most ONE chest, at the nested heart offset. The
		-- nested heart is NOT a separate record (`separate_record = false`), so
		-- no second chest may be produced for the same source.
		local nested = record.nested_heart
		local roll = loot.roll_bbqbox_source( seed, x, y, opts )
		if ( roll.kind == "chest" ) then
			-- Identity: prefer the scan's nested object_id (the physical heart
			-- container), else derive a stable one from the PARENT marker so a
			-- re-derivation cannot mint a second identity for the same source.
			local nested_object_id = ( type( nested ) == "table" and nested.object_id )
				or ( object_id .. "/heart" )
			local chest = {
				id = nested_object_id,
				object_id = nested_object_id,
				kind = roll.chest_kind,
				biome = region,
				provenance = "heart_spawn",
				x = roll.chest_x,
				y = roll.chest_y,
				parent_id = source_id,
			}
			local reason = "spawn_bbqbox nested spawn_heart confirmed a chest"
			if ( type( nested ) == "table" and nested.separate_record == true ) then
				-- Defensive: a future contract change that makes the nested heart
				-- a top-level record would recreate the double-count bug.
				reason = reason .. " (WARNING: nested_heart.separate_record is true; "
					.. "the scan is expected to nest it)"
			end
			return { status = "chest", reason = reason, chest = chest }
		end
		if ( roll.kind == "unresolved" ) then
			-- The nested heart is calendar-ambiguous. Adopt the scan's resolved
			-- nested outcome when it published one, keeping the NESTED identity so
			-- parent and child can never become two chests.
			local adopted = ( type( nested ) == "table" )
				and M.adopt_scan_outcome( nested, "bbqbox_nested_heart" ) or nil
			if ( adopted ~= nil and adopted.status == "chest" ) then
				adopted.chest.parent_id = source_id
				adopted.chest.reason = ( adopted.chest.reason or "" )
					.. " [nested in bbqbox " .. tostring( source_id ) .. "]"
				adopted.reason = adopted.reason .. " (nested in spawn_bbqbox "
					.. tostring( source_id ) .. ")"
				return adopted
			elseif ( adopted ~= nil ) then
				adopted.reason = adopted.reason .. " (nested in spawn_bbqbox "
					.. tostring( source_id ) .. ")"
				return adopted
			end
			return { status = "unresolved",
				reason = tostring( roll.reason
					or "spawn_bbqbox nested spawn_heart is calendar-dependent" ) }
		end
		return {
			status = "not_chest",
			reason = "spawn_bbqbox produced '" .. tostring( roll.kind )
				.. "', not a chest",
		}
	end

	-- spawn_heart: a dispatch, re-derived independently.
	local roll = loot.roll_heart_source( seed, x, y, opts )
	if ( roll.kind == "unresolved" ) then
		-- We could not settle it (no calendar). If the scan published a resolved
		-- dispatch outcome AND says what conditions it used, adopt it as a
		-- SECONDARY source -- labelled as borrowed, never as our own re-derivation,
		-- and never silently. This is what lets a caller that has no calendar
		-- still consume a scan that did.
		local adopted = M.adopt_scan_outcome( record, kind )
		if ( adopted ~= nil ) then
			adopted.reason = string.format( "%s [calendar-free adapter adopted the "
				.. "scan's resolved dispatch: %s]", adopted.reason,
				tostring( roll.reason or "" ) )
			return adopted
		end
		return { status = "unresolved",
			reason = tostring( roll.reason
				or "spawn_heart is calendar-dependent and no calendar was supplied" ) }
	end
	if ( roll.kind == "chest" ) then
		local chest = {
			id = source_id,
			object_id = object_id,
			kind = roll.chest_kind,
			biome = region,
			provenance = "heart_spawn",
			x = x,
			y = y,
		}
		-- Cross-check the scan's own resolution when it published one. A
		-- disagreement is surfaced so neither side silently overrides the other.
		local note = ""
		if ( record.outcome ~= nil and record.outcome ~= "chest" ) then
			note = string.format( " [scan said outcome=%s; adapter re-derived a chest]",
				tostring( record.outcome ) )
		end
		return {
			status = "chest",
			reason = string.format(
				"spawn_heart confirmed a chest (r=%.6f, threshold %.2f, type roll %s/1000)%s",
				roll.r, roll.heart_spawn_percent,
				tostring( roll.chest_roll ), note ),
			chest = chest,
		}
	end
	return {
		status = "not_chest",
		reason = string.format(
			"spawn_heart produced '%s' (r=%.6f, threshold %.2f), which is not a chest",
			tostring( roll.kind ), roll.r or -1, roll.heart_spawn_percent or -1 ),
	}
end

-- Adopt a scan-published dispatch outcome, but ONLY when the scan states it did
-- so with frozen conditions (`outcome_status` / non-`unresolved_reason`) and the
-- outcome is one this adapter recognises. Returns a verdict table or nil.
--
-- This is deliberately narrow: it is a fallback for the calendar-ambiguous band,
-- not a replacement for re-derivation. A scan that says `unresolved` is never
-- upgraded, and a scan that publishes no outcome is never guessed from.
function M.adopt_scan_outcome( record, kind )
	local outcome = record.outcome
	if ( type( outcome ) ~= "string" ) then return nil end
	-- Never adopt an explicitly unresolved scan answer.
	if ( outcome == "unresolved" or record.outcome_status == "unresolved"
		or record.calendar_dependent == true ) then
		return nil
	end
	local source_id = record.source_id
		or string.format( "%s/%s", tostring( record.biome ), tostring( kind ) )
	local object_id = record.object_id or source_id

	if ( outcome == "chest" ) then
		local chest_kind = record.chest_kind
		if ( chest_kind ~= "normal" and chest_kind ~= "super" ) then
			return nil -- a chest without a resolvable type is not usable
		end
		local x = record.world_x or record.x
		local y = record.world_y or record.y
		if ( type( x ) ~= "number" or type( y ) ~= "number" ) then return nil end
		return {
			status = "chest",
			reason = string.format(
				"scan-resolved spawn_heart chest (outcome=chest, chest_kind=%s); the "
					.. "adapter could not re-derive it without a calendar",
				tostring( chest_kind ) ),
			chest = {
				id = source_id,
				object_id = object_id,
				kind = chest_kind,
				biome = record.biome,
				provenance = "heart_spawn",
				x = x,
				y = y,
			},
			adopted = true,
		}
	end
	if ( outcome == "nothing" or outcome == "heart" or outcome == "chest_mimic"
		or outcome == "chest_leggy" ) then
		return {
			status = "not_chest",
			reason = string.format(
				"scan-resolved spawn_heart outcome=%s, which is not a chest",
				tostring( outcome ) ),
			adopted = true,
		}
	end
	return nil
end

-- discover( seed, scan_result, region, opts ) -> {
--   chests, rejected, unsupported, invalid, examined, reasons, complete
-- }
--
-- `scan_result` is a worldgen scan result table (see
-- files/isf/worldgen/scan.lua scan_layer). It is read, never modified.
function M.discover( seed, scan_result, region, opts )
	opts = opts or {}
	local out = {
		chests = {},
		rejected = {},
		unsupported = {},
		invalid = {},
		examined = 0,
		reasons = {},
		complete = false,
		known_source_omissions = M.known_omissions( region ),
	}

	if ( type( scan_result ) ~= "table" ) then
		out.reasons[ #out.reasons + 1 ] = "scan result is not a table"
		return out
	end
	if ( region == nil or region == "" ) then
		out.reasons[ #out.reasons + 1 ] = M.REASONS.no_biome
		return out
	end

	local records = scan_result.records
	if ( type( records ) ~= "table" or #records == 0 ) then
		out.reasons[ #out.reasons + 1 ] = M.REASONS.no_records
		return out
	end

	local any_classified = false
	local any_unsupported = false
	local any_unresolved = 0
	for i = 1, #records do
		local record = records[ i ]
		out.examined = out.examined + 1
		local verdict = M.classify_record( seed, record, region, opts )
		if ( verdict.status == "chest" ) then
			any_classified = true
			-- Deduplicate by object identity: one marker can appear as both a
			-- scene marker and a nested record.
			local duplicate = false
			for j = 1, #out.chests do
				if ( out.chests[ j ].object_id == verdict.chest.object_id ) then
					duplicate = true
					break
				end
			end
			if ( not duplicate ) then
				verdict.chest.reason = verdict.reason
				out.chests[ #out.chests + 1 ] = verdict.chest
			end
		elseif ( verdict.status == "not_chest" ) then
			-- A `not_chest` verdict is only ever produced from a CONCLUSIVE
			-- answer: either a supported chest source that this build resolved to
			-- a non-chest entity (a mimic, a leggy chest, "nothing"), or a
			-- documented non-chest kind/function. In both cases the chest question
			-- for that record is settled, so it counts as classified.
			any_classified = true
			out.rejected[ #out.rejected + 1 ] = {
				source_id = record.source_id,
				object_id = record.object_id,
				spawn_kind = record.spawn_kind,
				spawn_function = record.spawn_function,
				reason = verdict.reason,
			}
		elseif ( verdict.status == "unresolved" ) then
			-- Genuinely undetermined: a calendar-dependent dispatch without a
			-- calendar. NOT a classification, and NOT an error in the caller's
			-- data, so it keeps coverage partial without inventing a verdict.
			any_unresolved = any_unresolved + 1
			out.unresolved = out.unresolved or {}
			out.unresolved[ #out.unresolved + 1 ] = {
				source_id = record.source_id,
				object_id = record.object_id,
				spawn_kind = record.spawn_kind,
				spawn_function = record.spawn_function,
				reason = verdict.reason,
			}
		elseif ( verdict.status == "unsupported" ) then
			any_unsupported = true
			-- Only count a source once, so the reason list stays readable.
			local key = record.spawn_function or record.spawn_kind or "<unnamed>"
			local seen = false
			for j = 1, #out.unsupported do
				if ( out.unsupported[ j ].key == key ) then
					seen = true
					break
				end
			end
			if ( not seen ) then
				out.unsupported[ #out.unsupported + 1 ] = {
					key = key,
					spawn_kind = record.spawn_kind,
					spawn_function = record.spawn_function,
					reason = verdict.reason,
				}
			end
		else
			out.invalid[ #out.invalid + 1 ] = {
				source_id = record.source_id,
				reason = verdict.reason,
			}
		end
	end

	out.unresolved_count = any_unresolved

	-- `any_classified` means: at least one record was CONCLUSIVELY answered (it
	-- is a chest, or it provably is not). A documented non-chest kind counts,
	-- because the chest question for that record is settled. An unknown spawn
	-- function does not, because nothing about it was answered.
	if ( not any_classified ) then
		out.reasons[ #out.reasons + 1 ] = M.REASONS.unsupported_only
	end
	if ( any_unsupported ) then
		out.reasons[ #out.reasons + 1 ] = M.REASONS.partial_functions
	end
	if ( any_unresolved > 0 ) then
		out.reasons[ #out.reasons + 1 ] = string.format(
			"%d record(s) are calendar-dependent and no calendar was supplied "
				.. "(spawn_heart's 0.35/0.7 band)", any_unresolved )
	end
	if ( #out.invalid > 0 ) then
		out.reasons[ #out.reasons + 1 ] = string.format(
			"%d record(s) were malformed", #out.invalid )
	end

	-- Complete only when at least one record was conclusively classified and no
	-- record was left unknown or undetermined. An empty chest list from such a
	-- scan is a real "no chest markers among these records" answer -- but the
	-- CALLER still has to decide whether the record set itself is exhaustive (see
	-- the provider's scan_complete option and `source_capability` below).
	out.complete = any_classified and not any_unsupported
		and any_unresolved == 0
		and #out.invalid == 0 and #records > 0

	-- Did the records actually account for every chest source the vanilla biome
	-- script registers? This is stronger than "we classified what we were given":
	-- it is the evidence a caller needs before claiming enumeration completeness.
	out.source_capability = M.assess_sources( records, region )

	return out
end

-- assess_sources( records, region ) -> {
--   expected, observed, unmodeled_expected, unknown_observed, sufficient, reason
-- }
--
-- This answers a CAPABILITY question, not a per-seed count question:
--   "can this build resolve every chest source the vanilla biome script
--    registers for this region?"
--
-- A marker-driven source may legitimately occur ZERO times in a given seed, so
-- its absence from one seed's records is NOT a gap and must never be reported as
-- one. What matters is whether the build knows how to resolve it at all.
--
-- `observed` is reported for diagnostics only.
function M.assess_sources( records, region )
	local out = {
		expected = {},
		observed = {},
		unmodeled_expected = {},
		unknown_observed = {},
		sufficient = false,
	}
	local biome_key = region
	local _, info = chest_data.region( region )
	if ( info ~= nil and info.key ~= nil ) then
		biome_key = info.key
	end
	local expected = M.EXPECTED_CHEST_SOURCES[ biome_key ]
	if ( expected == nil ) then
		out.reason = "no expected chest-source set recorded for region " .. tostring( region )
		return out
	end

	-- Capability hole: the vanilla script registers a source this build cannot
	-- resolve. That is a real, permanent gap for the region.
	for i = 1, #expected do
		local source = expected[ i ]
		out.expected[ i ] = source
		if ( M.SUPPORTED_SPAWN_FUNCTIONS[ source ] == nil ) then
			out.unmodeled_expected[ #out.unmodeled_expected + 1 ] = source
		end
	end

	local observed_set = {}
	for i = 1, #( records or {} ) do
		local func = records[ i ].spawn_function
		if ( func ~= nil ) then
			observed_set[ func ] = ( observed_set[ func ] or 0 ) + 1
		end
	end
	for func, count in pairs( observed_set ) do
		out.observed[ #out.observed + 1 ] = { source = func, count = count }
		-- A source the build has no resolver for, seen in the data, is also a
		-- capability hole worth naming.
		if ( M.SUPPORTED_SPAWN_FUNCTIONS[ func ] ~= nil
			and M.KNOWN_NON_CHEST_SPAWN_FUNCTIONS[ func ] == nil ) then
			local listed = false
			for k = 1, #expected do
				if ( expected[ k ] == func ) then listed = true end
			end
			if ( not listed ) then
				out.unknown_observed[ #out.unknown_observed + 1 ] = func
			end
		end
	end
	table.sort( out.observed, function( a, b ) return a.source < b.source end )

	out.sufficient = ( #out.unmodeled_expected == 0 ) and ( #out.unknown_observed == 0 )
	if ( not out.sufficient ) then
		out.reason = "this build cannot resolve every chest source the vanilla "
			.. "script registers for " .. tostring( biome_key )
	end
	return out
end

-- is_pipeline_result( scan_result ) -> boolean, reason
--
-- Distinguishes a REAL region discovery result from a hand-built `{ records = … }`
-- table. Exhaustiveness is a property of an actual enumeration, so a manually
-- constructed record list must never be able to claim it, no matter what the
-- caller asserts.
--
-- The evidence required is what only a real pipeline result carries: a biome key,
-- the terrain spawn-pixel list the records were derived from, and a record count
-- consistent with the records themselves.
function M.is_pipeline_result(scan_result)
	-- Structural metadata is useful for diagnostics, but is not an audit of
	-- all terrain/scene/nested chest sources. Keep partial until that producer
	-- audit and native comparison exist; no caller flag can promote it.
	return false, "producer chest-source exhaustiveness is unverified; spawn_pixels and record_count do not prove no omitted sources"
end

return M
