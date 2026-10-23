-- tools/foundation/diagnostics/isf_probe.lua
--
-- ISF native-validation probe. NOT SHIPPED, NOT AUTO-ACTIVE, NOT PRODUCTION CODE.
--
-- What this is
-- ------------
-- A development-only diagnostic that records what the *running game* actually
-- does at the two seed boundaries of the Holy Mountain wand pipeline, plus the
-- raw date/time API tuples and the initial shop/card/perk entities. It exists so
-- that a future, explicitly authorized, disposable test run can collect evidence
-- that no amount of reasoning over shipped Lua can provide.
--
-- What this is NOT
-- ----------------
--   * It is not loaded by the mod's production entry points. This file lives
--     under tools/foundation/diagnostics/, outside the shipped files/ tree, and
--     nothing under files/isf/ references it. The syntax/mock tests assert that.
--   * Running it is not evidence. Only a real capture on a real game build by a
--     human-authorized run produces evidence, and the captured records are tagged
--     `source = "native"` only when the host confirms it is the live game.
--   * It does not modify the world, the RNG used by worldgen, persistent flags or
--     saves. Every write-capable call it could need is either absent or gated
--     behind the explicit disposable-mode guard below.
--
-- Safety model (three independent gates)
-- --------------------------------------
--   gate 1: OPT-IN. The module does nothing unless `configure{ enabled = true }`
--           is called with an explicit sink. Default state is disabled.
--   gate 2: DISPOSABLE MODE. Any call that would perturb ephemeral RNG/entity
--           state requires `configure{ disposable_run = true }` AND a non-empty
--           `run_id`, so it cannot fire in a normal session.
--   gate 3: READ-ONLY DEFAULT. Observation functions only read. The single
--           perturbing helper (`probe_seed_boundaries`) takes a fresh PRNG
--           instance and never touches the game RNG; `probe_entity_content`
--           re-reads an existing entity without modifying it.
--
-- Lua 5.1 / LuaJIT 2.0 compatible; no FFI, no external process, no require().

local M = {}

M.SCHEMA_VERSION = 1
M.PROBE_ID = "isf_native_probe"
M.PROBE_VERSION = "1.0.0"

-- ---------------------------------------------------------------------------
-- Configuration and gates
-- ---------------------------------------------------------------------------

local state = {
	enabled = false,
	disposable_run = false,
	run_id = nil,
	sink = nil,
	records = {},
	sequence = 0,
	host = nil,
}

-- Capability probe: a host is "live" only when the game's own reading API is
-- present. A mock host used by tests must never be labelled native.
local function host_is_live( host )
	if ( type( host ) ~= "table" ) then
		return false, "no host table"
	end
	if ( type( host.HasFlagPersistent ) ~= "function" ) then
		return false, "host lacks HasFlagPersistent (not the game sandbox)"
	end
	if ( type( host.EntityGetTransform ) ~= "function" ) then
		return false, "host lacks EntityGetTransform (not the game sandbox)"
	end
	return true, nil
end

-- configure( options ) -> ok, err
--   options.enabled         : must be exactly true to enable anything
--   options.sink            : function(record) receiving captured records
--   options.host            : the game global table (defaults to _G)
--   options.disposable_run  : true only for an explicitly authorized test run
--   options.run_id          : free-form identifier, required with disposable_run
function M.configure( options )
	options = options or {}

	if ( options.enabled ~= true ) then
		-- Explicit disable path, including teardown.
		state.enabled = false
		state.disposable_run = false
		state.sink = nil
		return false, "probe disabled: options.enabled must be true"
	end

	if ( type( options.sink ) ~= "function" ) then
		state.enabled = false
		return false, "probe not enabled: options.sink must be a function"
	end

	if ( options.disposable_run == true ) then
		if ( type( options.run_id ) ~= "string" or options.run_id == "" ) then
			state.enabled = false
			state.disposable_run = false
			return false, "disposable_run requires a non-empty run_id"
		end
		state.disposable_run = true
		state.run_id = options.run_id
	else
		state.disposable_run = false
		state.run_id = nil
	end

	state.host = options.host or ( type( _G ) == "table" and _G or nil )
	state.sink = options.sink
	state.enabled = true
	state.records = {}
	state.sequence = 0
	return true, nil
