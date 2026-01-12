-- main.lua
-- Smooth 16x16 RPG movement with progress-based step animation

local tileSize = 8
-- integer render scaling to make the game larger on screen
local renderScale = 3
local povW, povH = 160, 144 -- camera viewport in game pixels
local cameraX, cameraY = 0, 0
local cameraLerpSpeed = 100 -- higher = snappier camera
local playerStep = 2 -- tiles per move (16px)
local debugText = ""

-- on-screen input state
local uiInput = {up=false, down=false, left=false, right=false}
local activeTouches = {} -- map touch id / "mouse" -> dir
local uiButtons = {} -- populated in love.load (screen pixels)
-- when a turn is made, block movement while that same input remains held
local inputBlockDir = nil
local inputBlockTimer = 0
local inputBlockDelay = 0.1 -- seconds to wait while holding after a turn before movement starts

local warps = {}
-- local warpDebug = "" -- unused (kept commented for safety)


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

-------------------------------------------------
-- MAP DATA
-------------------------------------------------

local mapWidth, mapHeight
local groundLayer = {}
local collisionLayer = {}

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

local animFrames = {
    down  = {1, 2, 3},
    up    = {4, 5, 6},
    left  = {7, 8},
    right = {9, 10}
}

-------------------------------------------------
-- CSV PARSER
-------------------------------------------------

-- CSV helper (currently unused, kept for future maps)
local function loadCSV(data)
    local t = {}
    for n in data:gmatch("(%d+)") do
        table.insert(t, tonumber(n))
    end
    return t
end

-------------------------------------------------
-- COLLISION (2x2 PLAYER)
-------------------------------------------------

local function isBlocked(tx, ty)
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
        if collisionLayer[idx] ~= 0 then
            return true
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

    -- Parse layers
    for layer in tmx:gmatch("<layer.->.-</layer>") do
        local name = layer:match('name="([^"]+)"')
        local data = layer:match("<data[^>]*>(.-)</data>")
        local csv = {}
        for n in data:gmatch("(%d+)") do table.insert(csv, tonumber(n)) end
        if name == "ground" then groundLayer = csv end
        if name == "collision" then collisionLayer = csv end
    end

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
    if spawnDir then player.dir = spawnDir end

    return tmx
end



-------------------------------------------------
-- LOVE.LOAD
-------------------------------------------------

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    local tmx = loadMap("tiled/inside.tmx", 8, 24, "down")

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

        if not isBlocked(nx, ny) then
            player.tx, player.ty = nx, ny
            player.startX, player.startY = player.x, player.y
            player.targetX = (nx - 1) * tileSize
            player.targetY = (ny - 1) * tileSize
            player.moving = true

            inputBlockDir = nil
            inputBlockTimer = 0

            local frames = animFrames[player.dir]
            if frames then player.animIndex = (#frames == 3) and frames[2] or frames[1] end
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

            local frames = animFrames[player.dir]
            if frames then
                player.animIndex = (#frames == 3) and frames[2] or frames[1]
                if #frames == 3 then player.stepLeft = not player.stepLeft end
            end
        else
            player.x = player.x + (dxp / dist) * player.speed * dt
            player.y = player.y + (dyp / dist) * player.speed * dt

            local progress = (total > 0) and (1 - dist / total) or 0
            local frames = animFrames[player.dir]

            if frames then
                if #frames == 3 then
                    if progress < 0.25 or progress >= 0.75 then
                        player.animIndex = frames[2]
                    else
                        player.animIndex = player.stepLeft and frames[1] or frames[3]
                    end
                else
                    player.animIndex = (progress < 0.5) and frames[1] or frames[2]
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
                break
            end
        end
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
    if key == "[" then
        player.speed = math.max(10, player.speed - 20)
        debugText = "speed: " .. tostring(player.speed)
    elseif key == "]" then
        player.speed = player.speed + 20
        debugText = "speed: " .. tostring(player.speed)
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

    love.graphics.draw(
        charSheet,
        charQuads[player.animIndex],
        math.floor(player.x + 0.5),
        math.floor(player.y + 0.5)
    )

    love.graphics.pop()

    -- debug text (unscaled)
    love.graphics.setColor(1,1,1)
    local infoText = debugText or ""
    if warpDebug and warpDebug ~= "" then
        if infoText ~= "" then infoText = infoText .. "\n" .. warpDebug else infoText = warpDebug end
    end
    love.graphics.print(infoText, 4, 4)
    love.graphics.setColor(1,1,1,1)

    -- draw on-screen D-pad (unscaled, screen pixels)
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
        end
    end
    love.graphics.setColor(1,1,1)
end

