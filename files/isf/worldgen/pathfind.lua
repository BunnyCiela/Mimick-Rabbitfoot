-- files/isf/worldgen/pathfind.lua
--
-- Port of Noita's minimum-corridor search over a generated Wang tile buffer, and
-- of the path-start selection that feeds it.
--
-- Substantial reuse: noita-telescope, js/pathfinding.js
--   MIT License, Copyright (c) 2026 Lymm
--
-- Why this matters for prediction: the game guarantees a walkable corridor from
-- the surface down through each biome. If a Wang roll produces terrain with no
-- such corridor, the game regenerates the biome with an incremented reroll
-- counter, so the ACCEPTED tile layer depends on this search. Skipping it would
-- predict a different map than the game builds.
--
-- Standalone Lua 5.1: no FFI, no external process.

local M = {}

local CHUNK_SIZE = 512
local TILE_SIZE = 10

-- World x span of the corridor the main path starts in (non-Mines biomes).
local PATH_FIND_WORLD_POS_MIN_X = 159
local PATH_FIND_WORLD_POS_MAX_X = 223

-- Biomes built from the mines template start at a fixed tile instead.
local MINES_TEMPLATE = "coalmine.png"
local MINES_START_X = 142
local MINES_START_LEN = 12

local WORLD_CHUNK_CENTER_X = 35

function M.uses_mines_template( wang_file )
	if ( wang_file == nil ) then
		return false
	end
	-- Equivalent to JS endsWith(MINES_TEMPLATE).
	return string.sub( wang_file, -#MINES_TEMPLATE ) == MINES_TEMPLATE
end

-- getPathStartSegment( bbox, width, height, wang_file, is_ng_plus )
-- Returns { x = n, len = n } or nil.
function M.get_path_start_segment( bbox, width, height, wang_file, is_ng_plus )
	if ( M.uses_mines_template( wang_file ) ) then
		return { x = MINES_START_X, len = MINES_START_LEN }
	end

	local seg_len = math.floor( ( PATH_FIND_WORLD_POS_MAX_X - PATH_FIND_WORLD_POS_MIN_X ) / TILE_SIZE )
	local world_center = is_ng_plus and 32 or WORLD_CHUNK_CENTER_X
	local region_x = ( bbox[ 1 ] - world_center ) * CHUNK_SIZE
	local start_x = math.floor( ( PATH_FIND_WORLD_POS_MIN_X - region_x ) / TILE_SIZE )
	if ( start_x < 0 or start_x >= width ) then
		return nil
	end
	if ( start_x + seg_len < 0 or start_x + seg_len >= width ) then
		return nil
	end
	if ( height < 7 ) then
		return nil
	end
	return { x = start_x, len = math.floor( seg_len / TILE_SIZE ) }
end

-- A path tile may run through air (0,0,0) or coffee (0xc0,0xff,0xee).
--
-- `pixels` may be either a byte string of RGB triples or a 0-based byte table
-- whose index 1 holds pixel 0's red channel (mines_map keeps the table form so
-- stages can mutate it in place). `idx` is a 0-based byte offset.
local function byte_at( pixels, idx )
	if ( type( pixels ) == "string" ) then
		return pixels:byte( idx + 1 )
	end
	return pixels[ idx + 1 ] or 0
end

local function is_open( pixels, byte_index )
	if type(pixels)=="table"and pixels.packed_rgb then
		local color=pixels[byte_index/3+1]
		return color==0 or color==0xc0ffee
	end
	return ( byte_at( pixels, byte_index ) == 0
			and byte_at( pixels, byte_index + 1 ) == 0
			and byte_at( pixels, byte_index + 2 ) == 0 )
		or ( byte_at( pixels, byte_index ) == 0xc0
			and byte_at( pixels, byte_index + 1 ) == 0xff
			and byte_at( pixels, byte_index + 2 ) == 0xee )
end

