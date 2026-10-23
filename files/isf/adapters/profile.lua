-- files/isf/adapters/profile.lua
--
-- Generation-condition snapshot adapter (WORKER_CONTRACT.md "生成条件与报告";
-- PRD section 5 input contract).
--
-- A profile is an immutable, explicitly-passed description of the conditions a
-- prediction is made under:
--
--   id             : stable identifier of this snapshot (string)
--   game_version   : build hash / version string the snapshot belongs to
--   unlocked_flags : map of Noita persistent-flag IDs -> boolean
--   persistent_flags : map of non-unlock persistent markers -> boolean
--   calendar       : date/time the snapshot was taken (year/month/day/hour/...)
--
-- Invariants enforced here:
--   * snapshots are deep-copied on construction and frozen (writing to a
--     profile raises an error), so no provider can mutate shared state and no
--     later game state change can silently alter an in-flight evaluation;
--   * providers receive the profile explicitly; nothing in this module reads
--     global game state, so identical input always yields identical output;
--   * `normalize` is deterministic: key order in the serialized identity hash
--     depends only on sorted keys, never on table iteration order.
--
-- Lua 5.1 / LuaJIT compatible; no external dependencies.

local M = {}

M.SCHEMA_VERSION = 1
M.DEFAULT_ID = "unspecified"

-- Deep-freeze a snapshot.
--
-- A plain `__newindex` on the copied table is NOT enough: Lua only consults
-- `__newindex` when a key is absent, so `profile.unlocked_flags.SOME_FLAG = x`
-- would silently overwrite an existing flag. Each table is therefore replaced by
-- an empty read-through proxy whose `__index` points at a private backing store
-- and whose `__newindex` always raises. `pairs` is forwarded via `__pairs` where
-- the host supports it (Lua 5.2+/LuaJIT 2.1); on plain Lua 5.1/JIT 2.0 the
-- backing store is reachable for reading through the proxy metamethod and
-- ipairs-style arrays still work through `__index`.
-- Map from a frozen proxy to its private backing store. A side table is used
-- rather than a sentinel key inside the backing store so that `pairs(backing)`
-- yields exactly the snapshot's own entries.
local BACKINGS = setmetatable( {}, { __mode = "k" } )

local function readonly_proxy( backing )
	local proxy = setmetatable( {}, {
		-- The proxy itself holds no data keys, so every assignment is a *new*
		-- key and `__newindex` always fires. That is what makes a plain Lua 5.1
		-- table genuinely read-only; a table that already held the keys would
		-- bypass `__newindex` on writes to existing fields.
		__index = backing,
		__newindex = function()
			error( "profile snapshot is immutable; build a new snapshot instead", 2 )
		end,
		__metatable = "isf.profile.frozen",
	} )
	BACKINGS[ proxy ] = backing
	return proxy
end

local function freeze( value, seen )
	if ( type( value ) ~= "table" ) then
		return value
	end
	seen = seen or {}
	if ( seen[ value ] ) then
		return seen[ value ]
	end
	local backing = {}
	local proxy = readonly_proxy( backing )
	seen[ value ] = proxy
	for k, v in pairs( value ) do
		backing[ k ] = freeze( v, seen )
	end
	return proxy
end

-- Backing store of a frozen table, or the table itself when it is not frozen.
-- Module code (and only module code) uses this to iterate a snapshot map:
-- Lua 5.1's `pairs`/`ipairs` and `#` operate on a proxy's own (empty) keys, so
-- consumers must iterate the backing store.
function M.unwrap( value )
	if ( type( value ) ~= "table" ) then
		return value
	end
	local backing = BACKINGS[ value ]
	if ( type( backing ) == "table" ) then
		return backing
	end
	return value
end

-- Copy of a frozen map as a plain { key = value } table, safe to iterate.
-- Returns an empty table for anything that is not a table, so callers can use it
-- while validating untrusted input without a type guard first.
function M.flags( value )
	local out = {}
	local backing = M.unwrap( value )
	if ( type( backing ) ~= "table" ) then
		return out
	end
	for k, v in pairs( backing ) do
		out[ k ] = v
	end
	return out
end

-- Copy of a frozen list as a plain array, so `#` and `ipairs` behave.
function M.list( value )
	local out = {}
	local backing = M.unwrap( value )
	if ( type( backing ) ~= "table" ) then
		return out
	end
	for i = 1, #backing do
		out[ i ] = backing[ i ]
	end
	return out
end

local function is_string( v )
	return type( v ) == "string" and v ~= ""
end