end

function M.is_enabled()
	return state.enabled == true
end

function M.is_disposable()
	return state.enabled == true and state.disposable_run == true
end

function M.run_id()
	return state.run_id
end

-- Every record carries the same provenance envelope. `source` is derived from the
-- host capability probe, never from a caller-supplied claim, so test mocks are
-- always labelled "mock".
local function host_value(host,name)
	if type(host[name])~="function" then return nil end
	local ok,value=pcall(host[name])
	if ok then return value end
	return nil
end
local function base_record( kind )
	state.sequence = state.sequence + 1
	local live, why = host_is_live( state.host )
	local host_table = state.host or {}

	local record = {
		schema_version = M.SCHEMA_VERSION,
		probe = M.PROBE_ID,
		probe_version = M.PROBE_VERSION,
		kind = kind,
		seq = state.sequence,
		-- Provenance fields required by the review: build, profile, scope, position.
		source = live and "native" or "mock",
		source_detail = live and "live game sandbox" or ( "not the live game: " .. tostring( why ) ),
		build = {
			-- NOTE: select(1, pcall(f)) returns the pcall STATUS, not f's value.
			-- The value is the second return of pcall.
			api_version = ( function()
				if type( host_table.ModGetAPIVersion ) ~= "function" then return nil end
				local ok, value = pcall( host_table.ModGetAPIVersion )
				if ok then return value end
				return nil
			end )(),
			game_version_hash = type( host_table.__isf_build_hash ) == "string"
				and host_table.__isf_build_hash or nil,
			beta_build = host_value(host_table,"GameIsBetaBuild"),
		},
		profile = {
			run_id = state.run_id,
			disposable = state.disposable_run == true,
			daily_run = host_value(host_table,"GameIsDailyRun"),
			fully_deterministic = host_value(host_table,"GameIsModeFullyDeterministic"),
		},
		scope = nil,
		position = nil,
	}
	return record
end

