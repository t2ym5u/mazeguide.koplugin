local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonDialog    = require("ui/widget/buttondialog")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local Duo        = require("duo")
local ScreenBase = require("screen_base")

local Board      = lrequire("board")
local MazeView   = lrequire("board_widget")

local RULES_EN = [[
Guide & Explorer — two readers, one maze

Each player has a reader. The guide sees the whole map of a maze: its walls, its landmarks (symbols on the floor), the key and the exit door. The explorer is lost inside and sees only the cells around them. Together, get the explorer out!

Starting
• One player taps New game → Start a game and reads the code aloud. The other taps New game → Join a game and types it. One is the guide, the other the explorer.
• The difficulty is set by the player who starts (menu): Easy 7×7 (the explorer sees two cells around), Medium 9×9 and Hard 11×11 (one cell around).

Playing
• The guide does not know where the explorer starts. Explorer: describe what you see — walls, landmarks ("a black triangle two cells to my east"), the grey rock at the edge of the maze.
• Guide: find the explorer on your map, then give directions. North is at the top of both screens. Tap cells on your map to pencil where the explorer may be; tap again to rub out.
• Explorer: walk with the arrows, or by tapping a cell next to you. Pick up the key, then go through the door.

The explorer's reader counts the steps and gives the shortest possible way at the end.
]]

local RULES_FR = [[
Le guide et l'explorateur — deux liseuses, un labyrinthe

Chaque joueur a une liseuse. Le guide voit le plan complet d'un labyrinthe : ses murs, ses repères (des symboles au sol), la clé et la porte de sortie. L'explorateur est perdu à l'intérieur et ne voit que les cases autour de lui. Ensemble, faites-le sortir !

Pour commencer
• Un joueur touche Nouvelle partie → Lancer une partie et lit le code à voix haute. L'autre touche Nouvelle partie → Rejoindre une partie et le saisit. L'un est le guide, l'autre l'explorateur.
• La difficulté est celle du joueur qui lance (menu) : Facile 7×7 (l'explorateur voit à deux cases), Moyen 9×9 et Difficile 11×11 (à une case).

Déroulement
• Le guide ne sait pas où l'explorateur commence. Explorateur : décrivez ce que vous voyez — les murs, les repères (« un triangle noir deux cases à l'est »), la roche grise au bord du labyrinthe.
• Guide : retrouvez l'explorateur sur votre plan, puis guidez-le. Le nord est en haut des deux écrans. Touchez des cases de votre plan pour noter où l'explorateur peut être ; touchez de nouveau pour effacer.
• Explorateur : avancez avec les flèches, ou en touchant une case voisine. Ramassez la clé, puis passez la porte.

La liseuse de l'explorateur compte les pas et donne le chemin le plus court à la fin.
]]

local LEVEL_NAMES = { "Easy", "Medium", "Hard" }

local MazeScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function MazeScreen:init()
    self.board = Board.load(self.plugin:loadState())
    ScreenBase.init(self)
end

function MazeScreen:serializeState()
    return self.board and self.board:serialize() or nil
end

function MazeScreen:save()
    self.plugin:saveState(self:serializeState())
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function MazeScreen:isRoundOver()
    return not self.board or self.board:isOver()
end

function MazeScreen:actionRows()
    local b = self.board
    if not b then return {} end
    if b.role == "guide" then
        return { { { text = _("Rub out the pencil marks"), callback = function() self:onClearMarks() end } } }
    end
    return { {
        { text = "←", callback = function() self:onMove("w") end },
        { text = "↑", callback = function() self:onMove("n") end },
        { text = "↓", callback = function() self:onMove("s") end },
        { text = "→", callback = function() self:onMove("e") end },
    } }
end

