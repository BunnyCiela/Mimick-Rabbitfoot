-- files/isf/core/report.lua
--
-- Structured score report (WORKER_CONTRACT.md "生成条件与报告", PRD section 5).
--
-- A report is the only thing providers are allowed to hand back. It carries
--   schema_version, rule_version, seed, profile_id,
--   coverage { status, complete, reasons, categories },
--   sections (per-category subtotals),
--   entries  (every individual award, with provenance),
--   totals   (score_units + exact display string),
--   errors / warnings.
--
-- Invariants enforced here:
--   * totals.score_units always equals the sum of entry.score_units; a mismatch
--     is an error, never silently reconciled;
--   * entry ids are unique, so a resource visited twice through different
--     traversal paths cannot be counted twice unnoticed;
--   * providers use integer base score_units (4 units = 1 point); rule2 final
--     reports explicitly allow binary fixed-precision decay within those units.
--
-- Lua 5.1 / LuaJIT compatible; no external dependencies.

local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
if ( type( units ) ~= "table" ) then
	error( "report: files/isf/core/units.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.COVERAGE_COMPLETE = "complete"
M.COVERAGE_PARTIAL = "partial"
M.COVERAGE_UNSUPPORTED = "unsupported"

local VALID_STATUS = {
	[ M.COVERAGE_COMPLETE ] = true,
	[ M.COVERAGE_PARTIAL ] = true,
	[ M.COVERAGE_UNSUPPORTED ] = true,
}

local Report = {}
Report.__index = Report

-- category, rule_id, biome, source_id, x, y, score_units, reason, plus optional
-- spell_id / spell_group / wand_id / chest_id / extra fields.
function Report:add( entry )
	if ( type( entry ) ~= "table" ) then
		error( "report:add expects a table entry" )
	end
	if ( type( entry.id ) ~= "string" or entry.id == "" ) then
		error( "report: entry needs a stable string id" )
	end
	if ( self.entry_ids[ entry.id ] ) then
		error( "report: duplicate entry id '" .. entry.id .. "' (a resource was counted twice)" )
	end
	if ( type( entry.rule_id ) ~= "string" or entry.rule_id == "" ) then
		error( "report: entry '" .. entry.id .. "' needs rule_id" )
	end
	if ( type( entry.category ) ~= "string" or entry.category == "" ) then
		error( "report: entry '" .. entry.id .. "' needs category" )
	end
	if ( type( entry.score_units ) ~= "number" or entry.score_units~=entry.score_units or entry.score_units==math.huge
      or (self.settled_scores and not units.is_score_units(entry.score_units))
      or (not self.settled_scores and entry.score_units ~= math.floor( entry.score_units )) ) then
		error( "report: entry '" .. entry.id .. "' has invalid score_units for its precision" )
	end
	if ( entry.score_units < 0 ) then
		error( "report: entry '" .. entry.id .. "' score_units must be non-negative" )
	end
	if ( type( entry.reason ) ~= "string" or entry.reason == "" ) then
		error( "report: entry '" .. entry.id .. "' needs a human-readable reason" )
	end

	self.entry_ids[ entry.id ] = true
	self.entries[ #self.entries + 1 ] = entry
	self.total_units = self.total_units + entry.score_units
	if self.settled_scores and not units.is_score_units(self.total_units) then error("report: settled score precision overflow") end

	local section = self.sections[ entry.category ]
	if ( section == nil ) then
		section = { category = entry.category, score_units = 0, entries = 0, rule_ids = {} }
		self.sections[ entry.category ] = section
	end
	section.score_units = section.score_units + entry.score_units
	section.entries = section.entries + 1
	if ( not section.rule_ids[ entry.rule_id ] ) then
		section.rule_ids[ entry.rule_id ] = true
	end
end

-- Coverage claims must be explicit. ISF-01 is a partial report by construction.
function Report:claim( category, status, reason )
	if ( not VALID_STATUS[ status ] ) then
		error( "report:claim: invalid coverage status " .. tostring( status ) )
	end
	if ( type( category ) ~= "string" or category == "" ) then
		error( "report:claim: category must be a non-empty string" )
	end
	self.coverage.categories[ category ] = { status = status, reason = reason or "" }
	if ( status ~= M.COVERAGE_COMPLETE ) then
		self.coverage.complete = false
		self.coverage.reasons[ #self.coverage.reasons + 1 ] = category .. ": " .. ( reason or status )
	end
end

function Report:error( code, message )
	self.errors[ #self.errors + 1 ] = { code = code, message = message }
end

function Report:warning( code, message )
	self.warnings[ #self.warnings + 1 ] = { code = code, message = message }
end

-- Finish the report. Validates the totals invariant and freezes the coverage
-- status: a report can only be `complete` when every category claimed complete
-- and no error occurred.
function Report:finish()
	local sum = 0
	for i = 1, #self.entries do
		sum = sum + self.entries[ i ].score_units
	end
	if ( sum ~= self.total_units ) then
		self.errors[ #self.errors + 1 ] = {
			code = "total_mismatch",
			message = "entry sum " .. tostring( sum ) .. " != accumulated total " .. tostring( self.total_units ),
		}
		self.total_units = sum
	end

	if ( #self.errors > 0 ) then
		self.coverage.complete = false
	end
	if ( self.coverage.complete ) then
		self.coverage.status = M.COVERAGE_COMPLETE
	else
		local any_unsupported = false
		for _, info in pairs( self.coverage.categories ) do
			if ( info.status == M.COVERAGE_UNSUPPORTED ) then
				any_unsupported = true
			end
		end
		if ( any_unsupported and next( self.coverage.categories ) ~= nil ) then
			-- A category that is fully unsupported keeps the report partial: the
			-- PRD forbids treating unsupported rules as zero-score completion.
			self.coverage.status = M.COVERAGE_PARTIAL
		else
			self.coverage.status = M.COVERAGE_PARTIAL
		end
	end

	-- Deterministic entry order: sort by x, then y, then id. Physical order makes
	-- reports comparable between runs and between implementations.
	table.sort( self.entries, function( a, b )
		local ax = tonumber( a.x ) or 0
		local bx = tonumber( b.x ) or 0
		if ( ax ~= bx ) then
			return ax < bx
		end
		local ay = tonumber( a.y ) or 0
		local by = tonumber( b.y ) or 0
		if ( ay ~= by ) then
			return ay < by
		end
		return a.id < b.id
	end )

	local sections = {}
	local names = {}
	for name in pairs( self.sections ) do
		names[ #names + 1 ] = name
	end
	table.sort( names )
	for _, name in ipairs( names ) do
		local section = self.sections[ name ]
		local rules = {}
		for rule in pairs( section.rule_ids ) do
			rules[ #rules + 1 ] = rule
		end
		table.sort( rules )
		sections[ #sections + 1 ] = {
			category = section.category,
			score_units = section.score_units,
			score = units.to_string( section.score_units ),
			entries = section.entries,
			rule_ids = rules,
		}
	end

	return {
		schema_version = M.SCHEMA_VERSION,
		rule_version = self.rule_version,
		seed = self.seed,
		profile_id = self.profile_id,
		profile_identity = self.profile_identity,
		coverage = {
			status = self.coverage.status,
			complete = self.coverage.complete == true,
			reasons = self.coverage.reasons,
			categories = self.coverage.categories,
			notes = self.notes,
		},
		totals = {
			score_units = self.total_units,
			score = units.to_string( self.total_units ),
		},
		sections = sections,
		entries = self.entries,
		errors = self.errors,
		warnings = self.warnings,
		meta = self.meta,
	}
end

-- new( options ): options = { seed, profile_id, profile_identity, rule_version,
--                             meta = {...}, notes = {...} }
function M.new( options )
	if ( type( options ) ~= "table" ) then
		error( "report.new expects an options table" )
	end
	local self = setmetatable( {}, Report )
	self.settled_scores=options.settled_scores==true
	self.rule_version = options.rule_version or M.RULE_VERSION
	self.seed = options.seed
	self.profile_id = options.profile_id
	self.profile_identity = options.profile_identity
	self.meta = options.meta or {}
	self.notes = options.notes or {}
	self.entries = {}
	self.entry_ids = {}
	self.sections = {}
	self.total_units = 0
	self.errors = {}
	self.warnings = {}
	self.coverage = {
		status = M.COVERAGE_PARTIAL,
		complete = false,
		reasons = {},
		categories = {},
	}
	return self
end

return M
