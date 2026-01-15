-- main.lua
-- Smooth 16x16 RPG movement with progress-based step animation

local tileSize = 8
-- integer render scaling to make the game larger on screen
local renderScale = 3
local povW, povH = 160, 144 -- camera viewport in game pixels
local cameraX, cameraY = 0, 0
local cameraLerpSpeed = 100 -- higher = snappier camera
local playerStep = 2 -- tiles per move (16px)
local infoText = ""
local encounterText = ""

-- Lightweight JSON loader: converts JSON text into Lua table by converting
-- JSON array/object syntax to Lua table syntax and using load. This is
-- intentionally small and expects well-formed JSON produced by our encoder.
local function decode_json(json)
    if not json or json == "" then return nil end
    -- convert JSON arrays to Lua tables
    local s = json
    -- replace true/false/null
    s = s:gsub("%f[%w]null%f[%W]", "nil")
    s = s:gsub("%f[%w]true%f[%W]", "true")
    s = s:gsub("%f[%w]false%f[%W]", "false")
    -- convert brackets to braces for arrays
    s = s:gsub('%[', '{')
    s = s:gsub('%]', '}')
    -- convert JSON object keys "key": to ["key"]=
    s = s:gsub('"([^"\n]-)"%s*:', '["%1"]=')
    -- now attempt to load
    local loader = loadstring or load
    local fn, err = loader("return " .. s)
    if not fn then return nil, err end
    local ok, res = pcall(fn)
    if not ok then return nil, res end
    return res
end

-- on-screen input state
local uiInput = {up=false, down=false, left=false, right=false, a=false, start=false}
local activeTouches = {} -- map touch id / "mouse" -> dir
local uiButtons = {} -- populated in love.load (screen pixels)
-- when a turn is made, block movement while that same input remains held
local inputBlockDir = nil
local inputBlockTimer = 0
local inputBlockDelay = 0.1 -- seconds to wait while holding after a turn before movement starts

local warps = {}

local function pointInRect(px, py, rx, ry, rw, rh)
    return px >= rx and py >= ry and px <= rx + rw and py <= ry + rh
end

local function screenToPixels(x, y)
    local ww, wh = love.graphics.getWidth(), love.graphics.getHeight()
    if x <= 1 and y <= 1 then
        return x * ww, y * wh
    end
    return x, y
end

-------------------------------------------------
-- PLAYER
-------------------------------------------------

local player = {
    tx = 1, ty = 1,
    x = 0, y = 0,
    startX = 0, startY = 0,
    targetX = 0, targetY = 0,

    size = 16,
    speed = 40,
    moving = false,

    dir = "down",
    animIndex = 2,
    stepLeft = true
}

-- track which map the player is currently on (saved/loaded)
player.currentMap = ""

-- Player's current Pokemon party (populate with a starter)
player.party = {}
do
    local ok, pmod = pcall(require, "pokemon")
    if ok and pmod and pmod.Pokemon then
        -- Create starter Pokemon using the new speciesId-based constructor
        table.insert(player.party, pmod.Pokemon:new("pikachu", 5))
        table.insert(player.party, pmod.Pokemon:new("squirtle", 5))
    end
end

-- Player's inventory (bag)
do
    local ok, itemModule = pcall(require, "item")
    if ok and itemModule then
        if itemModule.Inventory then
            player.bag = itemModule.Inventory:new()
        else
            print("Warning: item module loaded but no Inventory class found")
            player.bag = nil
        end
    else
        print("Warning: Failed to load item module: " .. tostring(itemModule))
        player.bag = nil
    end
end

-------------------------------------------------
-- MAP DATA
-------------------------------------------------

local mapWidth, mapHeight
local groundLayer = {}
local collisionLayer = {}
local tileProperties = {}
local unlockedWater = {}
local unlockedWaterAll = false
local menu = require("menu")
local battle = require("battle")

-- expose player to the menu so menu actions can access `player.party`
if menu then menu.player = player end

-------------------------------------------------
-- TILESET
-------------------------------------------------

local tileset
local quads = {}
local tileW, tileH -- tileset tile size (from TMX)

-- Tiled flip bits (stored in high bits of the gid)
local FLIPPED_HORIZONTALLY_FLAG = 0x80000000
local FLIPPED_VERTICALLY_FLAG   = 0x40000000
local FLIPPED_DIAGONALLY_FLAG   = 0x20000000

local function decodeGid(gid)
    local fh = false; local fv = false; local fd = false
    if gid >= FLIPPED_HORIZONTALLY_FLAG then gid = gid - FLIPPED_HORIZONTALLY_FLAG; fh = true end
    if gid >= FLIPPED_VERTICALLY_FLAG   then gid = gid - FLIPPED_VERTICALLY_FLAG;   fv = true end
    if gid >= FLIPPED_DIAGONALLY_FLAG   then gid = gid - FLIPPED_DIAGONALLY_FLAG;   fd = true end
    return gid, fh, fv, fd
end

-------------------------------------------------
-- CHARACTER SPRITES (SINGLE ROW)
-------------------------------------------------

local charSheet
local charQuads = {}
local charWaterQuads = {}
local shadowQuad = nil