function MazeScreen:buildLayout()
    local title_bar = self:buildTitleBar(_("Guide & Explorer"), function()
        local items = {
            { text = _("New game"), callback = function() self:onNewGame() end },
            { text = T(_("Difficulty: %1"), _(LEVEL_NAMES[self.plugin:getSetting("level", 1)])),
              callback = function() self:openLevelMenu() end },
        }
        if self.board then
            items[#items + 1] = { text = _("Show the game code"), callback = function() self:showCode() end }
        end
        items[#items + 1] = self:makeRulesButtonConfig(RULES_EN, RULES_FR)
        return items
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(self:actionRows()),
    }

    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    local pad = Size.padding.large
    local content
    if self.board then
        self.view = MazeView:new{
            board = self.board, max_width = budget_w - 2 * pad, max_height = budget_h - 2 * pad,
            onCellTapped = function(r, c) self:onCellTapped(r, c) end,
        }
        self.board_widget = self.view
        content = self.view
    else
        self.view, self.board_widget = nil, nil
        content = TextBoxWidget:new{
            text = _("Each player needs a reader with this game. One starts a game and reads the code aloud; the other joins with that code."),
            face = Font:getFace("infofont"),
            width = math.min(budget_w, Device.screen:scaleBySize(500)),
            alignment = "center",
        }
    end
    local frame = FrameContainer:new{ padding = pad, margin = 0, bordersize = 0, content }

    if self:isLandscape() then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center", frame, HorizontalSpan:new{ width = self:getGutter() }, controls,
        })
    else
        self:buildPortraitLayout(title_bar, frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function MazeScreen:rebuild()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function MazeScreen:updateStatus(message)
    local b = self.board
    local status = message
    if not status then
        if not b then
            status = _("Start or join a game.")
        elseif b.role == "guide" then
            status = _("Find the explorer, then lead the way.")
        elseif b.done then
            status = T(_("Out in %1 steps! The shortest way took %2."), b.moves, b.maze.par)
        else
            status = self:joinStatus(
                T(_("Steps walked: %1"), b.moves),
                b.has_key and _("Key: in your pocket") or _("Key: not found yet"))
        end
    end
    ScreenBase.updateStatus(self, status)
end

-- ---------------------------------------------------------------------------
-- Play
-- ---------------------------------------------------------------------------

function MazeScreen:onCellTapped(r, c)
    local b = self.board
    if b.role == "guide" then
        b:toggleMark(r, c)
        self:save()
        self.view:refresh(self)
        return
    end
    local d = b:dirTo(r, c)
    if d then self:onMove(d) end
end

function MazeScreen:onMove(d)
    local b = self.board
    local res = b:move(d)
    if not res then return end
    if res == "wall" then
        self:updateStatus(_("A wall blocks the way."))
        return
    end
    self:save()
    self.view:refresh(self)
    if res == "key" then
        self:updateStatus()
        self:showMessage(_("You picked up the key! Now find the door."), 3)
    elseif res == "locked" then
        self:updateStatus(_("The door is locked: find the key first."))
    elseif res == "out" then
        self:updateStatus()
        self:refreshActionBar()
        self:showMessage(T(_("Out in %1 steps! The shortest way took %2."), b.moves, b.maze.par), 5)
    else
        self:updateStatus()
    end
end

function MazeScreen:onClearMarks()
    self.board:clearMarks()
    self:save()
    self.view:refresh(self)
end

-- ---------------------------------------------------------------------------
-- New game
-- ---------------------------------------------------------------------------

function MazeScreen:onNewGame()
    Duo.newGameDialog{
        title     = _("Guide & Explorer"),
        nvariants = #Board.LEVELS,
        variant   = self.plugin:getSetting("level", 1),
        variant_text = function(v) return T(_("Difficulty: %1"), _(LEVEL_NAMES[v])) end,
        roles = {
            { id = "guide",    text = _("Guide (the map)") },
            { id = "explorer", text = _("Explorer (in the maze)") },
        },
        on_start = function(game)
            self.board = Board.new{ seed = game.seed, level = game.variant, role = game.role, code = game.code }
            self:save()
            self:rebuild()
        end,
    }
end

function MazeScreen:showCode()
    local b = self.board
    self:showMessage(T(_("Game code: %1"), Duo.format(b.code)) .. "\n"
        .. T(_("Difficulty: %1"), _(LEVEL_NAMES[b.level])), 6)
end

function MazeScreen:openLevelMenu()
    local dlg
    local buttons = {}
    for i, name in ipairs(LEVEL_NAMES) do
        buttons[#buttons + 1] = { {
            text = _(name),
            callback = function()
                UIManager:close(dlg)
                self.plugin:saveSetting("level", i)
            end,
        } }
    end
    dlg = ButtonDialog:new{
        title = _("Difficulty of the games you start"),
        buttons = buttons,
    }
    UIManager:show(dlg)
end

return MazeScreen