-- Maximal runs of open tiles along one row, returned as { {x=, len=}, ... }.
local function find_sequences( pixels, width, row_y )
	local seqs = {}
	local start = nil
	local row_offset = row_y * width

	for x = 0, width - 1 do
		if is_open( pixels, ( row_offset + x ) * 3 ) then
			if ( start == nil ) then
				start = x
			end
		else
			if ( start ~= nil ) then
				seqs[ #seqs + 1 ] = { x = start, len = x - start }
				start = nil
			end
		end
	end
	if ( start ~= nil ) then
		seqs[ #seqs + 1 ] = { x = start, len = width - start }
	end
	return seqs
end

local function midpoint( seq )
	return seq.x + math.floor( seq.len / 2 )
end

-- findMinPath( pixels, width, height, start_segment ) -> array of {x,y} | nil
--
-- Breadth-first search from the forced start segment down to an opening on the
-- bottom row. Returns the reconstructed path in start-to-end order.
function M.find_min_path( pixels, width, height, start_segment )
	local start_y = 4
	local top_sequences
	if ( start_segment ~= nil ) then
		top_sequences = { start_segment }
	else
		top_sequences = find_sequences( pixels, width, start_y )
	end
	if ( #top_sequences == 0 ) then
		return nil
	end

	local bottom_sequences = find_sequences( pixels, width, height - 1 )
	if ( #bottom_sequences == 0 ) then
		return nil
	end

	-- Neighbour order matters: it fixes tie-breaking, so BFS must expand in the
	-- same order as upstream (down, left, right, up).
	local directions = { { 0, 1 }, { -1, 0 }, { 1, 0 }, { 0, -1 } }

	for s = 1, #top_sequences do
		local start_seq = top_sequences[ s ]
		local start_x = midpoint( start_seq )
		if ( start_x >= 0 and start_x < width ) then
			local visited = {}
			local parents = {}
			-- Flat FIFO queue of x,y pairs; head index avoids O(n^2) shifting.
			local queue = { start_x, start_y }
			local head = 1

			local start_idx = start_y * width + start_x
			visited[ start_idx ] = true
			parents[ start_idx ] = -2

			local max_y = start_y

			while ( head <= #queue ) do
				local cx = queue[ head ]
				local cy = queue[ head + 1 ]
				head = head + 2
				if ( cy > max_y ) then
					max_y = cy
				end

				for d = 1, 4 do
					local nx = cx + directions[ d ][ 1 ]
					local ny = cy + directions[ d ][ 2 ]
					if ( nx >= 0 and nx < width and ny > 3 and ny < height ) then
						local n_idx = ny * width + nx
						if ( visited[ n_idx ] == nil and is_open( pixels, n_idx * 3 ) ) then
							visited[ n_idx ] = true
							parents[ n_idx ] = cy * width + cx
							queue[ #queue + 1 ] = nx
							queue[ #queue + 1 ] = ny
						end
					end
				end
			end

			-- The path only counts if it reached an opening on the bottom row.
			if ( max_y >= height - 1 ) then
				local end_idx = nil
				for e = 1, #bottom_sequences do
					local end_x = midpoint( bottom_sequences[ e ] )
					if ( end_x >= 0 and end_x < width
						and visited[ ( height - 1 ) * width + end_x ] ~= nil ) then
						end_idx = ( height - 1 ) * width + end_x
						break
					end
				end

				if ( end_idx ~= nil ) then
					local path = {}
					local curr = end_idx
					while ( curr ~= -2 and curr ~= nil ) do
						-- Bitwise-free integer division: both operands are
						-- non-negative here, so floor is exact.
						local py = math.floor( curr / width )
						local px = curr - py * width
						path[ #path + 1 ] = { x = px, y = py }
						local parent = parents[ curr ]
						if ( parent == -2 or parent == nil ) then
							break
						end
						curr = parent
					end
					-- Reverse into start-to-end order.
					local out = {}
					for i = 1, #path do
						out[ i ] = path[ #path - i + 1 ]
					end
					return out
				end
			end
		end
	end

	return nil
end

-- Resource discovery needs acceptance only, not a particular shortest path.
-- Reuse bounded-by-largest-input scratch tables; stamps avoid clearing them on
-- every reroll. Sequential Lua calls own this workspace (no yielding here).
local seen, targets, stack, generation = {}, {}, {}, 0
function M.has_path(pixels, width, height, start_segment)
	if generation >= 2147483647 then seen,targets,generation={},{},0 end
	local bottoms=find_sequences(pixels,width,height-1)
	if #bottoms==0 then return false end
	generation=generation+1
	local target_stamp=generation
	for _,seq in ipairs(bottoms)do targets[(height-1)*width+midpoint(seq)]=target_stamp end
	local tops=start_segment and {start_segment}or find_sequences(pixels,width,4)
	local packed=type(pixels)=="table"and pixels.packed_rgb
	for _,seq in ipairs(tops)do
		local x=midpoint(seq)
		if x>=0 and x<width then
			generation=generation+1
			local stamp=generation
			local first=4*width+x
			local tail=1;stack[1]=first;seen[first]=stamp
			while tail>0 do
				local idx=stack[tail];tail=tail-1
				if targets[idx]==target_stamp then return true end
				local cx=idx%width
				-- Stack order prefers down. Reachability, not traversal order, is
				-- the contract; endpoints remain the original bottom midpoints.
				for d=1,4 do
					local n
					if d==1 then if idx>=5*width then n=idx-width end
					elseif d==2 then if cx<width-1 then n=idx+1 end
					elseif d==3 then if cx>0 then n=idx-1 end
					else n=idx+width end
					if n and n>=4*width and n<height*width and seen[n]~=stamp then
						local open
						if packed then local color=pixels[n+1];open=color==0 or color==0xc0ffee
						else open=is_open(pixels,n*3)end
						if open then seen[n]=stamp;tail=tail+1;stack[tail]=n end
					end
				end
			end
		end
	end
	return false
end

return M
