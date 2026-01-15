-- map.lua
-- Map loading, tile management, collision detection, and warps

local M = {}

-------------------------------------------------
-- MAP STATE
-------------------------------------------------

M.width = 0
M.height = 0
M.groundLayer = {}
M.collisionLayer = {}
M.tileProperties = {}
M.warps = {}
M.interactables = {}  -- Interactable objects (heal, box, trainer, etc.)
M.currentPath = ""

-- Tileset data
M.tileset = nil
M.quads = {}
M.tileW = 8
M.tileH = 8
M.tileSize = 8

-- Water unlock tracking
M.unlockedWater = {}
M.unlockedWaterAll = false

-------------------------------------------------
-- TILED FLIP FLAGS
-------------------------------------------------

local FLIPPED_HORIZONTALLY_FLAG = 0x80000000
local FLIPPED_VERTICALLY_FLAG   = 0x40000000
local FLIPPED_DIAGONALLY_FLAG   = 0x20000000

function M.decodeGid(gid)
    local fh, fv, fd = false, false, false
    if gid >= FLIPPED_HORIZONTALLY_FLAG then gid = gid - FLIPPED_HORIZONTALLY_FLAG; fh = true end
    if gid >= FLIPPED_VERTICALLY_FLAG   then gid = gid - FLIPPED_VERTICALLY_FLAG;   fv = true end
    if gid >= FLIPPED_DIAGONALLY_FLAG   then gid = gid - FLIPPED_DIAGONALLY_FLAG;   fd = true end
    return gid, fh, fv, fd
end

-------------------------------------------------
-- COLLISION DETECTION
-------------------------------------------------

-- Check if a 2x2 tile area is blocked
function M.isBlocked(tx, ty, approachDx, approachDy)
    approachDx = approachDx or 0
    approachDy = approachDy or 0
    local checks = {
        {tx, ty}, {tx + 1, ty},
        {tx, ty + 1}, {tx + 1, ty + 1}
    }

    for _, c in ipairs(checks) do
        local x, y = c[1], c[2]
        if x < 1 or y < 1 or x > M.width or y > M.height then
            return true
        end
        local idx = (y - 1) * M.width + x
        local collCount = #M.collisionLayer
        local rawgid = M.collisionLayer[idx]
        
        if idx < 1 or idx > collCount then
            return true
        end

        if rawgid and rawgid ~= 0 then
            local gid = M.decodeGid(rawgid)
            local props = M.tileProperties[gid]
            if props then
                if props.blocked == true then
                    return true
                end
                -- water tiles are blocked until unlocked
                if props.water then
                    local key = string.format("%d,%d", x, y)
                    if not (M.unlockedWaterAll or M.unlockedWater[key]) then
                        return true
                    end
                end
                -- jump tiles restrict approach direction
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

-- Check if any tile in 2x2 area has a jump property
function M.tileHasJumpAt(tx, ty, approachDx, approachDy)
    approachDx = approachDx or 0
    approachDy = approachDy or 0
    local checks = {
        {tx, ty}, {tx + 1, ty},
        {tx, ty + 1}, {tx + 1, ty + 1}
    }
    for _, c in ipairs(checks) do
        local x, y = c[1], c[2]
        if x >= 1 and y >= 1 and x <= M.width and y <= M.height then
            local idx = (y - 1) * M.width + x
            local rawgid = M.collisionLayer[idx]
            if rawgid and rawgid ~= 0 then
                local gid = M.decodeGid(rawgid)
                local props = M.tileProperties[gid]
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

-- Check if player position is on water
function M.isPositionOnWater(tx, ty)
    local checks = {
        {tx, ty}, {tx + 1, ty},
        {tx, ty + 1}, {tx + 1, ty + 1}
    }
    for _, c in ipairs(checks) do
        local x, y = c[1], c[2]
        if x >= 1 and y >= 1 and x <= M.width and y <= M.height then
            local idx = (y - 1) * M.width + x
            local raw = M.collisionLayer[idx]
            if raw and raw ~= 0 then
                local gid = M.decodeGid(raw)
                local props = M.tileProperties[gid]
                if props and props.water then
                    return true
                end
            end
        end
    end
    return false
end

-- Unlock water tile at position
function M.unlockWaterAt(tx, ty)
    local key = string.format("%d,%d", tx, ty)
    M.unlockedWater[key] = true
    M.unlockedWaterAll = true
end

-- Re-lock all water tiles
function M.relockWater()
    M.unlockedWaterAll = false
    M.unlockedWater = {}
end

-------------------------------------------------
-- MAP LOADING
-------------------------------------------------

local function tryRead(pathCandidates)
    for _, p in ipairs(pathCandidates) do
        local ok, data = pcall(love.filesystem.read, p)
        if ok and data and data ~= "" then return data, p end
    end
    return nil, nil
end

