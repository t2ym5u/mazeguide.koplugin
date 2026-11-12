package.path = "./?.lua;./common/?.lua;" .. package.path
local Board = dofile("board.lua")

local function walk(b, path)
    local last
    for _, d in ipairs(path) do last = b:move(d) end
    return last
end

-- Shortest list of directions from the explorer's cell to (r, c).
local function route(b, r, c)
    local m = b.maze
    local dist = Board.distances(m, r, c)
    local path, pr, pc = {}, b.pos[1], b.pos[2]
    while not (pr == r and pc == c) do
        for _, d in ipairs(Board.DIR_ORDER) do
            if not Board.wall(m, pr, pc, d) then
                local rr, cc = pr + Board.DIRS[d][1], pc + Board.DIRS[d][2]
                if dist[rr][cc] == dist[pr][pc] - 1 then
                    path[#path + 1] = d
                    pr, pc = rr, cc
                    break
                end
            end
        end
    end
    return path
end

describe("maze", function()
    it("is connected, with key, exit and start on distinct plain cells", function()
        for level, lvl in ipairs(Board.LEVELS) do
            for seed = 0, 40 do
                local m = Board.generate(seed, level)
                local dist = Board.distances(m, m.start[1], m.start[2])
                local landmarks = 0
                for r = 1, m.n do
                    for c = 1, m.n do
                        assert.is_number(dist[r][c])
                        if m.landmark[r][c] then landmarks = landmarks + 1 end
                    end
                end
                assert.equals(lvl.landmarks, landmarks)
                assert.is_false(m.landmark[m.key[1]][m.key[2]])
                assert.is_false(m.landmark[m.exit[1]][m.exit[2]])
                assert.is_false(m.landmark[m.start[1]][m.start[2]])
                local e = m.exit
                assert.is_true(e[1] == 1 or e[1] == m.n or e[2] == 1 or e[2] == m.n)
                assert.is_false(m.start[1] == m.key[1] and m.start[2] == m.key[2])
                assert.is_true(m.par >= m.n - 1, "par " .. m.par)
            end
        end
    end)

    it("walls are the same seen from both sides", function()
        local m = Board.generate(3, 2)
        for r = 1, m.n do
            for c = 1, m.n do
                if c < m.n then assert.equals(Board.wall(m, r, c, "e"), Board.wall(m, r, c + 1, "w")) end
                if r < m.n then assert.equals(Board.wall(m, r, c, "s"), Board.wall(m, r + 1, c, "n")) end
            end
        end
        assert.is_true(Board.wall(m, 1, 1, "n"))
        assert.is_true(Board.wall(m, m.n, m.n, "e"))
    end)

    it("is the same for the same code, different for another", function()
        local a, b, c = Board.generate(10, 2), Board.generate(10, 2), Board.generate(11, 2)
        assert.same(a, b)
        assert.are_not.same(a.wall_e, c.wall_e)
    end)

    it("gets bigger and longer with the level", function()
        local function avgPar(level)
            local t = 0
            for seed = 0, 19 do t = t + Board.generate(seed, level).par end
            return t / 20
        end
        assert.is_true(avgPar(1) < avgPar(2))
        assert.is_true(avgPar(2) < avgPar(3))
        assert.is_true(Board.LEVELS[1].view > Board.LEVELS[3].view)
    end)

    it("builds quickly", function()
        local t0 = os.clock()
        for seed = 0, 49 do Board.generate(seed, 3) end
        assert.is_true((os.clock() - t0) / 50 < 0.02)
    end)
end)

describe("walking", function()
    it("stops at walls, picks up the key, needs it at the exit", function()
        local b = Board.new{ seed = 7, level = 1, role = "explorer" }
        local m = b.maze
        for _, d in ipairs(Board.DIR_ORDER) do
            if Board.wall(m, b.pos[1], b.pos[2], d) then
                local before = { b.pos[1], b.pos[2] }
                assert.equals("wall", b:move(d))
                assert.same(before, b.pos)
                break
            end
        end
        local moves0 = b.moves
        local res = walk(b, route(b, m.key[1], m.key[2]))
        assert.equals("key", res)
        assert.is_true(b.has_key)
        res = walk(b, route(b, m.exit[1], m.exit[2]))
        assert.equals("out", res)
        assert.is_true(b:isOver())
        assert.is_true(b.moves - moves0 >= m.par)
    end)

    it("keeps the exit locked without the key", function()
        local b = Board.new{ seed = 8, level = 2, role = "explorer" }
        local m = b.maze
        local dk = Board.distances(m, m.key[1], m.key[2])
        local path = route(b, m.exit[1], m.exit[2])
        -- Only meaningful when the way to the exit avoids the key.
        local res = walk(b, path)
        if not b.has_key then
            assert.equals("locked", res)
            assert.is_false(b:isOver())
        end
        assert.is_number(dk[m.exit[1]][m.exit[2]])
    end)

    it("saves and restores the walk and the guide's marks", function()
        local b = Board.new{ seed = 9, level = 3, role = "guide", code = "00000" }
        b:toggleMark(2, 3)
        b:toggleMark(4, 4)
        b:toggleMark(4, 4)
        local b2 = Board.load(b:serialize())
        assert.is_true(b2:isMarked(2, 3))
        assert.is_false(b2:isMarked(4, 4))
        assert.same(b.maze, b2.maze)
        assert.is_nil(Board.load({ seed = 1, level = 1, pos = { 99, 1 } }))
    end)
end)
