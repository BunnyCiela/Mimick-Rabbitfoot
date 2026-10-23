-- files/isf/puzzles/recognize.lua
--
-- Turns puzzle ENTRANCE inputs (source-justified entrance records) into exactly
-- one puzzle INSTANCE per physical puzzle scene, and nothing else.
--
-- SUBSTANTIAL REUSE / ATTRIBUTION
--   The engine-default spawn-marker mapping (0x50a0f0 -> spawn_wands) and the
--   reward-room positions used by the data table come from noita-telescope:
--     js/spawn_function_config.js  (DEFAULT_SPAWNS)
--     js/misc_generation.js        (meditationCubePosition / snowyRoomPositions)
--     MIT License, Copyright (c) 2026 Lymm
--   Scene/functions cross-checked against noita-tools:
--     src/services/SeedInfo/infoHandler/InfoProviders/Map/impl/{Excavationsite,Snowcavetunnel}.ts
--     MIT License, Copyright (c) 2022 Seva Maltsev
--   The authoritative rule for every puzzle, however, is the installed vanilla
--   Lua extracted from data.wak (see tools/puzzles/extract_sources.py); upstream
--   parity is never treated as native game truth.
--
-- What "entrance" means here
-- --------------------------
-- An entrance is an explicit record with:
--   biome_key        generator key ("coalmine" | "excavationsite" | "snowcave")
--   spawn_function   the vanilla generator function that ran there
--   scene_name       the pixel-scene bitmap the generator placed (optional but
--                    required to disambiguate the shared electric-trap marker)
--   scene_x, scene_y the scene placement origin, if known
--   world_x, world_y the marker pixel's world position
--   generated        true only when the entrance object is verified to exist
--
-- Recognition never accepts a bare "there might be a puzzle here". It needs a
-- function that vanilla actually registers for a puzzle, and for the electric
-- trap it also needs the enclosing capsule scene, because
-- `spawn_electricity_trap` is ALSO a plain snowcave g_props prop (prob 0.05) and
-- is registered in four other biomes. A lone electric trap is a trap prop, not a
-- puzzle.
--
-- One instance per physical scene
-- -------------------------------
-- The Mines swinging-rope puzzle is announced by two marker functions
-- (`spawn_swing_puzzle_box` and `spawn_swing_puzzle_target`) that are two pixels
-- of ONE bitmap. The Snowy capsules carry `spawn_electricity_trap` INSIDE the
-- capsule scene, so the capsule and the "electric box" are one found object, not
-- two. Identity therefore keys on the physical scene placement
-- (biome, scene_origin) when known, and falls back to the puzzle kind plus a
-- rounded marker position cluster when the origin is not supplied. Scanning the
-- same placement twice, or through two trigger markers, yields ONE instance.
--
-- Lua 5.1 / LuaJIT 2.0 compatible. No I/O, no globals, no RNG.