function M.load(path, spawnTX, spawnTY, spawnDir)
    M.warps = {}
    M.interactables = {}
    M.groundLayer = {}
    M.collisionLayer = {}
    M.unlockedWater = {}
    M.unlockedWaterAll = false

    -- Read the TMX
    local tmx = love.filesystem.read(path)
    M.currentPath = path

    -- Map size
    M.width  = tonumber(tmx:match('width="(%d+)"'))
    M.height = tonumber(tmx:match('height="(%d+)"'))

    -- Tileset image
    local tilesetImage = tmx:match('<image.-source="([^"]+)"')
    if tilesetImage then
        tilesetImage = tilesetImage:gsub('^%.%./', 'tiled/')
        tilesetImage = tilesetImage:gsub('^sprites/', 'tiled/sprites/')
        tilesetImage = tilesetImage:gsub('^%./', '')
        M.tileset = love.graphics.newImage(tilesetImage)
    end

    -- Tileset tile size
    local tsTileW = tonumber(tmx:match('tilewidth="(%d+)"'))
    local tsTileH = tonumber(tmx:match('tileheight="(%d+)"'))
    M.tileSize = tsTileW
    M.tileW, M.tileH = tsTileW, tsTileH

    -- Build quads
    M.quads = {}
    local gid = 1
    for y = 0, M.tileset:getHeight() - M.tileH, M.tileH do
        for x = 0, M.tileset:getWidth() - M.tileW, M.tileW do
            M.quads[gid] = love.graphics.newQuad(x, y, M.tileW, M.tileH,
                M.tileset:getWidth(), M.tileset:getHeight())
            gid = gid + 1
        end
    end

    -- Parse tileset tile property definitions
    M.tileProperties = {}
    local baseDir = path:match("(.*/)") or ""

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
                    local tileGid = firstgid + id
                    local props = {}
                    for k,v in tileBlock:gmatch('<property[^>]-name="([^\"]+)"[^>]-value="([^\"]*)"') do
                        local val = v
                        if v == "true" then val = true elseif v == "false" then val = false end
                        props[k] = val
                    end
                    if next(props) then M.tileProperties[tileGid] = props end
                end
            end
        end
    end

    -- Also handle embedded tileset blocks
    for tilesetBlock in tmx:gmatch("<tileset.->.-</tileset>") do
        local firstgid = tonumber(tilesetBlock:match('firstgid="(%d+)"')) or 1
        for tileBlock in tilesetBlock:gmatch("<tile.->.-</tile>") do
            local id = tonumber(tileBlock:match('id="(%d+)"')) or 0
            local tileGid = firstgid + id
            local props = {}
            for k,v in tileBlock:gmatch('<property[^>]-name="([^\"]+)"[^>]-value="([^\"]*)"') do
                local val = v
                if v == "true" then val = true elseif v == "false" then val = false end
                props[k] = val
            end
            if next(props) then M.tileProperties[tileGid] = props end
        end
    end

    -- Parse layers
    for layer in tmx:gmatch("<layer.->.-</layer>") do
        local name = layer:match('name="([^"]+)"')
        local data = layer:match("<data[^>]*>(.-)</data>")
        local csv = {}
        for n in data:gmatch("(%d+)") do table.insert(csv, tonumber(n)) end
        if name == "ground" then M.groundLayer = csv end
        if name == "collision" then M.collisionLayer = csv end
    end

    -- Parse warp and interactable objects
    for og in tmx:gmatch("<objectgroup.->.-</objectgroup>") do
        local layerName = og:match('name="([^"]+)"') or ""
        for obj in og:gmatch("<object.-</object>") do
            local o = {
                x = tonumber(obj:match('x="([^"]+)"')) or 0,
                y = tonumber(obj:match('y="([^"]+)"')) or 0,
                width  = tonumber(obj:match('width="([^"]+)"')) or 0,
                height = tonumber(obj:match('height="([^"]+)"')) or 0,
                properties = {}
            }
            for k,v in obj:gmatch('<property[^>]-name="([^"]+)"[^>]-value="([^"]*)"') do
                o.properties[k] = v
            end
            -- Route to appropriate table based on layer name
            if layerName == "interactable" then
                table.insert(M.interactables, o)
            else
                table.insert(M.warps, o)
            end
        end
    end

    return tmx
end

-------------------------------------------------
-- DRAWING
-------------------------------------------------

function M.draw()
    if not M.tileset then return end
    
    for y = 1, M.height do
        for x = 1, M.width do
            local idx = (y - 1) * M.width + x
            local rawgid = M.groundLayer[idx]
            if rawgid and rawgid > 0 then
                local gid, fh, fv, fd = M.decodeGid(rawgid)
                local quad = M.quads[gid]
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

                    local ox = M.tileW * 0.5
                    local oy = M.tileH * 0.5
                    local drawX = (x - 1) * M.tileSize + ox
                    local drawY = (y - 1) * M.tileSize + oy

                    love.graphics.draw(M.tileset, quad, drawX, drawY, rot, sx, sy, ox, oy)
                end
            end
        end
    end
end

-------------------------------------------------
-- ENCOUNTER CHECKING
-------------------------------------------------

-- Check if position is in a grass encounter zone and return encounter info
function M.getEncounterAt(px, py)
    for _, w in ipairs(M.warps) do
        if w and w.properties then
            local gv = w.properties.grass
            local isGrass = (gv == true) or (gv == "true") or (gv == "1")
            if isGrass then
                if px >= w.x and px <= w.x + w.width and py >= w.y and py <= w.y + w.height then
                    return w
                end
            end
        end
    end
    return nil
end

-- Get warp at position
function M.getWarpAt(px, py)
    for _, w in ipairs(M.warps) do
        if px >= w.x and px <= w.x + w.width and py >= w.y and py <= w.y + w.height then
            local targetMap = w.properties.target_map
            local tx = tonumber(w.properties.target_x)
            local ty = tonumber(w.properties.target_y)
            local dir = w.properties.target_dir
            if targetMap and tx and ty then
                return {
                    targetMap = targetMap,
                    targetX = tx,
                    targetY = ty,
                    targetDir = dir
                }
            end
        end
    end
    return nil
end

-- Get interactable object at position (pixel coordinates)
function M.getInteractableAt(px, py)
    for _, obj in ipairs(M.interactables) do
        if px >= obj.x and px <= obj.x + obj.width and py >= obj.y and py <= obj.y + obj.height then
            return {
                action = obj.properties.action,
                id = obj.properties.id,  -- For trainers
                properties = obj.properties
            }
        end
    end
    return nil
end

return M
