-- files/isf/core/serialize.lua
--
-- Deterministic text renderings of a report, for saving and re-checking
-- (ISF-01 acceptance: "report can be saved and re-checked").
--
-- Two forms are provided:
--   * render_text(report)  -- human-readable, stable field order
--   * render_json(report)  -- strict JSON, stable key order, no NaN/inf
--
-- Determinism matters more than prettiness: two runs of the same seed/profile
-- must produce byte-identical output, so nothing here iterates a hash table
-- without sorting first.
--
-- Lua 5.1 / LuaJIT compatible; no external dependencies.

local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
if ( type( units ) ~= "table" ) then
	error( "serialize: files/isf/core/units.lua did not return a table" )
end

local M = {}

M.FORMAT_VERSION = 1

--------------------------------------------------------------------------------
-- JSON
--------------------------------------------------------------------------------

local function json_escape( s )
	s = tostring( s )
	s = s:gsub( "\\", "\\\\" )
	s = s:gsub( '"', '\\"' )
	s = s:gsub( "\n", "\\n" )
	s = s:gsub( "\r", "\\r" )
	s = s:gsub( "\t", "\\t" )
	s = s:gsub( "([%z\1-\31])", function( c )
		return string.format( "\\u%04x", string.byte( c ) )
	end )
	return s
end

local function is_array( t )
	local n = 0
	for k in pairs( t ) do
		if ( type( k ) ~= "number" ) then
			return false
		end
		n = n + 1
	end
	if ( n == 0 ) then
		return true -- empty table serializes as []
	end
	for i = 1, n do
		if ( t[ i ] == nil ) then
			return false
		end
	end
	return true
end