local data = dofile_once( "mods/interesting_seed_filter/files/isf/data/puzzles.lua" )
if ( type( data ) ~= "table" ) then
	error( "recognize: files/isf/data/puzzles.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1

-- Distinct recognition outcomes. Anything that is not ACCEPTED must not score.
M.STATUS_ACCEPTED = "accepted"
M.STATUS_NOT_A_PUZZLE = "not_a_puzzle"
M.STATUS_OUT_OF_SCOPE = "out_of_scope_biome"
M.STATUS_GATE_FAILED = "gate_failed"
M.STATUS_UNRESOLVED = "unresolved"

-- Positional cluster radius (world units) used only when a record carries no
-- scene origin. Scenes are tens to hundreds of units wide; two markers of the
-- same bitmap are within a few hundred units. Markers of two distinct
-- placements are much farther apart because the terrain spawn grid is 512.
M.CLUSTER_RADIUS = 256

-- ---------------------------------------------------------------------------
-- Region helpers
-- ---------------------------------------------------------------------------

-- Normalise a biome field (display name, generator key, alias) to a generator
-- key. Returns nil for unknown values: an unknown region is never silently
-- treated as in-scope.
function M.region_key( value )
	if ( type( value ) ~= "string" or value == "" ) then
		return nil
	end
	if ( data.REGIONS[ value ] ~= nil ) then
		return value
	end
	return data.REGION_ALIASES[ value ]
end

function M.region( key )
	if ( type( key ) ~= "string" ) then
		return nil
	end
	return data.REGIONS[ key ]
end

-- True when the region is a PRD R3 puzzle-scoring region.
function M.region_in_scope( key )
	local region = M.region( key )
	if ( region == nil ) then
		return false
	end
	return region.in_scope == true
end

-- The entrance region a reward room inherits, or nil.
function M.entrance_region_of_room( room_key )
	if ( type( room_key ) ~= "string" ) then
		return nil
	end
	return data.ROOM_TO_ENTRANCE[ room_key ]
end

-- ---------------------------------------------------------------------------
-- Instance identity
-- ---------------------------------------------------------------------------

-- Stable identity of the physical scene placement.
--
-- With a scene origin:   "<biome>/scene/<scene>/<origin_x>,<origin_y>"
-- Without one:           "<biome>/cluster/<kind>/<round(x/256)>,<round(y/256)>"
--
-- The second form is deliberately coarse: it guarantees that two markers of the
-- same bitmap collapse to one instance even when the caller did not report the
-- placement, while two genuinely different placements (whose markers sit on
-- different terrain spawn cells) stay distinct. It cannot over-merge two
-- puzzles that are less than one cluster radius apart in the same biome, which
-- the terrain grid makes very unlikely, and it can under-merge only when a
-- caller reports markers from one bitmap more than a radius apart with no
-- origin — an input shape the contract says to ask for instead.
function M.instance_id( biome_key, kind, record )
	local scene = record.scene_name
	local sx = record.scene_x
	local sy = record.scene_y
	if ( type( scene ) == "string" and scene ~= ""
		and type( sx ) == "number" and type( sy ) == "number" ) then
		return string.format( "%s/scene/%s/%d,%d", biome_key, scene, sx, sy )
	end
	local x = record.world_x or 0
	local y = record.world_y or 0
	local cx = math.floor( x / M.CLUSTER_RADIUS + 0.5 )
	local cy = math.floor( y / M.CLUSTER_RADIUS + 0.5 )
	return string.format( "%s/cluster/%s/%d,%d", biome_key, kind.id, cx, cy )
end

-- ---------------------------------------------------------------------------
-- Kind resolution
-- ---------------------------------------------------------------------------

-- Resolve which puzzle kind a record announces, or nil + reason.
--
-- Rules, in order:
--   1. A scene name that belongs to a whitelisted kind wins. This is how the
--      Snowy capsules are told apart from the other two, and how a scene marker
--      that merely *sits inside* a capsule resolves to that capsule.
--   2. Otherwise a registered marker function resolves it, but only when that
--      function is unambiguously one kind.
--   3. `spawn_electricity_trap` with no capsule scene is NOT a puzzle.
function M.resolve_kind( record, biome_key )
	local scene = record.scene_name
	if ( type( scene ) == "string" and scene ~= "" ) then
		local by_scene = data.KIND_BY_SCENE[ scene ]
		if ( by_scene ~= nil and by_scene.biome_key == biome_key ) then
			return by_scene
		end
	end

	local func = record.spawn_function
	if ( type( func ) ~= "string" or func == "" ) then
		return nil, "record has neither a whitelisted scene_name nor a spawn_function"
	end

	if ( data.SCENE_ONLY_FUNCTIONS[ func ] == true ) then
		return nil, "spawn function '" .. func .. "' is a mechanism inside a scene, "
			.. "not a puzzle on its own (it is also a plain prop elsewhere)"
	end

	local candidates = data.KIND_BY_FUNCTION[ func ]
	if ( candidates == nil or #candidates == 0 ) then
		return nil, "spawn function '" .. func .. "' is not registered for any "
			.. "PRD R3 puzzle in this build"
	end
	if ( #candidates > 1 ) then
		return nil, "spawn function '" .. func .. "' is ambiguous between "
			.. #candidates .. " puzzle kinds; a scene_name is required"
	end
	local kind = candidates[ 1 ]
	if ( kind.biome_key ~= biome_key ) then
		return nil, "spawn function '" .. func .. "' belongs to biome "
			.. tostring( kind.biome_key ) .. ", not " .. tostring( biome_key )
	end
	return kind
end

-- ---------------------------------------------------------------------------
-- Meditation-cube gate
-- ---------------------------------------------------------------------------

-- Vanilla excavationsite.lua:
--     function spawn_meditation_cube( x, y )
--         SetRandomSeed( x, y )
--         local rnd = Random( 1, 100 )
--         if ( rnd > 96 and not ModIsEnabled("nightmare") ) then ... end
--     end
--
-- This is a deterministic per-position gate: given the marker's world position
-- and the world seed it either passes or fails, always the same way. It is NOT a
-- heuristic. Returns true/false, or nil + reason when the gate cannot be
-- evaluated (missing prng dependency or non-numeric position).
M.GATE_MEDITATION_MIN = 97 -- Random(1,100) > 96
M.GATE_MEDITATION_MAX = 100

local prng_module = nil

-- Inject the shared PRNG (production: files/isf/random/prng.lua). Tests inject
-- either the real module or a deterministic stand-in. Recognition never draws
-- from a shared instance: it creates one per call.
function M.set_prng( module )
	if ( module ~= nil and type( module.new ) ~= "function" ) then
		error( "recognize.set_prng: module must expose .new(world_seed)" )
	end
	prng_module = module
end

function M.gate_meditation( world_seed, x, y )
	if ( type( x ) ~= "number" or type( y ) ~= "number" ) then
		return nil, "meditation gate needs numeric world coordinates"
	end
	if ( prng_module == nil ) then
		return nil, "meditation gate needs the shared PRNG module "
			.. "(recognize.set_prng)"
	end
	-- The gate seeds from position only; the world seed belongs to the instance.
	local rng = prng_module.new( world_seed )
	rng:SetRandomSeed( x, y )
	local roll = rng:Random( 1, 100 )
	return roll > 96, nil, roll
end

-- ---------------------------------------------------------------------------
-- Recognition
-- ---------------------------------------------------------------------------

-- recognize( records, options ) -> {
--     instances = {...},           -- one per physical puzzle scene
--     rejected = {...},            -- every non-instance with its reason
--     by_kind = { [kind_id] = count },
--     duplicates = <number of records folded into an existing instance>,
--     input_count = <number>,
-- }
--
-- options:
--   seed          world seed (required only to evaluate the meditation gate)
--   gate_meditation  function(seed, x, y) -> passed, reason, roll
--                    (defaults to M.gate_meditation)
--   accept_unverified  when true, an entrance record with generated=false is
--                    still recognised as an instance but is marked
--                    `verified = false`. Default false: only verified entrances
--                    create an instance.
--
-- Every instance carries the fields the provider needs, and keeps the record
-- list that produced it so duplicate visits stay auditable.
function M.recognize( records, options )
	options = options or {}
	if ( type( records ) ~= "table" ) then
		error( "recognize.recognize expects an array of entrance records" )
	end

	local gate = options.gate_meditation or M.gate_meditation
	local accept_unverified = options.accept_unverified == true

	local instances = {}
	local by_id = {}
	local rejected = {}
	local duplicates = 0

	for i = 1, #records do
		local rec = records[ i ]
		local label = "record " .. i
		local function reject( status, reason )
			rejected[ #rejected + 1 ] = {
				index = i,
				status = status,
				reason = reason,
				source_id = type( rec ) == "table" and rec.source_id or nil,
				biome_key = type( rec ) == "table" and rec.biome_key or nil,
				spawn_function = type( rec ) == "table" and rec.spawn_function or nil,
				scene_name = type( rec ) == "table" and rec.scene_name or nil,
				world_x = type( rec ) == "table" and rec.world_x or nil,
				world_y = type( rec ) == "table" and rec.world_y or nil,
			}
		end

		if ( type( rec ) ~= "table" ) then
			reject( M.STATUS_UNRESOLVED, label .. " is not a table" )
		else
			local biome_key = M.region_key( rec.biome_key or rec.biome )
			if ( biome_key == nil ) then
				reject( M.STATUS_UNRESOLVED,
					label .. " has an unknown biome " .. tostring( rec.biome_key or rec.biome ) )
			elseif ( not M.region_in_scope( biome_key ) ) then
				local region = M.region( biome_key )
				reject( M.STATUS_OUT_OF_SCOPE,
					"biome " .. biome_key .. " is outside the PRD R3 puzzle regions ("
					.. tostring( region and region.out_of_scope_reason or "no puzzle base" ) .. ")" )
			else
				local kind, why = M.resolve_kind( rec, biome_key )
				if ( kind == nil ) then
					reject( M.STATUS_NOT_A_PUZZLE, why )
				elseif ( rec.generated ~= true and not accept_unverified ) then
					reject( M.STATUS_UNRESOLVED,
						label .. " is an unverified entrance marker (generated=" ..
						tostring( rec.generated ) .. "); an opportunity is not an object" )
				else
					local instance_id = M.instance_id( biome_key, kind, rec )
					local existing = by_id[ instance_id ]

					-- Meditation gate, evaluated once per instance.
					local gate_passed, gate_reason, gate_roll = true, nil, nil
					if ( kind.gate == "meditation" ) then
						gate_passed, gate_reason, gate_roll = gate(
							options.seed, rec.world_x, rec.world_y )
						if ( gate_passed == nil ) then
							gate_passed = nil
						end
					end

					if ( existing ~= nil ) then
						duplicates = duplicates + 1
						existing.records[ #existing.records + 1 ] = rec
						existing.trigger_count = existing.trigger_count + 1
						if ( type( rec.source_id ) == "string" and rec.source_id ~= "" ) then
							existing.source_ids[ #existing.source_ids + 1 ] = rec.source_id
						end
						if ( kind.gate == "meditation" and gate_roll ~= nil
							and existing.gate_roll == nil ) then
							existing.gate_roll = gate_roll
						end
					elseif ( gate_passed == nil ) then
						reject( M.STATUS_UNRESOLVED,
							"meditation cube probability gate could not be evaluated: "
							.. tostring( gate_reason ) )
					elseif ( gate_passed == false ) then
						reject( M.STATUS_GATE_FAILED,
							string.format(
								"meditation cube gate failed at (%s, %s): Random(1,100)=%s is not > 96",
								tostring( rec.world_x ), tostring( rec.world_y ),
								tostring( gate_roll ) ) )
					else
						local anchor = M.anchor_of( kind, rec )
						local instance = {
							id = instance_id,
							kind = kind,
							kind_id = kind.id,
							puzzle_type = kind.puzzle_type,
							mechanism = kind.mechanism,
							biome_key = biome_key,
							biome = data.REGIONS[ biome_key ].name,
							label = kind.label,
							bonus = kind.bonus,
							verified = rec.generated == true,
							-- The ENTRANCE position, which is what the report
							-- shows and what reward regions inherit.
							x = anchor.x,
							y = anchor.y,
							marker_x = rec.world_x,
							marker_y = rec.world_y,
							scene_name = rec.scene_name,
							scene_x = rec.scene_x,
							scene_y = rec.scene_y,
							anchor_marker = kind.anchor_marker,
							gate = kind.gate,
							gate_roll = gate_roll,
							trigger_count = 1,
							records = { rec },
							source_ids = { rec.source_id },
							rewards = {},
							reward_status = "not_evaluated",
							resource_scope = data.REGIONS[ biome_key ].resource_scope,
							provenance = kind.provenance,
						}
						instances[ #instances + 1 ] = instance
						by_id[ instance_id ] = instance
					end
				end
			end
		end
	end

	-- Deterministic order: biome, then x, then y, then id.
	table.sort( instances, function( a, b )
		if ( a.biome_key ~= b.biome_key ) then
			return a.biome_key < b.biome_key
		end
		if ( a.x ~= b.x ) then
			return a.x < b.x
		end
		if ( a.y ~= b.y ) then
			return a.y < b.y
		end
		return a.id < b.id
	end )

	local by_kind = {}
	for i = 1, #instances do
		local id = instances[ i ].kind_id
		by_kind[ id ] = ( by_kind[ id ] or 0 ) + 1
	end

	return {
		instances = instances,
		rejected = rejected,
		by_kind = by_kind,
		duplicates = duplicates,
		input_count = #records,
	}
end

-- Position reported for an instance and used as the inherited reward origin.
-- The PRD scores the puzzle by its entrance, so the entrance anchor wins over a
-- reward-room coordinate. `anchor_marker` marks the specific marker that carries
-- the reward offset (the rope target, not the rope box).
function M.anchor_of( kind, record )
	-- Discovery emits the scene placement before its trigger entities. Derive
	-- a source-proven trigger pixel from that same physical scene so folding is
	-- independent of input order (and of whether a second marker was emitted).
	local offset=kind.anchor_scene_offset
	if offset and type(record.scene_x)=="number" and type(record.scene_y)=="number" then
		return {x=record.scene_x+offset.x,y=record.scene_y+offset.y}
	end
	local ax = record.world_x
	local ay = record.world_y
	if ( type( ax ) ~= "number" or type( ay ) ~= "number" ) then
		ax = record.scene_x
		ay = record.scene_y
	end
	return { x = ax, y = ay }
end

return M