-- Deep copy of plain data, transparently reading through frozen proxies.
--
-- This is the counterpart to freeze() and is what makes re-snapshotting work:
-- `profile.new( existing_frozen_profile )` must yield an equal snapshot, but a
-- frozen proxy holds no own keys, so `pairs(proxy)` yields nothing and `#proxy`
-- is 0 on Lua 5.1. Every read therefore goes through M.unwrap first.
local function deep_copy( value, seen )
	if ( type( value ) ~= "table" ) then
		return value
	end
	seen = seen or {}
	if ( seen[ value ] ) then
		return seen[ value ]
	end
	local out = {}
	seen[ value ] = out
	local source = M.unwrap( value )
	for k, v in pairs( source ) do
		out[ k ] = deep_copy( v, seen )
	end
	return out
end

-- Validate and copy a raw snapshot table. Returns profile, errors.
-- `errors` is a list of { code, message } objects; a profile is still returned
-- when only warnings apply so callers can decide how strict to be.
--
-- `raw` may be a plain table or an already-frozen snapshot; both are copied by
-- value so the result never aliases the caller's tables.
function M.normalize( raw )
	local errors = {}
	local warnings = {}

	if ( type( raw ) ~= "table" ) then
		return nil, { { code = "bad_profile", message = "profile must be a table" } }
	end

	-- Accept a frozen snapshot as input: read fields through the proxy.
	local source = M.unwrap( raw )

	local id = source.id
	if ( not is_string( id ) ) then
		id = M.DEFAULT_ID
		warnings[ #warnings + 1 ] = {
			code = "missing_profile_id",
			message = "profile has no id; using '" .. M.DEFAULT_ID .. "' (not reproducible)",
		}
	end

	local game_version = source.game_version
	if ( not is_string( game_version ) ) then
		game_version = "unknown"
		warnings[ #warnings + 1 ] = {
			code = "missing_game_version",
			message = "profile has no game_version; parity cannot be attributed to a build",
		}
	end

	-- Copy the flag maps entry by entry. M.flags() reads through a frozen proxy
	-- and returns a fresh plain table, so the validation loop below actually sees
	-- the entries instead of an empty proxy.
	local unlocked = M.flags( source.unlocked_flags or {} )
	if ( type( source.unlocked_flags ) ~= "table" and source.unlocked_flags ~= nil ) then
		errors[ #errors + 1 ] = {
			code = "bad_unlocked_flags",
			message = "unlocked_flags must be a map of flag id -> boolean",
		}
		unlocked = {}
	end
	for flag, value in pairs( unlocked ) do
		if ( type( flag ) ~= "string" ) then
			errors[ #errors + 1 ] = {
				code = "bad_unlocked_flag_key",
				message = "unlocked_flags key must be a string flag id",
			}
		elseif ( type( value ) ~= "boolean" ) then
			errors[ #errors + 1 ] = {
				code = "bad_unlocked_flag_value",
				message = "unlocked_flags['" .. flag .. "'] must be a boolean",
			}
		end
	end

	local persistent = M.flags( source.persistent_flags or {} )
	if ( type( source.persistent_flags ) ~= "table" and source.persistent_flags ~= nil ) then
		errors[ #errors + 1 ] = {
			code = "bad_persistent_flags",
			message = "persistent_flags must be a map of flag id -> boolean",
		}
		persistent = {}
	end

	local calendar = source.calendar
	if ( calendar ~= nil and type( calendar ) ~= "table" ) then
		errors[ #errors + 1 ] = {
			code = "bad_calendar",
			message = "calendar must be a table of date/time fields",
		}
		calendar = nil
	end
	calendar = calendar and deep_copy( calendar ) or {}

	-- Diagnostics are regenerated for the new snapshot, but an input that was
	-- already a profile may carry notes about its own construction (e.g. a
	-- degraded in-game read). Carry those forward instead of silently dropping
	-- them, de-duplicating by code so that repeated re-snapshotting cannot grow
	-- the list without bound.
	local function merge_diagnostics( inherited, fresh )
		local out = {}
		local seen = {}
		for i = 1, #inherited do
			local item = inherited[ i ]
			local code = type( item ) == "table" and item.code or nil
			if ( code == nil or not seen[ code ] ) then
				out[ #out + 1 ] = deep_copy( item )
				if ( code ~= nil ) then
					seen[ code ] = true
				end
			end
		end
		for i = 1, #fresh do
			local item = fresh[ i ]
			local code = type( item ) == "table" and item.code or nil
			if ( code == nil or not seen[ code ] ) then
				out[ #out + 1 ] = deep_copy( item )
				if ( code ~= nil ) then
					seen[ code ] = true
				end
			end
		end
		return out
	end

	local carried = merge_diagnostics( M.list( source.warnings ), warnings )
	local carried_errors = merge_diagnostics( M.list( source.errors ), errors )

	local profile = {
		schema_version = M.SCHEMA_VERSION,
		id = id,
		game_version = game_version,
		unlocked_flags = unlocked,
		persistent_flags = persistent,
		calendar = calendar,
		warnings = carried,
		errors = carried_errors,
	}
	return profile, carried_errors
end

-- Build a frozen snapshot. `raw` is copied, so later mutation of the caller's
-- table cannot change an evaluation already in flight.
function M.new( raw )
	local profile, errors = M.normalize( raw )
	if ( profile == nil ) then
		return nil, errors
	end
	local frozen = freeze( profile )
	return frozen, errors
end

-- Diagnostics captured on a snapshot, as plain iterable arrays.
function M.warnings( profile )
	return M.list( profile.warnings )
end

function M.errors( profile )
	return M.list( profile.errors )
end

-- Read an unlock flag; missing entries mean "not unlocked" (the game only sets
-- a flag when the unlock happened). Callers must treat a missing flag as false,
-- never as "unknown" silently: providers record which gated spells were
-- excluded and why.
function M.has_flag( profile, flag )
	if ( type( profile ) ~= "table" or type( flag ) ~= "string" ) then
		return false
	end
	local flags = profile.unlocked_flags
	if ( type( flags ) ~= "table" ) then
		return false
	end
	return flags[ flag ] == true
end

function M.has_persistent( profile, flag )
	if ( type( profile ) ~= "table" or type( flag ) ~= "string" ) then
		return false
	end
	local flags = profile.persistent_flags
	if ( type( flags ) ~= "table" ) then
		return false
	end
	return flags[ flag ] == true
end

-- Stable identity string for a profile: id + version + sorted flag digest.
-- Used in reports so a result can be attributed to exact conditions without
-- embedding the whole snapshot. Deterministic across runs and Lua builds
-- because it only depends on sorted keys.
function M.identity( profile )
	local parts = {
		tostring( profile.id ),
		tostring( profile.game_version ),
	}

	local function digest( map, label )
		map = M.unwrap( map )
		local keys = {}
		for k, v in pairs( map or {} ) do
			if ( v == true ) then
				keys[ #keys + 1 ] = tostring( k )
			end
		end
		table.sort( keys )
		parts[ #parts + 1 ] = label .. "=" .. tostring( #keys )
		-- A compact, order-independent checksum (FNV-1a style, 32-bit safe in
		-- doubles) so two snapshots can be compared without shipping the list.
		local hash = 2166136261
		for i = 1, #keys do
			local key = keys[ i ]
			for j = 1, #key do
				hash = ( hash * 16777619 + key:byte( j ) ) % 4294967296
			end
			hash = ( hash * 16777619 + 31 ) % 4294967296
		end
		parts[ #parts + 1 ] = label .. "_hash=" .. string.format( "%08x", hash )
	end

	digest( profile.unlocked_flags, "unlocked" )
	digest( profile.persistent_flags, "persistent" )

	-- Encode every calendar field, including false and unknown holiday flags.
	-- Length prefixes prevent delimiters in a field from aliasing another input.
	local calendar = M.unwrap( profile.calendar ) or {}
	local keys = {}
	for key in pairs( calendar ) do keys[ #keys + 1 ] = key end
	table.sort( keys )
	for _, key in ipairs( keys ) do
		local value = type( calendar[key] ) .. ":" .. tostring( calendar[key] )
		parts[ #parts + 1 ] = "calendar:" .. #key .. ":" .. key .. ":" .. #value .. ":" .. value
	end
	return table.concat( parts, "|" )
end

-- Plain-table copy of a profile for embedding in a report. Flags are emitted
-- as sorted arrays so the output is byte-identical between runs.
function M.describe( profile )
	local function sorted_true( map )
		map = M.unwrap( map )
		local out = {}
		for k, v in pairs( map or {} ) do
			if ( v == true ) then
				out[ #out + 1 ] = tostring( k )
			end
		end
		table.sort( out )
		return out
	end

	local calendar = {}
	for _, key in ipairs( { "year", "month", "day", "hour", "minute", "second", "jussi", "mammi" } ) do
		if ( ( profile.calendar or {} )[ key ] ~= nil ) then
			calendar[ key ] = profile.calendar[ key ]
		end
	end

	return {
		schema_version = profile.schema_version,
		id = profile.id,
		game_version = profile.game_version,
		identity = M.identity( profile ),
		unlocked_flags = sorted_true( profile.unlocked_flags ),
		persistent_flags = sorted_true( profile.persistent_flags ),
		calendar = calendar,
	}
end

return M
