-- tests/foundation/profile_clone_spec.lua
--
-- Regressions for the reviewed snapshot-copy defect.
--
-- Reported failure: profile.new( existing_frozen_profile ) silently produced an
-- empty snapshot, because normalize iterated the frozen proxy with pairs(), and a
-- proxy has no own keys on Lua 5.1. Symptoms were has_flag(q) == false and
-- q.calendar.day == nil even though p had them set.
--
-- These tests pin the corrected behaviour: re-snapshotting a frozen profile is a
-- by-value clone that preserves flags, calendar and diagnostics, keeps the new
-- snapshot immutable, and is identity-equal to the original.

local profile_lib = __isf_load("mods/interesting_seed_filter/files/isf/adapters/profile.lua")

local FLAG = "card_unlocked_nuke"
local FLAG2 = "card_unlocked_duplicate"

local function sample()
	local p = profile_lib.new( {
		id = "same",
		game_version = "test",
		unlocked_flags = { [ FLAG ] = true, [ FLAG2 ] = true },
		persistent_flags = { biome_0_secret_unlocked = true },
		calendar = { year = 2026, month = 10, day = 22, hour = 13, minute = 45 },
	} )
	return p
end

T.describe("clone: the exact reviewed reproduction")
do
	local p = profile_lib.new( {
		id = "same",
		game_version = "test",
		unlocked_flags = { [ FLAG ] = true },
		calendar = { year = 2026, month = 10, day = 22 },
	} )
	local q = profile_lib.new( p )

	T.check( profile_lib.has_flag( p, FLAG ), "source profile has the flag" )
	T.check( profile_lib.has_flag( q, FLAG ),
		"re-snapshotted profile still has the flag (was the reported defect)" )
	T.check( q.calendar ~= nil, "clone has a calendar table" )
	T.equal_int( q.calendar.year, 2026, "clone keeps calendar.year" )
	T.equal_int( q.calendar.month, 10, "clone keeps calendar.month" )
	T.equal_int( q.calendar.day, 22, "clone keeps calendar.day (was nil before the fix)" )

	-- The reported mutation attempts must still fail on the clone.
	local ok_day = pcall( function() q.calendar.day = 23 end )
	T.check( not ok_day, "clone calendar is immutable" )
	T.equal_int( q.calendar.day, 22, "calendar unchanged after a failed write" )

	local ok_flag = pcall( function() q.unlocked_flags[ FLAG ] = false end )
	T.check( not ok_flag, "clone flag map is immutable" )

	-- The source must be unaffected by anything the clone did.
	T.check( profile_lib.has_flag( p, FLAG ), "source profile still intact" )
	T.equal_int( p.calendar.day, 22, "source calendar still intact" )
end

T.describe("clone: by-value, not by-reference")
do
	local p = sample()
	local q = profile_lib.new( p )

	-- Distinct frozen proxies and distinct backing stores: mutating one can never
	-- be observed through the other.
	T.check( p.unlocked_flags ~= q.unlocked_flags, "flag maps are not the same table" )
	T.check( p.calendar ~= q.calendar, "calendar tables are not the same table" )
	T.check( profile_lib.unwrap( p.unlocked_flags ) ~= profile_lib.unwrap( q.unlocked_flags ),
		"flag backing stores are distinct" )
	T.check( profile_lib.unwrap( p.calendar ) ~= profile_lib.unwrap( q.calendar ),
		"calendar backing stores are distinct" )

	-- Same content, so identity must match exactly.
	T.equal( profile_lib.identity( p ), profile_lib.identity( q ),
		"a faithful clone has the same identity" )
	T.equal( q.id, p.id, "clone keeps the id" )
	T.equal( q.game_version, p.game_version, "clone keeps the game version" )
end

T.describe("clone: nested maps survive")
do
	-- A nested table inside the snapshot must be copied deeply, both when it is
	-- plain input and when it comes from an already-frozen source.
	local p = profile_lib.new( {
		id = "nested",
		unlocked_flags = { [ FLAG ] = true },
		calendar = { year = 2026, month = 10, day = 22 },
		persistent_flags = { biome_0_secret_unlocked = true },
	} )
	local q = profile_lib.new( p )
	local r = profile_lib.new( q ) -- double re-snapshot

	T.check( profile_lib.has_flag( r, FLAG ), "flag survives two re-snapshots" )
	T.check( profile_lib.has_persistent( r, "biome_0_secret_unlocked" ),
		"persistent flag survives two re-snapshots" )
	T.equal_int( r.calendar.year, 2026, "calendar survives two re-snapshots" )

	-- Entry counts must be right; an empty raw table would silently pass a
	-- "no false positives" check.
	local flags = profile_lib.flags( r.unlocked_flags )
	local n = 0
	for _ in pairs( flags ) do
		n = n + 1
	end
	T.equal_int( n, 1, "flag map has exactly the copied entry" )

	local persistent = profile_lib.flags( r.persistent_flags )
	local pn = 0
	for _ in pairs( persistent ) do
		pn = pn + 1
	end
	T.equal_int( pn, 1, "persistent map has exactly the copied entry" )

	-- flags() must be a plain, writable copy that does not alias the snapshot.
	flags[ FLAG ] = false
	T.check( profile_lib.has_flag( r, FLAG ),
		"mutating the flags() copy does not affect the snapshot" )
end