local animFrames = {
    down  = {1, 2, 3},
    up    = {4, 5, 6},
    left  = {7, 8},
    right = {9, 10}
}

-------------------------------------------------
-- COLLISION (2x2 PLAYER)
-------------------------------------------------

local function isBlocked(tx, ty, approachDx, approachDy)
    approachDx = approachDx or 0
    approachDy = approachDy or 0
    local checks = {
        {tx, ty}, {tx + 1, ty},
        {tx, ty + 1}, {tx + 1, ty + 1}
    }

    for _, c in ipairs(checks) do
        local x, y = c[1], c[2]
        if x < 1 or y < 1 or x > mapWidth or y > mapHeight then
            return true
        end
        local idx = (y - 1) * mapWidth + x
        local collCount = #collisionLayer
        local rawgid = collisionLayer[idx]
        -- Defensive guard: if computed index is outside the parsed collision array,
        -- treat as blocked so movement doesn't go off-map.
        if idx < 1 or idx > collCount then
            return true
        end

        if rawgid and rawgid ~= 0 then
            local gid = decodeGid(rawgid)
            local props = tileProperties[gid]
            if props then
                if props.blocked == true then
                    return true
                end
                -- water tiles are blocked until unlocked by talking ('z')
                if props.water then
                    local key = string.format("%d,%d", x, y)
                    if not (unlockedWaterAll or unlockedWater[key]) then
                        return true
                    end
                end
                -- `jump` may be a string specifying allowed approach direction.
                -- Only enforce jump-based blocking when the `jump` property exists.
                local j = props.jump
                if j then
                    if j == true or j == "down" then
                        if not (approachDy and approachDy > 0) then
                            return true
                        end
                    elseif j == "left" then
                        if not (approachDx and approachDx < 0) then
                            return true
                        end
                    elseif j == "right" then
                        if not (approachDx and approachDx > 0) then
                            return true
                        end
                    else
                        return true
                    end
                end
            else
                return true
            end
        end
    end
    return false
end

local function tileHasJumpAt(tx, ty, approachDx, approachDy)
    approachDx = approachDx or 0
    approachDy = approachDy or 0
    local checks = {
        {tx, ty}, {tx + 1, ty},
        {tx, ty + 1}, {tx + 1, ty + 1}
    }
    for _, c in ipairs(checks) do
        local x, y = c[1], c[2]
        if x >= 1 and y >= 1 and x <= mapWidth and y <= mapHeight then
            local idx = (y - 1) * mapWidth + x
            local rawgid = collisionLayer[idx]
            if rawgid and rawgid ~= 0 then
                local gid = decodeGid(rawgid)
                local props = tileProperties[gid]
                if props and props.jump then
                    local j = props.jump
                    if j == true or j == "down" or j == "left" or j == "right" then
                        if j == true then return true end
                        if j == "down" and approachDy and approachDy > 0 then return true end
                        if j == "left" and approachDx and approachDx < 0 then return true end
                        if j == "right" and approachDx and approachDx > 0 then return true end
                    end
                end
            end
        end
    end
    return false
end

local function playerIsOnWater()
    local checks = {
        {player.tx, player.ty}, {player.tx + 1, player.ty},
        {player.tx, player.ty + 1}, {player.tx + 1, player.ty + 1}
    }
    for _, c in ipairs(checks) do
        local x, y = c[1], c[2]
        if x >= 1 and y >= 1 and x <= mapWidth and y <= mapHeight then
            local idx = (y - 1) * mapWidth + x
            local raw = collisionLayer[idx]
            if raw and raw ~= 0 then
                local gid = decodeGid(raw)
                local props = tileProperties[gid]
                if props and props.water then
                    return true
                end
            end
        end
    end
    return false
end

local currentMap = ""