local function json_value( value, indent, seen )
	local tv = type( value )
	if ( tv == "nil" ) then
		return "null"
	elseif ( tv == "boolean" ) then
		return value and "true" or "false"
	elseif ( tv == "number" ) then
		if ( value ~= value or value == math.huge or value == -math.huge ) then
			return "null"
		end
		if ( value == math.floor( value ) and math.abs( value ) < 1e15 ) then
			return string.format( "%d", value )
		end
		-- Old Windows CRT pads exponents to three digits (e-005), while
		-- newer LuaJIT formatters use two (e-05). Canonical JSON must agree.
		local number = string.format( "%.17g", value )
		return ( number:gsub( "([eE][+-])0+(%d+)", "%1%2" ) )
	elseif ( tv == "string" ) then
		return '"' .. json_escape( value ) .. '"'
	elseif ( tv ~= "table" ) then
		return '"<' .. json_escape( tv ) .. '>"'
	end

	if ( seen[ value ] ) then
		return '"<cycle>"'
	end
	seen[ value ] = true

	local pad = string.rep( "  ", indent + 1 )
	local close_pad = string.rep( "  ", indent )
	local out

	if ( is_array( value ) ) then
		if ( #value == 0 ) then
			out = "[]"
		else
			local parts = {}
			for i = 1, #value do
				parts[ #parts + 1 ] = pad .. json_value( value[ i ], indent + 1, seen )
			end
			out = "[\n" .. table.concat( parts, ",\n" ) .. "\n" .. close_pad .. "]"
		end
	else
		local keys = {}
		for k in pairs( value ) do
			keys[ #keys + 1 ] = tostring( k )
		end
		table.sort( keys )
		if ( #keys == 0 ) then
			out = "{}"
		else
			local parts = {}
			for _, key in ipairs( keys ) do
				local v = value[ key ]
				if ( v == nil ) then
					-- key was not a string; re-resolve through pairs
					for k2, v2 in pairs( value ) do
						if ( tostring( k2 ) == key ) then
							v = v2
							break
						end
					end
				end
				parts[ #parts + 1 ] = pad .. '"' .. json_escape( key ) .. '": '
					.. json_value( v, indent + 1, seen )
			end
			out = "{\n" .. table.concat( parts, ",\n" ) .. "\n" .. close_pad .. "}"
		end
	end

	seen[ value ] = nil
	return out
end

function M.render_json( report )
	-- `timing_ms` is wall-clock diagnostics and would break byte-identical
	-- output for the same seed/profile, so it is excluded from the saved form.
	-- Callers that want it read report.timing_ms directly.
	local copy = {}
	for k, v in pairs( report ) do
		if ( k ~= "timing_ms" ) then
			copy[ k ] = v
		end
	end
	return json_value( copy, 0, {} ) .. "\n"
end

--------------------------------------------------------------------------------
-- Human-readable text
--------------------------------------------------------------------------------

local function fmt_coord( x, y )
	local function one( v )
		if ( type( v ) ~= "number" ) then
			return tostring( v )
		end
		if ( v == math.floor( v ) ) then
			return string.format( "%d", v )
		end
		return string.format( "%.4f", v )
	end
	return "(" .. one( x ) .. ", " .. one( y ) .. ")"
end

function M.render_text( report )
	local out = {}
	local function line( s )
		out[ #out + 1 ] = s or ""
	end

	line( "ISF seed report" )
	line( "===============" )
	line( "seed            : " .. tostring( report.seed ) )
	line( "profile_id      : " .. tostring( report.profile_id ) )
	line( "profile_identity: " .. tostring( report.profile_identity ) )
	line( "rule_version    : " .. tostring( report.rule_version ) )
	line( "schema_version  : " .. tostring( report.schema_version ) )
	line( "coverage        : " .. tostring( report.coverage.status )
		.. ( report.coverage.complete and " (complete)" or " (PARTIAL - not a full seed score)" ) )
	for _, reason in ipairs( report.coverage.reasons or {} ) do
		line( "  - " .. tostring( reason ) )
	end

	line()
	line( "Totals" )
	line( "------" )
	line( "score: " .. tostring( report.totals.score ) .. " points ("
		.. tostring( report.totals.score_units ) .. " score_units)" )

	for _, section in ipairs( report.sections or {} ) do
		line( "  " .. section.category .. ": " .. section.score
			.. " (" .. tostring( section.entries ) .. " entries; rules "
			.. table.concat( section.rule_ids, "," ) .. ")" )
	end

	-- Per-region subtotals (ISF-12 multi-region report). Derived from the merged
	-- entries, so these always add up to the total above.
	local details = report.details
	if ( type( details ) == "table" and type( details.by_region ) == "table"
		and #details.by_region > 0 ) then
		line()
		line( "By region" )
		line( "---------" )
		for _, row in ipairs( details.by_region ) do
			line( "  " .. tostring( row.region ) .. ": " .. tostring( row.score )
				.. " (" .. tostring( row.entries ) .. " entries)" )
		end
	end

	-- Coverage per required category, with the owning provider, so a reader can
	-- see WHICH rule is incomplete rather than only that the report is partial.
	if ( type( details ) == "table" and type( details.coverage_rows ) == "table" ) then
		line()
		line( "Coverage by category" )
		line( "--------------------" )
		for _, row in ipairs( details.coverage_rows ) do
			line( string.format( "  %-11s %-34s %s",
				tostring( row.status ), tostring( row.label or row.category ),
				row.owner and ( "(" .. tostring( row.owner ) .. ")" ) or "(no provider)" ) )
		end
	end

	-- Which regions were actually enumerated, and which could not be.
	if ( type( details ) == "table" and type( details.regions ) == "table" ) then
		line()
		line( "Region discovery" )
		line( "----------------" )
		for _, row in ipairs( details.regions ) do
			if ( row.discovered ) then
				line( string.format( "  %-16s ok: %s record(s), %s scene marker(s)",
					tostring( row.name ), tostring( row.records ),
					tostring( row.scene_markers ) ) )
			else
				line( string.format( "  %-16s NOT discovered: %s",
					tostring( row.name ), tostring( row.reason ) ) )
			end
		end
	end

	-- Missing capabilities, by name. Never inferred from an absent score.
	if ( type( details ) == "table" and type( details.missing_capabilities ) == "table"
		and #details.missing_capabilities > 0 ) then
		line()
		line( "Known missing capabilities" )
		line( "--------------------------" )
		for _, cap in ipairs( details.missing_capabilities ) do
			line( "  " .. tostring( cap.capability ) .. ": " .. tostring( cap.reason ) )
		end
	end

	line()
	line( "Entries" )
	line( "-------" )
	if ( #( report.entries or {} ) == 0 ) then
		line( "  (no scoring resources)" )
	end
	for _, entry in ipairs( report.entries or {} ) do
		-- Name the most specific identifier available for this award.
		local label = entry.spell_id or entry.always_cast or entry.perk_id
			or entry.source_id or ""
		line( string.format(
			"  [%s] %s %s  +%s  %s",
			tostring( entry.rule_id ),
			tostring( entry.category ),
			fmt_coord( entry.x, entry.y ),
			units.to_string( entry.score_units ),
			tostring( label )
		) )
		line( "      id=" .. tostring( entry.id ) .. " reason=" .. tostring( entry.reason ) )
	end

	if ( report.errors and #report.errors > 0 ) then
		line()
		line( "Errors" )
		line( "------" )
		for _, err in ipairs( report.errors ) do
			line( "  " .. tostring( err.code ) .. ": " .. tostring( err.message ) )
		end
	end
	if ( report.warnings and #report.warnings > 0 ) then
		line()
		line( "Warnings" )
		line( "--------" )
		for _, warn in ipairs( report.warnings ) do
			line( "  " .. tostring( warn.code ) .. ": " .. tostring( warn.message ) )
		end
	end

	if ( report.details ) then
		-- Accept either a single-provider detail payload (`.summary` / `.shops`)
		-- or the aggregate form (`.providers`, each with its own detail payload).
		local payloads = {}
		if ( report.details.providers ~= nil ) then
			for _, p in ipairs( report.details.providers ) do
				if ( p.details ~= nil ) then
					payloads[ #payloads + 1 ] = { provider = p.provider, details = p.details }
				end
			end
		elseif ( report.details.summary ~= nil ) then
			payloads[ 1 ] = { provider = report.meta and report.meta.provider or "provider",
				details = report.details }
		end

		for _, payload in ipairs( payloads ) do
			local details = payload.details
			line()
			line( "Holy Mountain shops (" .. tostring( payload.provider ) .. ")" )
			line( "-------------------" )
			if ( details.summary ) then
				local s = details.summary
				line( string.format(
					"  mountains=%s spell_shops=%s wand_shops=%s scored_cards=%s unresolved=%s",
					tostring( s.holy_mountains ),
					tostring( s.spell_shops ),
					tostring( s.wand_shops ),
					tostring( s.scored_cards ),
					tostring( s.unresolved_slots )
				) )
			end
			if ( details.pool ) then
				line( string.format(
					"  spell pool: %s cards available, %s gated cards excluded",
					tostring( details.pool.included ),
					tostring( details.pool.excluded_count )
				) )
			end
			for _, shop in ipairs( details.shops or {} ) do
				line( string.format(
					"  HM%d %s shop at %s sale_slot=%s kind_roll=%s",
					shop.temple_index,
					shop.kind == "spell" and "spell" or "wand",
					fmt_coord( shop.x, shop.y ),
					tostring( shop.sale_item ),
					tostring( shop.kind_roll )
				) )
				for _, slot in ipairs( shop.slots or {} ) do
					-- Spell shops expose row/seeded_x/level; wand shops expose
					-- wand_type/gen_x plus an optional generated wand. Render
					-- whichever shape this provider produced.
					if ( slot.wand_type ~= nil ) then
						local wand = slot.wand
						local ac = "-"
						if ( wand ~= nil and wand.always_casts ~= nil and #wand.always_casts > 0 ) then
							ac = tostring( wand.always_casts[ 1 ] )
						end
						line( string.format(
							"    wand[%d] %s %s roll=%s ac=%s cards=%s%s",
							slot.slot,
							tostring( slot.wand_type ),
							fmt_coord( slot.gen_x, slot.gen_y ),
							tostring( slot.roll ),
							ac,
							wand ~= nil and tostring( #( wand.cards or {} ) ) or "?",
							slot.is_sale and " SALE" or ""
						) )
					else
						line( string.format(
							"    %s[%d] %s %s lvl=%s%s",
							tostring( slot.row or "?" ),
							slot.slot or 0,
							fmt_coord( slot.seeded_x or slot.x, slot.y ),
							tostring( slot.spell_id or "<unresolved>" ),
							tostring( slot.level or "?" ),
							slot.is_sale and " SALE" or ""
						) )
					end
				end
				if ( shop.kind == "wand" and #( shop.slots or {} ) == 0 ) then
					line( "    (wand shop contents are not scored by the spell provider; "
						.. "see the sold-wands provider)" )
				end
			end
		end
	end

	-- NOTE: `report.timing_ms` is deliberately NOT rendered. It is wall-clock
	-- diagnostics, so printing it would make two runs of the same seed/profile
	-- produce different text and defeat the reproducibility check. Callers that
	-- want it read `report.timing_ms` directly.

	return table.concat( out, "\n" ) .. "\n"
end

return M
