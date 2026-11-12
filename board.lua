-- ---------------------------------------------------------------------------
-- board.lua — Guide & Explorer: a maze seen from two readers. Pure Lua.
--
-- Both readers build the same maze from the game code (common/duo.lua).
--   * The guide sees the whole map: walls, landmarks, the key and the exit,
--     but not where the explorer is.
--   * The explorer sees only the cells around them, and walks.
-- The explorer describes what they see ("a wall to the north, a white
-- square to my east"); the guide works out where they are and leads them to
-- the key, then to the exit. The explorer's reader counts the steps.
--
-- Cells are (r, c), 1-based. Walls: wall_e[r][c] between (r, c) and
-- (r, c + 1), wall_s[r][c] between (r, c) and (r + 1, c).
-- ---------------------------------------------------------------------------

local Duo = require("duo")

local Board = {}
Board.__index = Board

--   n          maze side
--   view       how far the explorer sees (1 = the 3×3 around them)
--   landmarks  how many cells carry a symbol
--   braid      share of dead ends opened into loops (several routes)
Board.LEVELS = {
    { id = "easy",   n = 7,  view = 2, landmarks = 10, braid = 0.5 },
    { id = "medium", n = 9,  view = 1, landmarks = 14, braid = 0.35 },
    { id = "hard",   n = 11, view = 1, landmarks = 14, braid = 0.25 },
}

Board.DIRS = {
    n = { -1, 0 }, s = { 1, 0 }, w = { 0, -1 }, e = { 0, 1 },
}
Board.DIR_ORDER = { "n", "e", "s", "w" }

-- Landmark symbols: shape index 1..7, filled or not (as in shapes.lua).
Board.SHAPES = { "circle", "square", "triangle_up", "triangle_down", "diamond", "plus", "cross" }

-- ---------------------------------------------------------------------------
-- The maze
-- ---------------------------------------------------------------------------

local function newGrid(n, v)
    local g = {}
    for r = 1, n do
        g[r] = {}
        for c = 1, n do g[r][c] = v end
    end
    return g
end

-- Is there a wall on side d of (r, c)? The outer border is a wall.
function Board.wall(m, r, c, d)
    local n = m.n
    if d == "e" then return c == n or m.wall_e[r][c] end
    if d == "w" then return c == 1 or m.wall_e[r][c - 1] end
    if d == "s" then return r == n or m.wall_s[r][c] end
    return r == 1 or m.wall_s[r - 1][c]
end

local function setWall(m, r, c, d, v)
    if d == "e" then m.wall_e[r][c] = v
    elseif d == "w" then m.wall_e[r][c - 1] = v
    elseif d == "s" then m.wall_s[r][c] = v
    else m.wall_s[r - 1][c] = v end
end

local function inside(n, r, c)
    return r >= 1 and r <= n and c >= 1 and c <= n
end

-- Steps from (r, c) to every cell.
function Board.distances(m, r, c)
    local dist = newGrid(m.n, false)
    dist[r][c] = 0
    local queue, head = { { r, c } }, 1
    while head <= #queue do
        local p = queue[head]
        head = head + 1
        for _, d in ipairs(Board.DIR_ORDER) do
            if not Board.wall(m, p[1], p[2], d) then
                local rr, cc = p[1] + Board.DIRS[d][1], p[2] + Board.DIRS[d][2]
                if dist[rr][cc] == false then
                    dist[rr][cc] = dist[p[1]][p[2]] + 1
                    queue[#queue + 1] = { rr, cc }
                end
            end
        end
    end
    return dist
end

local function openSides(m, r, c)
    local k = 0
    for _, d in ipairs(Board.DIR_ORDER) do
        if not Board.wall(m, r, c, d) then k = k + 1 end
    end
    return k
end

-- The maze for (seed, level): walls, landmarks, key, exit and the
-- explorer's start. Every draw comes from `rng`, in a fixed order.
function Board.generate(seed, level)
    local lvl = Board.LEVELS[level] or Board.LEVELS[1]
    local rng = Duo.rng(seed, "mazeguide")
    local n = lvl.n
    local m = { n = n, wall_e = newGrid(n, true), wall_s = newGrid(n, true) }

    -- A perfect maze by depth-first carving.
    local seen = newGrid(n, false)
    local stack = { { rng:random(n), rng:random(n) } }
    seen[stack[1][1]][stack[1][2]] = true
    while #stack > 0 do
        local p = stack[#stack]
        local options = {}
        for _, d in ipairs(Board.DIR_ORDER) do
            local rr, cc = p[1] + Board.DIRS[d][1], p[2] + Board.DIRS[d][2]
            if inside(n, rr, cc) and not seen[rr][cc] then options[#options + 1] = d end
        end
        if #options == 0 then
            stack[#stack] = nil
        else
            local d = rng:pick(options)
            setWall(m, p[1], p[2], d, false)
            local rr, cc = p[1] + Board.DIRS[d][1], p[2] + Board.DIRS[d][2]
            seen[rr][cc] = true
            stack[#stack + 1] = { rr, cc }
        end
    end

    -- Open some dead ends into loops, so there is more than one way and a
    -- wrong turn is not always a long way back.
    for r = 1, n do
        for c = 1, n do
            if openSides(m, r, c) == 1 and rng:random() < lvl.braid then
                local options = {}
                for _, d in ipairs(Board.DIR_ORDER) do
                    local rr, cc = r + Board.DIRS[d][1], c + Board.DIRS[d][2]
                    if inside(n, rr, cc) and Board.wall(m, r, c, d) then options[#options + 1] = d end
                end
                if #options > 0 then setWall(m, r, c, rng:pick(options), false) end
            end
        end
    end

    -- Landmarks on distinct cells, each symbol used once.
    local cells = {}
    for r = 1, n do
        for c = 1, n do cells[#cells + 1] = { r, c } end
    end
    rng:shuffle(cells)
    local symbols = {}
    for s = 1, 14 do symbols[s] = s end
    rng:shuffle(symbols)
    m.landmark = newGrid(n, false)
    local k = 0
    for i = 1, lvl.landmarks do
        k = k + 1
        m.landmark[cells[k][1]][cells[k][2]] = symbols[i]
    end

    -- Key and exit on plain cells, the exit on the border, far from the key.
    k = k + 1
    m.key = { cells[k][1], cells[k][2] }
    local dkey = Board.distances(m, m.key[1], m.key[2])
    local best
    for j = k + 1, #cells do
        local r, c = cells[j][1], cells[j][2]
        local border = r == 1 or r == n or c == 1 or c == n
        if border and (not best or dkey[r][c] > dkey[best[1]][best[2]]) then best = { r, c } end
    end
    m.exit = best
    -- Start: a plain cell at least about n steps from the key (the first
    -- such cell in the shuffled order).
    local far = math.floor(n * 0.9)
    for j = k + 1, #cells do
        local r, c = cells[j][1], cells[j][2]
        if not (r == best[1] and c == best[2]) and not m.landmark[r][c] and dkey[r][c] >= far then
            m.start = { r, c }
            break
        end
    end
    m.start = m.start or { cells[#cells][1], cells[#cells][2] }
    local dexit = Board.distances(m, m.exit[1], m.exit[2])
    m.par = dkey[m.start[1]][m.start[2]] + dexit[m.key[1]][m.key[2]]
    return m
end

-- ---------------------------------------------------------------------------
-- A game on one reader
-- ---------------------------------------------------------------------------

-- o: seed, level, role ("guide" | "explorer"), code, and saved progress.
function Board.new(o)
    local self = setmetatable({}, Board)
    self.seed  = o.seed or 0
    self.level = Board.LEVELS[o.level] and o.level or 1
    self.role  = o.role == "explorer" and "explorer" or "guide"
    self.code  = o.code
    self.maze  = Board.generate(self.seed, self.level)
    self.view  = Board.LEVELS[self.level].view
    local m = self.maze
    self.pos     = o.pos or { m.start[1], m.start[2] }
    self.has_key = o.has_key == true
    self.moves   = o.moves or 0
    self.done    = o.done == true
    self.marks   = o.marks or {}   -- guide's pencil marks, "r,c" -> true
    return self
end

function Board:serialize()
    return {
        seed = self.seed, level = self.level, role = self.role, code = self.code,
        pos = self.pos, has_key = self.has_key, moves = self.moves, done = self.done,
        marks = self.marks,
    }
end

function Board.load(t)
    if type(t) ~= "table" or type(t.seed) ~= "number" or not Board.LEVELS[t.level] then return nil end
    local b = Board.new(t)
    local n = b.maze.n
    if type(b.pos) ~= "table" or not inside(n, b.pos[1] or 0, b.pos[2] or 0) then return nil end
    return b
end

function Board:isOver()
    return self.done
end

-- The explorer steps in direction d: "wall", "moved", "key" (picked it up),
-- "locked" (at the exit without the key), "out" (left with the key: won).
function Board:move(d)
    if self.done or not Board.DIRS[d] then return nil end
    local m, r, c = self.maze, self.pos[1], self.pos[2]
    if Board.wall(m, r, c, d) then return "wall" end
    r, c = r + Board.DIRS[d][1], c + Board.DIRS[d][2]
    self.pos = { r, c }
    self.moves = self.moves + 1
    if not self.has_key and r == m.key[1] and c == m.key[2] then
        self.has_key = true
        return "key"
    end
    if r == m.exit[1] and c == m.exit[2] then
        if not self.has_key then return "locked" end
        self.done = true
        return "out"
    end
    return "moved"
end

-- Direction from the explorer to an adjacent cell, or nil.
function Board:dirTo(r, c)
    for _, d in ipairs(Board.DIR_ORDER) do
        if self.pos[1] + Board.DIRS[d][1] == r and self.pos[2] + Board.DIRS[d][2] == c then return d end
    end
end

function Board:toggleMark(r, c)
    local key = r .. "," .. c
    self.marks[key] = not self.marks[key] or nil
end

function Board:isMarked(r, c)
    return self.marks[r .. "," .. c] == true
end

function Board:clearMarks()
    self.marks = {}
end

return Board