T.describe("clone: inherited diagnostics are preserved")
do
	-- A degraded snapshot carries warnings; cloning it must not lose them.
	-- A profile with no id produces the `missing_profile_id` warning, which is the
	-- one thing normalize() cannot regenerate from the already-defaulted clone.
	local p = profile_lib.new( { unlocked_flags = {} } )
	local p_codes = {}
	for _, w in ipairs( profile_lib.warnings( p ) ) do
		p_codes[ w.code ] = true
	end
	T.check( p_codes.missing_profile_id == true, "source carries missing_profile_id" )

	local q = profile_lib.new( p )
	local q_codes = {}
	for _, w in ipairs( profile_lib.warnings( q ) ) do
		q_codes[ w.code ] = ( q_codes[ w.code ] or 0 ) + 1
	end
	T.check( q_codes.missing_profile_id ~= nil,
		"cloning does not silently drop the inherited warning code" )
	T.equal_int( q_codes.missing_profile_id, 1,
		"the inherited warning is carried once, not duplicated" )
	T.equal( q.id, "unspecified", "the defaulted id survives the clone" )
end

T.describe("clone: identity distinguishes different snapshots")
do
	local a = profile_lib.new( {
		id = "x", unlocked_flags = { [ FLAG ] = true },
		calendar = { year = 2026, month = 10, day = 22 },
	} )
	local b = profile_lib.new( {
		id = "x", unlocked_flags = { [ FLAG ] = true },
		calendar = { year = 2026, month = 10, day = 23 },
	} )
	local c = profile_lib.new( {
		id = "x", unlocked_flags = { [ FLAG2 ] = true },
		calendar = { year = 2026, month = 10, day = 22 },
	} )

	T.check( profile_lib.identity( a ) ~= profile_lib.identity( b ),
		"a different calendar day changes the identity" )
	T.check( profile_lib.identity( a ) ~= profile_lib.identity( c ),
		"a different unlock set changes the identity" )
end

T.describe("clone: direct flag lookup stays Lua 5.1 compatible")
do
	-- The contract keeps `profile.unlocked_flags[flag]` working for plain reads
	-- through the proxy metamethod (no `__pairs` needed).
	local p = sample()
	T.check( p.unlocked_flags[ FLAG ] == true,
		"direct index read through the frozen proxy works" )
	T.check( p.unlocked_flags[ "card_unlocked_absent" ] == nil,
		"absent flag reads as nil through the proxy" )
	T.check( p.calendar.day == 22, "direct nested field read works" )

	-- Iteration must go through .flags/.list, which are the documented helpers.
	T.check( type( profile_lib.flags ) == "function", "flags() helper exists" )
	T.check( type( profile_lib.list ) == "function", "list() helper exists" )
	local n = 0
	for _ in pairs( profile_lib.flags( p.unlocked_flags ) ) do
		n = n + 1
	end
	T.equal_int( n, 2, "flags() exposes both entries for iteration" )
end

T.describe("clone: normalize() itself is idempotent on frozen input")
do
	-- normalize is the internal entry point new() uses; it must also accept a
	-- frozen profile, because callers may normalize before freezing.
	local p = sample()
	local r, errors = profile_lib.normalize( p )
	T.check( r ~= nil, "normalize accepts a frozen profile" )
	T.equal_int( #errors, 0, "normalizing a valid frozen profile reports no errors" )
	T.check( r.unlocked_flags[ FLAG ] == true, "normalized flags carry the entry" )
	T.equal_int( r.calendar.day, 22, "normalized calendar carries the day" )

	-- and it must be a plain (pre-freeze) table, not an alias of the proxy.
	T.check( r.unlocked_flags ~= p.unlocked_flags, "normalize returns a fresh table" )
	r.unlocked_flags[ FLAG ] = false
	T.check( profile_lib.has_flag( p, FLAG ), "normalize output does not alias the frozen source" )
end

T.describe("clone: bad input is still rejected")
do
	local bad, errors = profile_lib.new( {
		id = "bad",
		unlocked_flags = { [ FLAG ] = "yes" },
	} )
	T.check( #errors > 0, "a non-boolean flag is reported" )

	-- and an invalid frozen profile does not become valid by cloning
	local p = profile_lib.new( { id = "bad2", unlocked_flags = { [ FLAG ] = "yes" } } )
	local q, qerr = profile_lib.new( p )
	T.check( #qerr > 0, "cloning an invalid profile keeps reporting the error" )
end

T.describe("helpers tolerate non-table input")
do
	-- These helpers are called while validating untrusted input, so they must not
	-- raise on a wrong-typed field. (A refactor once made flags() call pairs() on
	-- a string here; this pins the safe behaviour.)
	local function count( t )
		local n = 0
		for _ in pairs( t ) do
			n = n + 1
		end
		return n
	end
	T.equal_int( count( profile_lib.flags( "not-a-table" ) ), 0,
		"flags() returns an empty table for a string" )
	T.equal_int( count( profile_lib.flags( nil ) ), 0, "flags() returns an empty table for nil" )
	T.equal_int( #profile_lib.list( "not-a-table" ), 0, "list() returns an empty array for a string" )
	T.equal_int( #profile_lib.list( nil ), 0, "list() returns an empty array for nil" )
	T.equal( profile_lib.unwrap( "x" ), "x", "unwrap passes non-tables through" )

	-- A wrongly-typed flag map is a reported error, not a crash.
	local p, errs = profile_lib.new( { id = "typed", unlocked_flags = "nope" } )
	T.check( p ~= nil, "a wrong-typed flag map still yields a profile" )
	T.check( #errs > 0, "and reports the type error" )
	local codes = {}
	for _, e in ipairs( errs ) do
		codes[ e.code ] = true
	end
	T.check( codes.bad_unlocked_flags == true, "the specific error code is bad_unlocked_flags" )
end