local function loadMap(path, spawnTX, spawnTY, spawnDir)
    warps = {}
    groundLayer = {}
    collisionLayer = {}

    -- Read the TMX
    local tmx = love.filesystem.read(path)
    currentMap = path

    -- Map size
    mapWidth  = tonumber(tmx:match('width="(%d+)"'))
    mapHeight = tonumber(tmx:match('height="(%d+)"'))

    -- Tileset image
    local tilesetImage = tmx:match('<image.-source="([^"]+)"')
    if tilesetImage then
        tilesetImage = tilesetImage:gsub('^%.%./', 'tiled/')
        tilesetImage = tilesetImage:gsub('^sprites/', 'tiled/sprites/')
        tilesetImage = tilesetImage:gsub('^%./', '')
        tileset = love.graphics.newImage(tilesetImage)
    end

    -- Tileset size
    local tsTileW = tonumber(tmx:match('tilewidth="(%d+)"'))
    local tsTileH = tonumber(tmx:match('tileheight="(%d+)"'))
    tileSize = tsTileW
    tileW, tileH = tsTileW, tsTileH

    -- Build quads
    quads = {}
    local gid = 1
    for y = 0, tileset:getHeight() - tileH, tileH do
        for x = 0, tileset:getWidth() - tileW, tileW do
            quads[gid] = love.graphics.newQuad(x, y, tileW, tileH,
                tileset:getWidth(), tileset:getHeight())
            gid = gid + 1
        end
    end

    -- Parse tileset <tile> property definitions (map local ids -> global gids)
    tileProperties = {}
    -- Determine base directory of the TMX so relative tileset sources can be resolved
    local baseDir = path:match("(.*/)") or ""

    local function tryRead(pathCandidates)
        for _, p in ipairs(pathCandidates) do
            local ok, data = pcall(love.filesystem.read, p)
            if ok and data and data ~= "" then return data, p end
        end
        return nil, nil
    end

    -- Handle self-closing tileset tags that reference external .tsx files
    for tilesetBlock in tmx:gmatch("<tileset.-/>") do
        local firstgid = tonumber(tilesetBlock:match('firstgid="(%d+)"')) or 1
        local source = tilesetBlock:match('source="([^"]+)"')
        if source then
            local candidates = {
                source,
                baseDir .. source,
                source:gsub('^%./', ''),
                baseDir .. source:gsub('^%./', ''),
                source:gsub('^%.%./', ''),
                'tiled/' .. source:gsub('^%.%./', ''),
            }
            local tilesetContent, resolved = tryRead(candidates)
            if tilesetContent then
                for tileBlock in tilesetContent:gmatch("<tile.->.-</tile>") do
                    local id = tonumber(tileBlock:match('id="(%d+)"')) or 0
                    local gid = firstgid + id
                    local props = {}
                    for k,v in tileBlock:gmatch('<property[^>]-name="([^\"]+)"[^>]-value="([^\"]*)"') do
                        local val = v
                        if v == "true" then val = true elseif v == "false" then val = false end
                        props[k] = val
                    end
                    if next(props) then tileProperties[gid] = props end
                end
            end
        end
    end

    -- Also handle embedded tileset blocks that include inline <tile> definitions
    for tilesetBlock in tmx:gmatch("<tileset.->.-</tileset>") do
        local firstgid = tonumber(tilesetBlock:match('firstgid="(%d+)"')) or 1
        for tileBlock in tilesetBlock:gmatch("<tile.->.-</tile>") do
            local id = tonumber(tileBlock:match('id="(%d+)"')) or 0
            local gid = firstgid + id
            local props = {}
            for k,v in tileBlock:gmatch('<property[^>]-name="([^\"]+)"[^>]-value="([^\"]*)"') do
                local val = v
                if v == "true" then val = true elseif v == "false" then val = false end
                props[k] = val
            end
            if next(props) then tileProperties[gid] = props end
        end
    end

    -- Parse layers
    for layer in tmx:gmatch("<layer.->.-</layer>") do
        local name = layer:match('name="([^"]+)"')
        local data = layer:match("<data[^>]*>(.-)</data>")
        local csv = {}
        for n in data:gmatch("(%d+)") do table.insert(csv, tonumber(n)) end
        if name == "ground" then groundLayer = csv end
        if name == "collision" then collisionLayer = csv end
    end

    -- clear unlocked water on map load
    unlockedWater = {}
    unlockedWaterAll = false

    -- Parse warp objects
    for og in tmx:gmatch("<objectgroup.->.-</objectgroup>") do
        for obj in og:gmatch("<object.-</object>") do
            local w = {
                x = tonumber(obj:match('x="([^"]+)"')) or 0,
                y = tonumber(obj:match('y="([^"]+)"')) or 0,
                width  = tonumber(obj:match('width="([^"]+)"')) or 0,
                height = tonumber(obj:match('height="([^"]+)"')) or 0,
                properties = {}
            }
            for k,v in obj:gmatch('<property[^>]-name="([^"]+)"[^>]-value="([^"]*)"') do
                w.properties[k] = v
            end
            table.insert(warps, w)
        end
    end

    -- Spawn player
    player.tx = spawnTX
    player.ty = spawnTY
    player.x = (spawnTX - 1) * tileSize
    player.y = (spawnTY - 1) * tileSize
    player.targetX = player.x
    player.targetY = player.y
    player.moving = false
    if spawnDir then
        player.dir = spawnDir
        local frames = animFrames[player.dir]
        if frames then
            player.animIndex = (#frames == 3) and frames[2] or frames[1]
            if #frames == 3 then player.stepLeft = true end
        end
    end

    return tmx
end



-------------------------------------------------
-- LOVE.LOAD
-------------------------------------------------

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    local defaultMapPath = "tiled/inside.tmx"
    local defaultSpawnTX, defaultSpawnTY, defaultSpawnDir = 9, 25, "right"
    loadMap(defaultMapPath, defaultSpawnTX, defaultSpawnTY, defaultSpawnDir)

    -- Attempt to load saved player state from `save/player.json` and merge into `player`.
    local saved = nil
    if love.filesystem.getInfo("save/player.json") then
        local data = love.filesystem.read("save/player.json")
        if data then
            local tbl_or_err, derr = decode_json(data)
            if tbl_or_err then
                saved = tbl_or_err
            else
                infoText = "Save load failed: " .. tostring(derr or "invalid save")
            end
        end
    end

    if saved then
        -- merge saved fields into existing player table (preserve runtime-only fields)
        for k, v in pairs(saved) do
            player[k] = v
        end
        
        -- Reconstruct Pokemon instances from saved data (to restore metatables and methods)
        if player.party and #player.party > 0 then
            local ok, pmod = pcall(require, "pokemon")
            if ok and pmod and pmod.Pokemon then
                for i, pokemonData in ipairs(player.party) do
                    if type(pokemonData) == "table" and pokemonData.speciesId then
                        player.party[i] = pmod.Pokemon.fromSavedData(pokemonData)
                    end
                end
            end
        end
        
        -- Reconstruct Inventory instance from saved data (to restore metatables and methods)
        if player.bag then
            local ok, itemModule = pcall(require, "item")
            if ok and itemModule and itemModule.Inventory then
                local newBag = itemModule.Inventory:new()
                -- Restore items from saved bag
                for pocket, items in pairs(player.bag) do
                    if type(items) == "table" then
                        for itemId, itemData in pairs(items) do
                            if type(itemData) == "table" and itemData.quantity then
                                newBag:add(itemId, itemData.quantity)
                            end
                        end
                    end
                end
                player.bag = newBag
            end
        end
        
        -- If save specifies a different map, load it and place the player there.
        if player.currentMap and player.currentMap ~= "" then
            local mpath = player.currentMap
            local tx = player.tx or defaultSpawnTX
            local ty = player.ty or defaultSpawnTY
            local dir = player.dir or defaultSpawnDir
            loadMap(mpath, tx, ty, dir)
            player.currentMap = currentMap
        else
            player.currentMap = currentMap
        end
        infoText = "Save loaded"
    else
        player.currentMap = currentMap
        -- First load: give starter items if no save found
        if player.bag then
            player.bag:add("potion", 5)
            player.bag:add("pokeball", 10)
        end
    end

    -- If the player is placed on water after loading, unlock all water tiles.
    if playerIsOnWater() then
        unlockedWaterAll = true
        unlockedWater = {}
    end

    -- character sheet (single row, 1px border + spacing)
    charSheet = love.graphics.newImage("tiled/sprites/Characters (Overworld).png")
    local cw, ch = 16, 16
    local margin, spacing = 1, 1
    local imgw, imgh = charSheet:getWidth(), charSheet:getHeight()

    local count = math.floor((imgw - margin * 2 + spacing) / (cw + spacing))
    for i = 1, count do
        local sx = margin + (i - 1) * (cw + spacing)
        local sy = margin
        charQuads[i] = love.graphics.newQuad(sx, sy, cw, ch, imgw, imgh)
    end

    -- shadow is located at row 3, column 5 (1-based)
    do
        local row, col = 3, 5
        local sx = margin + (col - 1) * (cw + spacing)
        local sy = margin + (row - 1) * (ch + spacing)
        shadowQuad = love.graphics.newQuad(sx, sy, cw, ch, imgw, imgh)
    end

    -- build water-row quads (fourth row matches ordering of the first row)
    do
        local waterRow = 4
        local waterRowSy = margin + (waterRow - 1) * (ch + spacing)
        for i = 1, count do
            local sx = margin + (i - 1) * (cw + spacing)
            charWaterQuads[i] = love.graphics.newQuad(sx, waterRowSy, cw, ch, imgw, imgh)
        end
    end

    -- set fixed window size to requested POV * render scale
    love.window.setMode(povW * renderScale, povH * renderScale)

    -- initialize on-screen D-pad buttons (screen pixels)
    do
        local ww, wh = love.graphics.getWidth(), love.graphics.getHeight()
        local margin = 12
        local b = 44 -- button size in pixels
        local midX = margin + b
        local midY = wh - margin - b

        local function addButton(dir, cx, cy)
            uiButtons[dir] = { x = cx - b/2, y = cy - b/2, w = b, h = b }
        end

        addButton("up",    midX,       midY - b)
        addButton("down",  midX,       midY + b)
        addButton("left",  midX - b,   midY)
        addButton("right", midX + b,   midY)
        -- action button 'A' on the right side
        addButton("a", ww - margin - b, midY)
        addButton("start", ww - margin - b, midY - b)
    end

    -- initialize camera to follow player (in game pixels, before scaling)
    local centerX = player.x + player.size / 2
    local centerY = player.y + player.size / 2
    local maxCamX = math.max(0, mapWidth * tileSize - povW)
    local maxCamY = math.max(0, mapHeight * tileSize - povH)
    cameraX = math.floor(math.max(0, math.min(maxCamX, centerX - povW / 2)) + 0.5)
    cameraY = math.floor(math.max(0, math.min(maxCamY, centerY - povH / 2)) + 0.5)
end

-------------------------------------------------
-- LOVE.UPDATE
-------------------------------------------------

-------------------------------------------------
-- LOVE.UPDATE
-------------------------------------------------

-- resolve input into a single direction
local function getInputDir()
    if (menu and menu.isOpen and menu.isOpen()) or (battle and battle.isActive and battle.isActive()) then return nil, 0, 0 end
    local dx, dy = 0, 0
    if love.keyboard.isDown("up")    or uiInput.up    then dy = -1 end
    if love.keyboard.isDown("down")  or uiInput.down  then dy =  1 end
    if love.keyboard.isDown("left")  or uiInput.left  then dx = -1 end
    if love.keyboard.isDown("right") or uiInput.right then dx =  1 end
    if dx ~= 0 and dy ~= 0 then dx = 0 end

    if dy < 0 then return "up", dx, dy end
    if dy > 0 then return "down", dx, dy end
    if dx < 0 then return "left", dx, dy end
    if dx > 0 then return "right", dx, dy end
    return nil, 0, 0
end

function love.update(dt)
    if menu and menu.update then menu.update(dt) end
    if battle and battle.update then battle.update(dt) end
    local requestedDir, dx, dy = getInputDir()

    -- if we're not currently moving, handle rotate-first behavior
    if not player.moving then
        if requestedDir and requestedDir ~= player.dir then
            player.dir = requestedDir
            local frames = animFrames[player.dir]
            if frames then
                player.animIndex = (#frames == 3) and frames[2] or frames[1]
            end
            inputBlockDir = requestedDir
            inputBlockTimer = 0
            dx, dy = 0, 0
        end

        if not requestedDir and inputBlockDir then
            inputBlockDir = nil
            inputBlockTimer = 0
        end

        if inputBlockDir and requestedDir == inputBlockDir then
            inputBlockTimer = inputBlockTimer + dt
        end
    end

    if not player.moving
        and (dx ~= 0 or dy ~= 0)
        and not (inputBlockDir and requestedDir == inputBlockDir and inputBlockTimer < inputBlockDelay)
    then
        local nx = player.tx + dx * playerStep
        local ny = player.ty + dy * playerStep

        -- If the intended landing tile(s) are jump tiles (and approach allows),
        -- advance the landing past them so the player cannot stop on jump tiles.
        local jumped = false
        if tileHasJumpAt(nx, ny, dx, dy) then
            jumped = true
            nx = nx + dx
            ny = ny + dy
            -- if there are consecutive jump tiles, keep skipping up to a small limit
            local tries = 0
            while tileHasJumpAt(nx, ny, dx, dy) and tries < 4 do
                nx = nx + dx
                ny = ny + dy
                tries = tries + 1
            end
        end

        if not isBlocked(nx, ny, dx, dy) then
            player.tx, player.ty = nx, ny
            player.startX, player.startY = player.x, player.y
            player.targetX = (nx - 1) * tileSize
            player.targetY = (ny - 1) * tileSize
            player.moving = true

            -- mark jumping state for horizontal jumps and downward jumps
            player.jumping = jumped and (dx ~= 0 or dy > 0)
            player.moveProgress = 0

            inputBlockDir = nil
            inputBlockTimer = 0

            local frames = animFrames[player.dir]
            if frames then
                if player.jumping and (player.dir == "left" or player.dir == "right") then
                    player.animIndex = frames[1]
                elseif player.jumping and player.dir == "down" and #frames == 3 then
                    player.animIndex = frames[2]
                else
                    player.animIndex = (#frames == 3) and frames[2] or frames[1]
                end
            end
        end
    end

    if player.moving then
        local dxp = player.targetX - player.x
        local dyp = player.targetY - player.y
        local dist = math.sqrt(dxp*dxp + dyp*dyp)
        local total = math.sqrt((player.targetX-player.startX)^2 + (player.targetY-player.startY)^2)

        if dist < 1 then
            player.x, player.y = player.targetX, player.targetY
            player.moving = false
            player.jumping = false
            player.moveProgress = 0

            local frames = animFrames[player.dir]
            if frames then
                player.animIndex = (#frames == 3) and frames[2] or frames[1]
                if #frames == 3 then player.stepLeft = not player.stepLeft end
            end
            -- After completing a step, check for encounter objects (encounters layer)
            -- Objects parsed into `warps` may include encounter rects with a `grass` property.
            local cx = player.x + player.size * 0.5
            local cy = player.y + player.size * 0.5
            for _, w in ipairs(warps) do
                if w and w.properties then
                    local gv = w.properties.grass
                    local isGrass = (gv == true) or (gv == "true") or (gv == "1")
                    if isGrass then
                        if cx >= w.x and cx <= w.x + w.width and cy >= w.y and cy <= w.y + w.height then
                            if battle and battle.start and (not battle.isActive or not battle.isActive()) then
                                local roll = math.random(1, 100)
                                if roll <= 10 then
                                    -- If the encounter object specifies a comma-separated list of species dex numbers,
                                    -- build a wild list from those species; otherwise fall back to random wilds.
                                    local speciesProp = w.properties.species
                                    local wildList = nil
                                    if speciesProp and speciesProp ~= "" then
                                        local ok, pmod = pcall(require, "pokemon")
                                        if ok and pmod and pmod.Pokemon and pmod.PokemonSpecies then
                                            wildList = {}
                                            -- parse optional min/max level CSVs (order corresponds to species list)
                                            local minsProp = w.properties.minlevel or w.properties.minlevels or w.properties.min_levels or ""
                                            local maxsProp = w.properties.maxlevel or w.properties.maxlevels or w.properties.max_levels or ""
                                            local mins = {}
                                            local maxs = {}
                                            local function splitToList(str)
                                                local t = {}
                                                for part in (str or ""):gmatch("([^,]+)") do
                                                    table.insert(t, part:match("^%s*(.-)%s*$"))
                                                end
                                                return t
                                            end
                                            mins = splitToList(minsProp)
                                            maxs = splitToList(maxsProp)

                                            local idx = 0
                                            for item in speciesProp:gmatch("([^,]+)") do
                                                idx = idx + 1
                                                local s = item:match("^%s*(.-)%s*$")
                                                local dexnum = tonumber(s)
                                                if dexnum then
                                                    -- Search PokemonSpecies table for matching dex number
                                                    for speciesId, speciesData in pairs(pmod.PokemonSpecies) do
                                                        if speciesData.id == dexnum then
                                                            -- Determine level from min/max lists if provided
                                                            local minn = tonumber(mins[idx])
                                                            local maxn = tonumber(maxs[idx])
                                                            local level = 1
                                                            if minn and maxn then
                                                                if minn > maxn then local tmp = minn; minn = maxn; maxn = tmp end
                                                                level = math.max(1, math.random(minn, maxn))
                                                            elseif minn then
                                                                level = math.max(1, minn)
                                                            elseif maxn then
                                                                level = math.max(1, maxn)
                                                            end
                                                            local inst = pmod.Pokemon:new(speciesId, level)
                                                            table.insert(wildList, inst)
                                                            break
                                                        end
                                                    end
                                                end
                                            end
                                            if #wildList == 0 then wildList = nil end
                                        end
                                    end

                                    if wildList then
                                        battle.start(wildList, player)
                                    else
                                        battle.start(nil, player)
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            end
        else
            player.x = player.x + (dxp / dist) * player.speed * dt
            player.y = player.y + (dyp / dist) * player.speed * dt

            local progress = (total > 0) and (1 - dist / total) or 0
            player.moveProgress = progress
            local frames = animFrames[player.dir]

            if frames then
                if #frames == 3 then
                    if player.jumping and player.dir == "down" then
                        player.animIndex = frames[2]
                    elseif progress < 0.25 or progress >= 0.75 then
                        player.animIndex = frames[2]
                    else
                        player.animIndex = player.stepLeft and frames[1] or frames[3]
                    end
                else
                    if player.jumping and (player.dir == "left" or player.dir == "right") then
                        player.animIndex = frames[1]
                    else
                        player.animIndex = (progress < 0.5) and frames[1] or frames[2]
                    end
                end
            end
        end
    end

    local cx = player.x + player.size * 0.5
    local cy = player.y + player.size * 0.5

    for _, w in ipairs(warps) do
        if cx >= w.x and cx <= w.x + w.width and cy >= w.y and cy <= w.y + w.height then
            local targetMap = w.properties.target_map
            local tx = tonumber(w.properties.target_x)
            local ty = tonumber(w.properties.target_y)
            local dir = w.properties.target_dir

            if targetMap and tx and ty then
                loadMap(targetMap, tx, ty, dir)
                player.currentMap = currentMap
                -- If the player spawns on water after warping, unlock all water tiles.
                if playerIsOnWater() then
                    unlockedWaterAll = true
                    unlockedWater = {}
                end
                break
            end
        end
    end

    -- Update encounter hint text when standing inside a grass encounter rect
    encounterText = ""
    for _, w in ipairs(warps) do
        if w and w.properties then
            local gv = w.properties.grass
            local isGrass = (gv == true) or (gv == "true") or (gv == "1")
            if isGrass then
                if cx >= w.x and cx <= w.x + w.width and cy >= w.y and cy <= w.y + w.height then
                    -- robustly find any property whose name begins with 'species' (case-insensitive)
                    local sp = ""
                    for pk, pv in pairs(w.properties) do
                        if type(pk) == "string" and pk:lower():match("^species") then
                            if pv ~= nil and tostring(pv) ~= "" then
                                sp = tostring(pv)
                                break
                            end
                        end
                    end
                    if sp ~= "" then
                        encounterText = "Species: " .. sp
                    else
                        encounterText = "Species: (any)"
                    end
                    break
                end
            end
        end
    end

    -- If player is not on water anymore, re-lock all water tiles.
    if not player.moving and unlockedWaterAll and not playerIsOnWater() then
        unlockedWaterAll = false
        unlockedWater = {}
    end

    local centerX = player.x + player.size / 2
    local centerY = player.y + player.size / 2
    local maxCamX = math.max(0, mapWidth * tileSize - povW)
    local maxCamY = math.max(0, mapHeight * tileSize - povH)

    cameraX = math.floor(math.max(0, math.min(maxCamX, centerX - povW / 2)) + 0.5)
    cameraY = math.floor(math.max(0, math.min(maxCamY, centerY - povH / 2)) + 0.5)
end

-------------------------------------------------
-- INPUT: runtime tweaks
-------------------------------------------------

function love.keypressed(key)
    if menu and menu.isOpen and menu.isOpen() then
        if menu.keypressed then menu.keypressed(key) end
        return
    end

    if battle and battle.isActive and battle.isActive() then
        if battle.keypressed then battle.keypressed(key) end
        return
    end

    if key == "[" then
        player.speed = math.max(10, player.speed - 20)
        debugText = "speed: " .. tostring(player.speed)
    elseif key == "]" then
        player.speed = player.speed + 20
        debugText = "speed: " .. tostring(player.speed)
    elseif key == "b" or key == "B" then
        -- start/stop a simple battle
        if battle and battle.isActive and battle.isActive() then
            if battle["end"] then battle["end"]() end
        elseif battle and battle.start then
            -- Start battle and pass the player so their first party member is used
            battle.start(nil, player)
        end
        return
    elseif key == "z" or key == "Z" then
        -- talk / interact: unlock water tile in front of the player
        local dx, dy = 0, 0
        if player.dir == "up" then dy = -1 end
        if player.dir == "down" then dy = 1 end
        if player.dir == "left" then dx = -1 end
        if player.dir == "right" then dx = 1 end
        -- target top-left tile of the tile-sized step in front
        local tx = player.tx + dx * playerStep
        local ty = player.ty + dy * playerStep
        if tx >= 1 and ty >= 1 and tx <= mapWidth and ty <= mapHeight then
            local idx = (ty - 1) * mapWidth + tx
            local raw = collisionLayer[idx]
            if raw and raw ~= 0 then
                local gid = decodeGid(raw)
                local props = tileProperties[gid]
                if props and props.water then
                        local key = string.format("%d,%d", tx, ty)
                        unlockedWater[key] = true
                        unlockedWaterAll = true
                        infoText = "Water unlocked"
                        -- attempt to step forward into the unlocked water tile
                        if not player.moving then
                            if not isBlocked(tx, ty, dx, dy) then
                                player.tx, player.ty = tx, ty
                                player.startX, player.startY = player.x, player.y
                                player.targetX = (tx - 1) * tileSize
                                player.targetY = (ty - 1) * tileSize
                                player.moving = true
                                player.jumping = false
                                player.moveProgress = 0
                                inputBlockDir = nil
                                inputBlockTimer = 0
                                local frames = animFrames[player.dir]
                                if frames then
                                    player.animIndex = (#frames == 3) and frames[2] or frames[1]
                                end
                            end
                        end
                else
                    infoText = "Nothing to talk to"
                end
            else
                infoText = "Nothing to talk to"
            end
        else
            infoText = "Nothing to talk to"
        end
    end

    if key == "space" then
        if menu and menu.toggle then menu.toggle() end
    end

end

-------------------------------------------------
-- MOUSE / TOUCH INPUT (on-screen buttons)
-------------------------------------------------

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    for dir, b in pairs(uiButtons) do
        if pointInRect(x, y, b.x, b.y, b.w, b.h) then
            uiInput[dir] = true
            activeTouches["mouse"] = dir
            -- If menu is open, route on-screen presses to the menu instead
            if menu and menu.isOpen and menu.isOpen() then
                if dir == "up" or dir == "down" or dir == "left" or dir == "right" then
                    if menu.keypressed then menu.keypressed(dir) end
                elseif dir == "a" then
                    if menu.keypressed then menu.keypressed("return") end
                elseif dir == "start" then
                    if menu.keypressed then menu.keypressed("space") end
                end
            elseif battle and battle.isActive and battle.isActive() then
                -- Route on-screen presses to battle controls while a battle is active
                if dir == "up" or dir == "down" or dir == "left" or dir == "right" then
                    if battle.keypressed then battle.keypressed(dir) end
                elseif dir == "a" then
                    if battle.keypressed then battle.keypressed("z") end
                elseif dir == "start" then
                    if battle.keypressed then battle.keypressed("space") end
                end
            else
                if dir == "a" then
                    love.keypressed("z")
                elseif dir == "start" then
                    love.keypressed("space")
                end
            end
        end
    end
end

function love.mousereleased(x, y, button)
    if button ~= 1 then return end
    local dir = activeTouches["mouse"]
    if dir then uiInput[dir] = false; activeTouches["mouse"] = nil end
end

function love.touchpressed(id, x, y)
    local sx, sy = screenToPixels(x, y)
    for dir, b in pairs(uiButtons) do
        if pointInRect(sx, sy, b.x, b.y, b.w, b.h) then
            uiInput[dir] = true
            activeTouches[id] = dir
            -- If menu is open, route on-screen presses to the menu instead
            if menu and menu.isOpen and menu.isOpen() then
                if dir == "up" or dir == "down" or dir == "left" or dir == "right" then
                    if menu.keypressed then menu.keypressed(dir) end
                elseif dir == "a" then
                    if menu.keypressed then menu.keypressed("return") end
                elseif dir == "start" then
                    if menu.keypressed then menu.keypressed("space") end
                end
            elseif battle and battle.isActive and battle.isActive() then
                -- Route on-screen presses to battle controls while a battle is active
                if dir == "up" or dir == "down" or dir == "left" or dir == "right" then
                    if battle.keypressed then battle.keypressed(dir) end
                elseif dir == "a" then
                    if battle.keypressed then battle.keypressed("z") end
                elseif dir == "start" then
                    if battle.keypressed then battle.keypressed("space") end
                end
            else
                if dir == "a" then
                    love.keypressed("z")
                elseif dir == "start" then
                    love.keypressed("space")
                end
            end
        end
    end
end

function love.touchreleased(id, x, y)
    local dir = activeTouches[id]
    if dir then uiInput[dir] = false; activeTouches[id] = nil end
end

-------------------------------------------------
-- LOVE.DRAW
-------------------------------------------------

function love.draw()
    love.graphics.push()
    love.graphics.scale(renderScale, renderScale)
    love.graphics.translate(-cameraX, -cameraY)

    for y = 1, mapHeight do
        for x = 1, mapWidth do
            local idx = (y - 1) * mapWidth + x
            local rawgid = groundLayer[idx]
            if rawgid and rawgid > 0 then
                local gid, fh, fv, fd = decodeGid(rawgid)
                local quad = quads[gid]
                if quad then
                    local sx, sy, rot = 1, 1, 0
                    if fd then
                        if fh and not fv then
                            rot = math.pi/2
                        elseif fh and fv then
                            rot = math.pi
                            sx = -1
                        elseif not fh and fv then
                            rot = -math.pi/2
                        else
                            sy = -1
                        end
                    else
                        if fh then sx = -1 end
                        if fv then sy = -1 end
                    end

                    local ox = (tileW or tileSize) * 0.5
                    local oy = (tileH or tileSize) * 0.5
                    local drawX = (x - 1) * tileSize + ox
                    local drawY = (y - 1) * tileSize + oy

                    love.graphics.draw(tileset, quad, drawX, drawY, rot, sx, sy, ox, oy)
                end
            end
        end
    end

    -- character draw with optional jump vertical offset and shadow
    local drawX = math.floor(player.x + 0.5)
    local drawY = math.floor(player.y + 0.5)
    if player.jumping and player.moveProgress then
        local jumpH = 6 -- pixels to move up at peak
        local off = -math.sin((player.moveProgress or 0) * math.pi) * jumpH
        drawY = math.floor(player.y + off + 0.5)
    end

    -- draw shadow under character while jumping
    if shadowQuad and player.jumping then
        local shadowCx = math.floor(player.x + player.size * 0.5 + 0.5)
        local shadowCy = math.floor(player.y + player.size - 2 + 0.5)
        local prog = player.moveProgress or 0
        local scale = 1 - 0.25 * math.sin(prog * math.pi)
        local alpha = 0.85 - 0.4 * math.sin(prog * math.pi)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(charSheet, shadowQuad, shadowCx, shadowCy, 0, scale, scale, player.size * 0.5, player.size * 0.5)
        love.graphics.setColor(1,1,1,1)
    end

    do
        local drawQuad = charQuads[player.animIndex] or charQuads[1]
        if playerIsOnWater() and charWaterQuads[player.animIndex] then
            drawQuad = charWaterQuads[player.animIndex]
        end
        love.graphics.draw(charSheet, drawQuad, drawX, drawY)
    end

    love.graphics.pop()

    -- debug text (unscaled) with background so it's always visible
    local displayText = ""
    if encounterText and encounterText ~= "" then
        displayText = encounterText
    end
    if infoText and infoText ~= "" then
        if displayText ~= "" then displayText = displayText .. "\n" .. infoText else displayText = infoText end
    end
    if warpDebug and warpDebug ~= "" then
        if displayText ~= "" then displayText = displayText .. "\n" .. warpDebug else displayText = warpDebug end
    end
    if displayText ~= "" then
        local font = love.graphics.getFont()
        local maxw = 0
        local lines = {}
        for line in displayText:gmatch("([^\n]+)") do
            table.insert(lines, line)
            local w = font and font:getWidth(line) or 0
            if w > maxw then maxw = w end
        end
        local h = (font and font:getHeight() or 12) * #lines
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 2, 2, maxw + 8, h + 6, 4, 4)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(displayText, 6, 4)
    end

    -- draw menu overlay (unscaled)
    if menu and menu.draw then menu.draw() end
    -- draw battle overlay (unscaled)
    if battle and battle.draw then battle.draw() end

    -- draw on-screen D-pad (unscaled, screen pixels) on top of overlays
    for dir, b in pairs(uiButtons) do
        local cx = b.x + b.w/2
        local cy = b.y + b.h/2
        local pressed = uiInput[dir]
        love.graphics.setColor(0, 0, 0, pressed and 0.6 or 0.4)
        love.graphics.circle("fill", cx, cy, math.min(b.w, b.h) * 0.5)
        love.graphics.setColor(1,1,1, pressed and 1 or 0.9)

        local s = math.min(b.w, b.h) * 0.28
        if dir == "up" then
            love.graphics.polygon("fill", cx, cy - s, cx - s, cy + s, cx + s, cy + s)
        elseif dir == "down" then
            love.graphics.polygon("fill", cx, cy + s, cx - s, cy - s, cx + s, cy - s)
        elseif dir == "left" then
            love.graphics.polygon("fill", cx - s, cy, cx + s, cy - s, cx + s, cy + s)
        elseif dir == "right" then
            love.graphics.polygon("fill", cx + s, cy, cx - s, cy - s, cx - s, cy + s)
        elseif dir == "a" then
            local font = love.graphics.getFont()
            local text = "A"
            local fw = font and font:getWidth(text) or 8
            local fh = font and font:getHeight() or 8
            love.graphics.print(text, cx - fw/2, cy - fh/2)
        elseif dir == "start" then
            local font = love.graphics.getFont()
            local text = "START"
            local fw = font and font:getWidth(text) or 28
            local fh = font and font:getHeight() or 8
            love.graphics.print(text, cx - fw/2, cy - fh/2)
        end
    end
    love.graphics.setColor(1,1,1)
end

