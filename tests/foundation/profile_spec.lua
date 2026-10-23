-- tests/foundation/profile_spec.lua
--
-- Generation-condition snapshot adapter (ISF-01 acceptance: same seed + same
-- snapshot reproduces; different unlock snapshots reproduce separately; reading
-- never modifies persistent progress).

local profile_lib = __isf_load("mods/interesting_seed_filter/files/isf/adapters/profile.lua")
local game_profile = __isf_load("mods/interesting_seed_filter/files/isf/adapters/game_profile.lua")
local spells = __isf_load("mods/interesting_seed_filter/files/isf/data/spells.lua")

T.describe("profile: required fields and defaults")
do
	local p = profile_lib.new( {
		id = "snap-1",
		game_version = "9dbd52ced019a643169a2db02f46c77f8766c6e5",
		unlocked_flags = { card_unlocked_nuke = true, card_unlocked_fish = false },
		persistent_flags = { biome_0_secret_unlocked = true },
		calendar = { year = 2026, month = 10, day = 21 },
	} )
	T.check( p ~= nil, "a complete snapshot builds" )
	T.equal( p.id, "snap-1", "id is preserved" )
	T.equal_int( p.schema_version, 1, "schema version recorded" )
	T.check( profile_lib.has_flag( p, "card_unlocked_nuke" ), "true flag reads as unlocked" )
	T.check( not profile_lib.has_flag( p, "card_unlocked_fish" ), "false flag reads as locked" )
	T.check( not profile_lib.has_flag( p, "card_unlocked_missing" ),
		"missing flag reads as locked (the game only sets flags that happened)" )
	T.check( profile_lib.has_persistent( p, "biome_0_secret_unlocked" ), "persistent marker reads" )

	local sparse = profile_lib.new( {} )
	T.check( sparse ~= nil, "an empty snapshot still builds" )
	T.equal( sparse.id, "unspecified", "missing id falls back to a named default" )
	local warned = false
	for _, w in ipairs( profile_lib.warnings( sparse ) ) do
		if ( w.code == "missing_profile_id" ) then
			warned = true
		end
	end
	T.check( warned, "missing id is warned about rather than silently invented" )
end