local function emit( record )
	if ( not state.enabled ) then
		return false, "probe disabled"
	end
	state.records[ #state.records + 1 ] = record
	local ok, err = pcall( state.sink, record )
	if ( not ok ) then
		return false, "sink failed: " .. tostring( err )
	end
	return true, nil
end

-- Read-only access to everything captured so far (for a runbook step that dumps
-- after the fact instead of streaming).
function M.records()
	local copy = {}
	for i = 1, #state.records do
		copy[ i ] = state.records[ i ]
	end
	return copy
end

function M.reset()
	state.records = {}
	state.sequence = 0
end

-- ---------------------------------------------------------------------------
-- Date/time capture (the potion.lua 8-value finding)
-- ---------------------------------------------------------------------------

-- Capture the FULL return tuple of a date function, including arity.
--
-- The official API text documents 6 return values for both
-- GameGetDateAndTimeUTC and GameGetDateAndTimeLocal, but shipped
-- data/scripts/items/potion.lua reads EIGHT from the Local variant:
--   local year,month,day,temp1,temp2,temp3,jussi,mammi = GameGetDateAndTimeLocal()
-- So this must record how many values actually came back and keep them all,
-- including nils, rather than trusting the documentation.
local function capture_datetime( name, fn )
	local values = {}
	local count = 0
	if ( type( fn ) == "function" ) then
		-- Preserve the TRUE return arity. `local a,b,c,... = pcall(fn)` reports
		-- the number of named slots, and `{pcall(fn)}` stops at the first nil, so
		-- both would misreport how many values the engine actually returned.
		-- The explicit count from select("#", ...) is the only reliable source.
		local function pack( ... )
			return { n = select( "#", ... ), ... }
		end
		local results = pack( pcall( fn ) )
		local ok = results[ 1 ]
		if ( not ok ) then
			return nil, "call failed: " .. tostring( results[ 2 ] )
		end
		-- results[1] is the pcall status; the returned values follow it.
		count = results.n - 1
		for i = 1, count do
			values[ i ] = results[ i + 1 ]
		end
	end
	return {
		name = name,
		count = count,
		values = values,
		-- Documented arity, so a mismatch is visible in the record itself.
		documented_count = 6,
		arity_mismatch = ( count ~= 0 and count ~= 6 ),
	}, nil
end

-- probe_datetime( options )
-- Pure read. Records both variants plus the engine's own frame/time counters so a
-- later comparison can align observations with a session.
function M.probe_datetime( options )
	options = options or {}
	if ( not state.enabled ) then
		return false, "probe disabled"
	end
	local host = state.host or {}
	local record = base_record( "datetime" )
	record.scope = options.scope or "session"
	record.position = nil

	local utc, utc_err = capture_datetime( "GameGetDateAndTimeUTC", host.GameGetDateAndTimeUTC )
	local local_time, local_err = capture_datetime( "GameGetDateAndTimeLocal", host.GameGetDateAndTimeLocal )
	record.utc = utc
	record.local_time = local_time
	record.errors = {}
	if ( utc_err ) then record.errors[ #record.errors + 1 ] = "utc: " .. utc_err end
	if ( local_err ) then record.errors[ #record.errors + 1 ] = "local: " .. local_err end

	-- Engine counters that help align a record with a run, read-only.
	if ( type( host.GameGetFrameNum ) == "function" ) then
		local ok, frame = pcall( host.GameGetFrameNum )
		if ( ok ) then record.frame = frame end
	end
	if ( type( host.GameGetRealWorldTimeSinceStarted ) == "function" ) then
		local ok, t = pcall( host.GameGetRealWorldTimeSinceStarted )
		if ( ok ) then record.real_time_seconds = t end
	end
	return emit( record )
end

-- ---------------------------------------------------------------------------
-- Persistent profile capture (read-only)
-- ---------------------------------------------------------------------------

-- probe_profile( options )
--   options.flags : array of persistent flag ids to test (read-only HasFlagPersistent)
-- Records which flags are set. Never adds, removes or rewrites a flag.
function M.probe_profile( options )
	options = options or {}
	if ( not state.enabled ) then
		return false, "probe disabled"
	end
	local host = state.host or {}
	local record = base_record( "profile" )
	record.scope = options.scope or "session"

	local flags = options.flags or {}
	local observed = {}
	if ( type( host.HasFlagPersistent ) == "function" ) then
		for i = 1, #flags do
			local flag = flags[ i ]
			local ok, value = pcall( host.HasFlagPersistent, flag )
			observed[ #observed + 1 ] = {
				flag = flag,
				set = ( ok and value == true ) or false,
				error = ( not ok ) and tostring( value ) or nil,
			}
		end
	else
		record.errors = { "host lacks HasFlagPersistent; flags not observable" }
	end
	record.flags = observed
	return emit( record )
end

-- ---------------------------------------------------------------------------
-- Boundary A vs boundary B: the coordinate question
-- ---------------------------------------------------------------------------

-- Reduce a coordinate to the candidate representations the hypotheses consider.
-- Keeping all of them on the record is the point: the probe must not decide.
local function coordinate_forms( value )
	local forms = {
		exact = value,
	}
	-- Round-half-to-even, as the reference tools do for wand creation.
	local f = math.floor( value )
	local diff = value - f
	local rhe
	if ( diff < 0.5 ) then
		rhe = f
	elseif ( diff > 0.5 ) then
		rhe = f + 1
	else
		rhe = ( f % 2 == 0 ) and f or ( f + 1 )
	end
	forms.round_half_even = rhe
	forms.floor = f
	-- Binary32 narrowing: exact for the f32 grid at these magnitudes.
	forms.float32 = M.float32( value )
	forms.integral = ( value == f )
	return forms
end

-- Round a double to the nearest IEEE-754 binary32 value (round-half-to-even).
-- Self-contained so the probe has no dependency on production modules.
function M.float32( x )
	if ( type( x ) ~= "number" ) then
		return nil
	end
	if ( x ~= x or x == 0 or x == math.huge or x == -math.huge ) then
		return x
	end
	local sign = 1
	if ( x < 0 ) then
		sign = -1
		x = -x
	end
	local e = math.floor( math.log( x ) / math.log( 2 ) )
	local p = 2 ^ e
	while ( p > x ) do
		e = e - 1
		p = 2 ^ e
	end
	while ( p * 2 <= x ) do
		e = e + 1
		p = 2 ^ e
	end
	local scale = 2 ^ ( 23 - e )
	local m = x * scale
	local r = math.floor( m )
	local frac = m - r
	if ( frac > 0.5 ) then
		r = r + 1
	elseif ( frac == 0.5 and r % 2 == 1 ) then
		r = r + 1
	end
	return sign * ( r / scale )
end

-- probe_seed_boundaries( options )
--
-- Compares the two candidate seed boundaries for a Holy Mountain wand slot,
-- WITHOUT touching game state:
--
--   boundary A ("selection"): the raw Lua slot x used by generate_shop_wand's
--     own SetRandomSeed, which decides wand_level vs wand_unshuffle.
--   boundary B ("content"):   the position gun_procedural.lua later reads from
--     EntityGetTransform, which seeds every stat and card.
--
-- It draws the selection roll for EVERY candidate representation of x, on fresh
-- PRNG instances, and records the results side by side. It does not choose.
--
-- options: seed, shop_x, shop_y, slot, count (default 5), prng (module table),
--          entity_x/entity_y (optional observed EntityGetTransform result)
function M.probe_seed_boundaries( options )
	options = options or {}
	if ( not state.enabled ) then
		return false, "probe disabled"
	end
	local prng = options.prng
	if ( type( prng ) ~= "table" or type( prng.new ) ~= "function" ) then
		-- Fall back to loading the shared PRNG from the mod namespace.
		local ok, loaded = pcall( dofile_once,
			"mods/interesting_seed_filter/files/isf/random/prng.lua" )
		if ( not ok or type( loaded ) ~= "table" ) then
			return false, "no PRNG module available for boundary probing"
		end
		prng = loaded
	end

	local seed = options.seed
	if ( type( seed ) ~= "number" ) then
		return false, "probe_seed_boundaries requires a numeric seed"
	end

	local count = options.count or 5
	local slot = options.slot or 1
	local shop_x = options.shop_x
	local shop_y = options.shop_y
	if ( type( shop_x ) ~= "number" or type( shop_y ) ~= "number" ) then
		return false, "probe_seed_boundaries requires shop_x and shop_y"
	end

	local item_width = 132 / count
	local raw_slot_x = shop_x + ( slot - 1 ) * item_width
	local x_forms = coordinate_forms( raw_slot_x )

	local record = base_record( "seed_boundaries" )
	record.scope = options.scope or "holy_mountain_wand_shop"
	record.position = {
		shop_x = shop_x,
		shop_y = shop_y,
		slot = slot,
		count = count,
		raw_slot_x = raw_slot_x,
	}

	record.boundary_a = {
		description = "generate_shop_wand SetRandomSeed on raw Lua slot x",
		candidates = {},
	}
	-- Boundary A: selection roll for each candidate representation.
	local names = { "exact", "round_half_even", "floor", "float32" }
	for i = 1, #names do
		local name = names[ i ]
		local x = x_forms[ name ]
		local rng = prng.new( seed )
		rng:SetRandomSeed( x, shop_y )
		local roll = rng:Random( 0, 100 )
		record.boundary_a.candidates[ #record.boundary_a.candidates + 1 ] = {
			mode = name,
			x = x,
			roll = roll,
			shuffle = roll <= 50,
			wand_type = ( roll <= 50 and "wand_level_" or "wand_unshuffle_" )
				.. "0" .. tostring( options.tier or 1 ),
		}
	end

	-- Boundary B: what the engine stored. Only filled when the caller supplies an
	-- observed EntityGetTransform result; otherwise explicitly unknown.
	record.boundary_b = {
		description = "gun_procedural SetRandomSeed from EntityGetTransform",
		observed = nil,
		candidates = {},
	}
	if ( type( options.entity_x ) == "number" and type( options.entity_y ) == "number" ) then
		local entity_forms = coordinate_forms( options.entity_x )
		record.boundary_b.observed = {
			x = options.entity_x,
			y = options.entity_y,
			forms = entity_forms,
		}
		for i = 1, #names do
			local name = names[ i ]
			local x = entity_forms[ name ]
			local rng = prng.new( seed )
			rng:SetRandomSeed( x, options.entity_y )
			-- First draw of the content path is the level-1 cost coin flip.
			local first = rng:Random( 0, 100 )
			record.boundary_b.candidates[ #record.boundary_b.candidates + 1 ] = {
				mode = name,
				x = x,
				first_draw = first,
			}
		end
	else
		record.boundary_b.note =
			"entity position not supplied; boundary B remains unobserved "
			.. "(this is the unresolved question, not a failure)"
	end

	-- Agreement analysis across the two boundaries, for the report consumer.
	local a_modes = {}
	for _, c in ipairs( record.boundary_a.candidates ) do
		a_modes[ c.mode ] = c.wand_type
	end
	record.agreement = {
		boundary_a_types = a_modes,
		a_is_mode_sensitive = false,
		note = "compare boundary_a and boundary_b against a native capture",
	}
	-- Flag when candidate representations disagree at all.
	local first_type = nil
	for _, c in ipairs( record.boundary_a.candidates ) do
		if ( first_type == nil ) then
			first_type = c.wand_type
		elseif ( c.wand_type ~= first_type ) then
			record.agreement.a_is_mode_sensitive = true
		end
	end

	-- This path only ever used fresh PRNG instances; the game RNG is untouched.
	record.side_effects = "none: fresh PRNG instances, no SetWorldSeed, no entity writes"

	return emit( record )
end

-- ---------------------------------------------------------------------------
-- Entity observation (read-only)
-- ---------------------------------------------------------------------------

-- probe_entity_transform( options )
-- Reads EntityGetTransform for a specific entity and records the FULL tuple
-- (documented as x, y, rotation, scale_x, scale_y) plus each coordinate form.
-- This is the observation that resolves boundary B.
function M.probe_entity_transform( options )
	options = options or {}
	if ( not state.enabled ) then
		return false, "probe disabled"
	end
	local host = state.host or {}
	local entity_id = options.entity_id
	if ( type( entity_id ) ~= "number" ) then
		return false, "probe_entity_transform requires a numeric entity_id"
	end
	if ( type( host.EntityGetTransform ) ~= "function" ) then
		return false, "host lacks EntityGetTransform"
	end

	local record = base_record( "entity_transform" )
	record.scope = options.scope or "holy_mountain_wand"
	record.entity_id = entity_id

	local ok, x, y, rotation, scale_x, scale_y = pcall( host.EntityGetTransform, entity_id )
	if ( not ok ) then
		record.error = tostring( x )
		record.position = nil
		return emit( record )
	end

	record.transform = {
		x = x,
		y = y,
		rotation = rotation,
		scale_x = scale_x,
		scale_y = scale_y,
		return_count = 5,
	}
	record.position = { x = x, y = y }
	if ( type( x ) == "number" ) then
		record.coordinate_forms = coordinate_forms( x )
	end

	-- Entity identity/description, all read-only.
	if ( type( host.EntityGetName ) == "function" ) then
		local okn, name = pcall( host.EntityGetName, entity_id )
		if ( okn ) then record.entity_name = name end
	end
	if ( type( host.EntityGetTags ) == "function" ) then
		local okt, tags = pcall( host.EntityGetTags, entity_id )
		if ( okt ) then record.entity_tags = tags end
	end
	record.side_effects = "none: read-only component queries"
	return emit( record )
end

-- probe_wand_contents( options )
-- Reads a wand entity's ability/gun config and deck after initialization:
-- slots (deck capacity), cards, Always Cast, and the key stats.
-- Read-only: uses EntityGetFirstComponent / ComponentGetValue2 only.
function M.probe_wand_contents( options )
	options = options or {}
	if ( not state.enabled ) then
		return false, "probe disabled"
	end
	local host = state.host or {}
	local entity_id = options.entity_id
	if ( type( entity_id ) ~= "number" ) then
		return false, "probe_wand_contents requires a numeric entity_id"
	end
	if ( type( host.EntityGetFirstComponent ) ~= "function"
		or type( host.ComponentGetValue2 ) ~= "function" ) then
		return false, "host lacks component query functions"
	end

	local record = base_record( "wand_contents" )
	record.scope = options.scope or "holy_mountain_wand"
	record.entity_id = entity_id

	local ok, ability = pcall( host.EntityGetFirstComponent, entity_id, "AbilityComponent" )
	if ( not ok or ability == nil ) then
		record.error = "no AbilityComponent on entity " .. tostring( entity_id )
		return emit( record )
	end

	local function read( component, field )
		local okv, value = pcall( host.ComponentGetValue2, component, field )
		if ( okv ) then return value end
		return nil
	end

	record.gun_config = {
		deck_capacity = read( ability, "deck_capacity" ),
		actions_per_round = read( ability, "actions_per_round" ),
		reload_time = read( ability, "reload_time" ),
		fire_rate_wait = read( ability, "fire_rate_wait" ),
		spread_degrees = read( ability, "spread_degrees" ),
		mana_max = read( ability, "mana_max" ),
		mana_charge_speed = read( ability, "mana_charge_speed" ),
		shuffle_deck_when_empty = read( ability, "shuffle_deck_when_empty" ),
	}

	-- Always Cast: a separate component/field, never a deck card.
	local ok_ac, always_cast = pcall( host.EntityGetFirstComponent, entity_id, "ItemComponent" )
	if ( ok_ac and always_cast ~= nil ) then
		record.always_cast_component_present = true
	end

	-- Deck cards, if the host can enumerate them.
	record.cards = {}
	record.cards_source = "not enumerated by this host"
	if ( type( host.GetWandDeckCards ) == "function" ) then
		local okd, cards = pcall( host.GetWandDeckCards, entity_id )
		if ( okd and type( cards ) == "table" ) then
			for i = 1, #cards do
				record.cards[ i ] = cards[ i ]
			end
			record.cards_source = "GetWandDeckCards"
		end
	end

	record.side_effects = "none: component reads only"
	return emit( record )
end

-- ---------------------------------------------------------------------------
-- Holy Mountain shop capture (read-only, before any purchase)
-- ---------------------------------------------------------------------------

-- Snapshot the entities near a Holy Mountain shop anchor.
--
-- Uses EntityGetInRadius (read-only) and records each entity's transform, tags
-- and name. Cards/wands are distinguishable by tags/components, which is exactly
-- what a "before buying" capture needs.
--
-- options: shop_x, shop_y, radius (default 200), label
function M.probe_shop_entities( options )
	options = options or {}
	if ( not state.enabled ) then
		return false, "probe disabled"
	end
	local host = state.host or {}
	if ( type( host.EntityGetInRadius ) ~= "function" ) then
		return false, "host lacks EntityGetInRadius"
	end

	local shop_x = options.shop_x
	local shop_y = options.shop_y
	if ( type( shop_x ) ~= "number" or type( shop_y ) ~= "number" ) then
		return false, "probe_shop_entities requires shop_x and shop_y"
	end
	local radius = options.radius or 200

	local record = base_record( "shop_entities" )
	record.scope = options.scope or "holy_mountain_shop"
	record.label = options.label
	record.position = { x = shop_x, y = shop_y, radius = radius }

	local ok, list = pcall( host.EntityGetInRadius, shop_x, shop_y, radius )
	if ( not ok or type( list ) ~= "table" ) then
		record.error = "EntityGetInRadius failed: " .. tostring( list )
		record.entities = {}
		return emit( record )
	end

	local entities = {}
	for i = 1, #list do
		local id = list[ i ]
		local item = { entity_id = id }
		if ( type( host.EntityGetTransform ) == "function" ) then
			local okt, x, y, rot = pcall( host.EntityGetTransform, id )
			if ( okt ) then
				item.x = x
				item.y = y
				item.rotation = rot
				item.coordinate_forms = coordinate_forms( x )
			end
		end
		if ( type( host.EntityGetName ) == "function" ) then
			local okn, name = pcall( host.EntityGetName, id )
			if ( okn ) then item.name = name end
		end
		if ( type( host.EntityGetTags ) == "function" ) then
			local okt, tags = pcall( host.EntityGetTags, id )
			if ( okt ) then item.tags = tags end
		end
		-- Distinguish the shop's wand/card entities from scenery.
		if ( type( host.EntityGetFirstComponent ) == "function" ) then
			local oka, ability = pcall( host.EntityGetFirstComponent, id, "AbilityComponent" )
			item.has_ability = ( oka and ability ~= nil )
			local oki, itemcomp = pcall( host.EntityGetFirstComponent, id, "ItemComponent" )
			item.has_item = ( oki and itemcomp ~= nil )
		end
		entities[ #entities + 1 ] = item
	end
	record.entities = entities
	record.entity_count = #entities
	record.side_effects = "none: radius query and component reads only"
	return emit( record )
end

-- ---------------------------------------------------------------------------
-- Perk capture (read-only; no picks, no rerolls)
-- ---------------------------------------------------------------------------

-- probe_perk_entities( options )
-- Lists the perk pickup entities offered at a Holy Mountain altar, before any
-- pick. Never picks a perk, never rerolls, never writes a flag.
function M.probe_perk_entities( options )
	options = options or {}
	if ( not state.enabled ) then
		return false, "probe disabled"
	end
	local host = state.host or {}
	if ( type( host.EntityGetInRadius ) ~= "function" ) then
		return false, "host lacks EntityGetInRadius"
	end
	local x, y = options.x, options.y
	if ( type( x ) ~= "number" or type( y ) ~= "number" ) then
		return false, "probe_perk_entities requires x and y"
	end
	local radius = options.radius or 160

	local record = base_record( "perk_entities" )
	record.scope = options.scope or "holy_mountain_perks"
	record.label = options.label
	record.position = { x = x, y = y, radius = radius }

	local ok, list = pcall( host.EntityGetInRadius, x, y, radius )
	if ( not ok or type( list ) ~= "table" ) then
		record.error = "EntityGetInRadius failed: " .. tostring( list )
		record.perks = {}
		return emit( record )
	end

	local perks = {}
	for i = 1, #list do
		local id = list[ i ]
		local item = { entity_id = id }
		if ( type( host.EntityGetTransform ) == "function" ) then
			local okt, ex, ey = pcall( host.EntityGetTransform, id )
			if ( okt ) then item.x = ex item.y = ey end
		end
		if ( type( host.EntityGetTags ) == "function" ) then
			local okt, tags = pcall( host.EntityGetTags, id )
			if ( okt ) then
				item.tags = tags
				-- Perk pickups are tagged; keep only likely candidates.
				local tagged = tostring( tags or "" )
				if ( tagged:find( "perk", 1, true ) ) then
					perks[ #perks + 1 ] = item
				end
			end
		end
	end
	record.perks = perks
	record.perk_count = #perks
	record.side_effects = "none: radius query and tag reads only; no pick, no reroll"
	return emit( record )
end

-- ---------------------------------------------------------------------------
-- Optional independent reroll observation
-- ---------------------------------------------------------------------------

-- probe_reroll_sequence( options )
--
-- Records what the *independent* reroll sequence would offer, WITHOUT rerolling.
--
-- Requires disposable mode: it needs an explicit opt-in to even simulate, because
-- a careless implementation could re-roll a live altar. This version only reads a
-- caller-supplied list of perk names (e.g. from a fresh altar's entities) and
-- records them; it never calls any reroll API and never writes
-- TEMPLE_PERK_REROLL_COUNT or any other flag.
function M.probe_reroll_sequence( options )
	options = options or {}
	if ( not state.enabled ) then
		return false, "probe disabled"
	end
	if ( not M.is_disposable() ) then
		return false,
			"probe_reroll_sequence requires disposable_run (it must never run in an ordinary game)"
	end
	local record = base_record( "reroll_sequence" )
	record.scope = options.scope or "holy_mountain_perks_reroll"
	record.label = options.label
	record.note = "observation only: no reroll was performed, no flag was written"

	local rounds = options.rounds or {}
	record.rounds = {}
	for i = 1, #rounds do
		local round = rounds[ i ] or {}
		local names = {}
		for j = 1, #( round.perks or {} ) do
			names[ j ] = round.perks[ j ]
		end
		record.rounds[ i ] = {
			round = i,
			perks = names,
			source = round.source or "caller-supplied observation",
		}
	end
	record.round_count = #record.rounds
	record.side_effects = "none: no reroll API call, no flag write"
	return emit( record )
end

-- ---------------------------------------------------------------------------
-- Sink helpers
-- ---------------------------------------------------------------------------

-- Render a record as a stable, line-oriented text block (for GamePrint or a log).
function M.format( record )
	local out = {}
	local function line( s ) out[ #out + 1 ] = s end
	line( "[isf-probe] kind=" .. tostring( record.kind )
		.. " seq=" .. tostring( record.seq )
		.. " source=" .. tostring( record.source ) )
	line( "  probe=" .. tostring( record.probe ) .. " v" .. tostring( record.probe_version ) )
	line( "  scope=" .. tostring( record.scope ) .. " run_id=" .. tostring( record.profile and record.profile.run_id ) )
	if ( record.position ) then
		line( string.format( "  position=(%s,%s)",
			tostring( record.position.x ), tostring( record.position.y ) ) )
	end
	if ( record.boundary_a ) then
		for _, c in ipairs( record.boundary_a.candidates ) do
			line( string.format( "  A/%s x=%.6f roll=%d type=%s",
				c.mode, c.x, c.roll, tostring( c.wand_type ) ) )
		end
	end
	if ( record.boundary_b ) then
		if ( record.boundary_b.observed ) then
			line( string.format( "  B observed x=%.6f", record.boundary_b.observed.x ) )
			for _, c in ipairs( record.boundary_b.candidates ) do
				line( string.format( "  B/%s x=%.6f first=%d", c.mode, c.x, c.first_draw ) )
			end
		else
			line( "  B unobserved: " .. tostring( record.boundary_b.note ) )
		end
	end
	if ( record.utc ) then
		line( "  utc count=" .. tostring( record.utc.count )
			.. " mismatch=" .. tostring( record.utc.arity_mismatch ) )
	end
	if ( record.local_time ) then
		line( "  local count=" .. tostring( record.local_time.count )
			.. " mismatch=" .. tostring( record.local_time.arity_mismatch ) )
	end
	if ( record.side_effects ) then
		line( "  side_effects=" .. tostring( record.side_effects ) )
	end
	return table.concat( out, "\n" )
end

return M
