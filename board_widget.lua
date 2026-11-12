local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer     = require("ffi/blitbuffer")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager      = require("ui/uimanager")

local Board  = lrequire("board")
local Shapes = lrequire("shapes")

local C_BG    = Blitbuffer.COLOR_WHITE
local C_FG    = Blitbuffer.COLOR_BLACK
local C_FLOOR = Blitbuffer.COLOR_GRAY_E
local C_ROCK  = Blitbuffer.COLOR_GRAY_7
local C_MARK  = Blitbuffer.COLOR_GRAY_9

-- ---------------------------------------------------------------------------
-- Icons
-- ---------------------------------------------------------------------------

local function paintKey(bb, x, y, s)
    local r = math.floor(s * 0.16)
    local t = math.max(2, math.floor(s / 14))
    local cx, cy = x + math.floor(s * 0.3), y + math.floor(s / 2)
    bb:paintCircle(cx, cy, r, C_FG, t)
    local shaft_x = cx + r
    local shaft_w = math.floor(s * 0.48)
    bb:paintRect(shaft_x, cy - math.floor(t / 2), shaft_w, t + 1, C_FG)
    local tooth = math.floor(s * 0.12)
    bb:paintRect(shaft_x + shaft_w - t, cy, t + 1, tooth, C_FG)
    bb:paintRect(shaft_x + shaft_w - 3 * t, cy, t + 1, math.floor(tooth * 0.7), C_FG)
end

local function paintDoor(bb, x, y, s)
    local w, h = math.floor(s * 0.44), math.floor(s * 0.66)
    local dx, dy = x + math.floor((s - w) / 2), y + math.floor((s - h) / 2)
    local t = math.max(2, math.floor(s / 14))
    bb:paintRect(dx, dy, w, h, C_FG)
    bb:paintRect(dx + t, dy + t, w - 2 * t, h - t, C_BG)
    bb:paintCircle(dx + w - 3 * t, dy + math.floor(h / 2), math.max(2, t), C_FG)
end

-- The explorer: a pawn (head and shoulders).
local function paintPawn(bb, x, y, s)
    local cx = x + math.floor(s / 2)
    local head = math.floor(s * 0.13)
    bb:paintCircle(cx, y + math.floor(s * 0.3), head, C_FG)
    local top, h = y + math.floor(s * 0.45), math.floor(s * 0.32)
    for i = 0, h - 1 do
        local hw = math.floor(s * 0.1 + (s * 0.14) * i / h)
        bb:paintRect(cx - hw, top + i, 2 * hw, 1, C_FG)
    end
end

-- ---------------------------------------------------------------------------
-- MazeView — the guide's whole map, or the explorer's window around them.
-- ---------------------------------------------------------------------------

local MazeView = InputContainer:extend{
    board      = nil,
    max_width  = 0,
    max_height = 0,
    onCellTapped = nil,   -- function(r, c), maze coordinates
}

function MazeView:init()
    local b = self.board
    if b.role == "guide" then
        self.span = b.maze.n
    else
        self.span = 2 * b.view + 1
    end
    local cell = math.floor(math.min(self.max_width, self.max_height) / self.span)
    -- The explorer's window stays a comfortable size, not a wall of grey.
    if b.role == "explorer" then cell = math.min(cell, math.floor(math.min(self.max_width, self.max_height) / 3.2)) end
    self.cell = math.max(cell, 14)
    self.dimen = Geom:new{ w = self.cell * self.span, h = self.cell * self.span }
    self.ges_events = {
        TapCell = { GestureRange:new{ ges = "tap", range = function() return self.paint_rect end } },
    }
end

-- Maze cell shown at window position (i, j), 1-based.
function MazeView:mazeCell(i, j)
    local b = self.board
    if b.role == "guide" then return i, j end
    return b.pos[1] - b.view + i - 1, b.pos[2] - b.view + j - 1
end

function MazeView:onTapCell(_, ges)
    if not self.paint_rect then return false end
    local j = math.floor((ges.pos.x - self.paint_rect.x) / self.cell) + 1
    local i = math.floor((ges.pos.y - self.paint_rect.y) / self.cell) + 1
    if i >= 1 and i <= self.span and j >= 1 and j <= self.span and self.onCellTapped then
        self.onCellTapped(self:mazeCell(i, j))
    end
    return true
end

function MazeView:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }
    local b, m, cell = self.board, self.board.maze, self.cell
    local n = m.n
    local wall = math.max(3, math.floor(cell / 9))
    local guide = b.role == "guide"
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BG)
    for i = 1, self.span do
        for j = 1, self.span do
            local r, c = self:mazeCell(i, j)
            local px, py = x + (j - 1) * cell, y + (i - 1) * cell
            if r < 1 or r > n or c < 1 or c > n then
                -- Beyond the edge of the maze: solid rock.
                bb:paintRect(px, py, cell, cell, C_ROCK)
            else
                if not guide then bb:paintRect(px, py, cell, cell, C_FLOOR) end
                if guide and b:isMarked(r, c) then
                    bb:paintRect(px, py, cell, cell, C_MARK)
                end
                local lm = m.landmark[r][c]
                if lm then
                    Shapes.paint(bb, Board.SHAPES[math.floor((lm - 1) / 2) + 1], lm % 2 == 1,
                        px + math.floor(cell * 0.1), py + math.floor(cell * 0.1), math.floor(cell * 0.8))
                end
                if r == m.key[1] and c == m.key[2] and not b.has_key then paintKey(bb, px, py, cell) end
                if r == m.exit[1] and c == m.exit[2] then paintDoor(bb, px, py, cell) end
                if not guide and r == b.pos[1] and c == b.pos[2] then paintPawn(bb, px, py, cell) end
            end
        end
    end
    -- Walls: drawn after the cells so they sit on top.
    for i = 1, self.span do
        for j = 1, self.span do
            local r, c = self:mazeCell(i, j)
            if r >= 1 and r <= n and c >= 1 and c <= n then
                local px, py = x + (j - 1) * cell, y + (i - 1) * cell
                local h = math.floor(wall / 2)
                if Board.wall(m, r, c, "n") then bb:paintRect(px - h, py - h, cell + wall, wall, C_FG) end
                if Board.wall(m, r, c, "s") then bb:paintRect(px - h, py + cell - h, cell + wall, wall, C_FG) end
                if Board.wall(m, r, c, "w") then bb:paintRect(px - h, py - h, wall, cell + wall, C_FG) end
                if Board.wall(m, r, c, "e") then bb:paintRect(px + cell - h, py - h, wall, cell + wall, C_FG) end
            end
        end
    end
end

function MazeView:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

return MazeView