T.describe("profile: validation rejects malformed snapshots")
do
	local p, errors = profile_lib.new( {
		id = "bad",
		unlocked_flags = { card_unlocked_nuke = "yes" },
	} )
	T.check( #errors > 0, "a non-boolean flag value is an error" )

	local p2, errors2 = profile_lib.new( {
		id = "bad2",
		persistent_flags = "not-a-table",
	} )
	T.check( #errors2 > 0, "a non-table persistent_flags is an error" )
end

T.describe("profile: immutability")
do
	local p = profile_lib.new( {
		id = "snap-imm",
		unlocked_flags = { card_unlocked_nuke = true },
		calendar = { year = 2026 },
	} )

	local ok1 = pcall( function() p.id = "changed" end )
	T.check( not ok1, "overwriting an existing scalar field raises" )

	local ok2 = pcall( function() p.unlocked_flags.card_unlocked_nuke = false end )
	T.check( not ok2, "overwriting an existing flag raises (no silent snapshot drift)" )

	local ok3 = pcall( function() p.unlocked_flags.card_unlocked_new = true end )
	T.check( not ok3, "adding a flag raises" )

	local ok4 = pcall( function() p.calendar.year = 1999 end )
	T.check( not ok4, "nested snapshot tables are frozen too" )

	-- The backing store must be readable by module code, otherwise identity and
	-- describe() could not work.
	local backing = profile_lib.unwrap( p.unlocked_flags )
	local count = 0
	for _ in pairs( backing ) do
		count = count + 1
	end
	T.equal_int( count, 1, "unwrap exposes exactly the frozen entries for reading" )
	T.check( p.unlocked_flags.card_unlocked_nuke == true, "proxy still reads through" )
end

T.describe("profile: copying is by value")
do
	local raw = {
		id = "snap-copy",
		unlocked_flags = { card_unlocked_nuke = true },
	}
	local p = profile_lib.new( raw )
	raw.unlocked_flags.card_unlocked_nuke = false
	raw.unlocked_flags.card_unlocked_extra = true
	T.check( profile_lib.has_flag( p, "card_unlocked_nuke" ),
		"mutating the caller's table after construction does not change the snapshot" )
	T.check( not profile_lib.has_flag( p, "card_unlocked_extra" ),
		"new keys added to the caller's table do not leak into the snapshot" )
end

T.describe("profile: identity is stable and condition-sensitive")
do
	local function make( flags )
		return profile_lib.new( { id = "snap-id", game_version = "v1", unlocked_flags = flags } )
	end
	local a = make( { b = true, a = true } )
	local b = make( { a = true, b = true } )
	T.equal( profile_lib.identity( a ), profile_lib.identity( b ),
		"identity does not depend on table insertion order" )

	local c = make( { a = true } )
	T.check( profile_lib.identity( a ) ~= profile_lib.identity( c ),
		"identity changes when the unlock set changes" )

	local d = make( { a = true, b = true, unknown_extra = true } )
	T.check( profile_lib.identity( a ) ~= profile_lib.identity( d ),
		"identity changes when an extra flag is set" )
end

T.describe("profile: describe() is sorted and reproducible")
do
	local p = profile_lib.new( {
		id = "snap-desc",
		game_version = "v1",
		unlocked_flags = { zzz = true, aaa = true, mmm = false },
		persistent_flags = { p2 = true, p1 = true },
		calendar = { year = 2026, month = 10, day = 21, hour = 1, minute = 2, second = 3 },
	} )
	local d = profile_lib.describe( p )
	T.equal_int( #d.unlocked_flags, 2, "only true flags are listed" )
	T.equal( d.unlocked_flags[ 1 ], "aaa", "unlocked flags are sorted" )
	T.equal( d.unlocked_flags[ 2 ], "zzz", "unlocked flags are sorted" )
	T.equal( d.persistent_flags[ 1 ], "p1", "persistent flags are sorted" )
	T.equal_int( d.calendar.year, 2026, "calendar year preserved" )
	T.check( d.identity ~= nil and d.identity ~= "", "describe includes an identity" )
end

T.describe("game_profile: read-only bridge to the running game")
do
	-- A fake host that only implements the documented read functions. Any call to
	-- a write function on this table would be a missing-field error, which is the
	-- point: the adapter must not need them.
	local reads = {}
	local fake = {}
	local function reader( name, ... )
		return function( ... )
			reads[ #reads + 1 ] = name
			local out = { ... }
			return unpack( out )
		end
	end
	fake.HasFlagPersistent = function( flag )
		reads[ #reads + 1 ] = "HasFlagPersistent:" .. flag
		-- Pretend exactly two gating unlocks are set.
		return flag == "card_unlocked_duplicate" or flag == "card_unlocked_mestari"
	end
	fake.GameGetDateAndTimeUTC = function()
		reads[ #reads + 1 ] = "GameGetDateAndTimeUTC"
		return 2026, 10, 21, 12, 0, 0
	end
	fake.GameGetFrameNum = function()
		reads[ #reads + 1 ] = "GameGetFrameNum"
		return 42
	end
	fake.ModGetAPIVersion = function()
		reads[ #reads + 1 ] = "ModGetAPIVersion"
		return 12
	end

	local p, diag = game_profile.build( { api = fake, id = "live-test" } )
	T.check( p ~= nil, "a snapshot builds from a live-style host" )
	T.equal( p.id, "live-test", "explicit id is honoured" )
	T.equal( p.game_version, spells.GAME_VERSION_HASH, "game version comes from the extracted build hash" )
	T.check( profile_lib.has_flag( p, "card_unlocked_duplicate" ), "a set unlock is captured" )
	T.check( not profile_lib.has_flag( p, "card_unlocked_fish" ), "an unset unlock is captured as locked" )
	T.equal_int( p.calendar.year, 2026, "calendar is captured" )
	T.equal_int( p.calendar.month, 10, "calendar month captured" )

	-- Only read functions may be used.
	local write_names = {
		["SetWorldSeed"] = true, ["SetRandomSeed"] = true,
		["AddFlagPersistent"] = true, ["RemoveFlagPersistent"] = true,
		["GlobalsSetValue"] = true, ["GameAddFlagRun"] = true,
	}
	for _, name in ipairs( reads ) do
		local base = name:gsub( ":.*$", "" )
		T.check( not write_names[ base ], "adapter never calls the writer " .. tostring( base ) )
	end
	T.check( #reads > 0, "the adapter actually read from the host" )

	-- The PRD requires the seed to be an explicit input; the adapter must say it
	-- did not scrape one.
	local said_seed = false
	for _, note in ipairs( diag.notes ) do
		if ( note:find( "seed is supplied by the caller", 1, true ) ) then
			said_seed = true
		end
	end
	T.check( said_seed, "diagnostics state that the world seed is a caller input" )
	T.check( diag.runtime.api_version == 12, "runtime API version recorded" )
	T.check( diag.runtime.frame == 42, "runtime frame recorded" )
end

T.describe("game_profile: degraded hosts are flagged, not hidden")
do
	-- No HasFlagPersistent at all: every gated spell is treated as locked, and the
	-- diagnostics must say so plainly.
	local fake = {}
	fake.GameGetDateAndTimeUTC = function() return 2026, 10, 21, 0, 0, 0 end
	fake.GameGetFrameNum = function() return 1 end

	local p, diag = game_profile.build( { api = fake, id = "degraded" } )
	T.check( p ~= nil, "a snapshot still builds without the unlock reader" )
	local has_flag = false
	for i = 1, #spells.gated_flag_list do
		if ( profile_lib.has_flag( p, spells.gated_flag_list[ i ] ) ) then
			has_flag = true
		end
	end
	T.check( not has_flag, "without the reader, nothing is claimed unlocked" )

	local warned = false
	for _, note in ipairs( diag.notes ) do
		if ( note:find( "degraded", 1, true ) ) then
			warned = true
		end
	end
	T.check( warned, "degraded guest host is explicitly flagged as degraded" )
	T.check( #diag.missing_readers > 0, "missing required readers are listed" )
end

T.describe("game_profile: no api => no snapshot, with diagnostics")
do
	local p, diag = game_profile.build( { api = "not-a-table" } )
	T.check( p == nil, "no host means no snapshot rather than a fabricated one" )
	T.check( #diag.notes > 0, "diagnostics explain why" )
end

T.describe("game_profile: daily runs are called out")
do
	local fake = {}
	fake.HasFlagPersistent = function() return false end
	fake.GameGetDateAndTimeUTC = function() return 2026, 10, 21, 0, 0, 0 end
	fake.GameGetFrameNum = function() return 1 end
	fake.GameIsDailyRun = function() return true end

	local p, diag = game_profile.build( { api = fake, id = "daily" } )
	T.check( p ~= nil, "snapshot builds" )
	local called_out = false
	for _, note in ipairs( diag.notes ) do
		if ( note:find( "daily run", 1, true ) ) then
			called_out = true
		end
	end
	T.check( called_out, "daily-run unlock-all caveat is reported" )
end
