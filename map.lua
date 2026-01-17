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
M.routes = {}  -- Route zones for encounter determination
M.currentPath = ""

-- Map cache to avoid reloading
M.mapCache = {}

-- Clear map cache (call when code changes require reloading maps)
function M.clearCache()
    M.mapCache = {}
end

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
-- Helper for water tile keys (faster than string.format)
local function waterKey(x, y)
    return x * 100000 + y  -- Numeric key is faster than string concat
end

function M.isBlocked(tx, ty, approachDx, approachDy)
    approachDx = approachDx or 0
    approachDy = approachDy or 0
    
    -- Cache frequently accessed values
    local width = M.width
    local height = M.height
    local collisionLayer = M.collisionLayer
    local collCount = #collisionLayer
    local tileProperties = M.tileProperties
    local unlockedWaterAll = M.unlockedWaterAll
    local unlockedWater = M.unlockedWater
    local decodeGid = M.decodeGid
    
    -- Check all 4 tiles in 2x2 area
    for dy = 0, 1 do
        for dx = 0, 1 do
            local x = tx + dx
            local y = ty + dy
            
            if x < 1 or y < 1 or x > width or y > height then
                return true
            end
            
            local idx = (y - 1) * width + x
            if idx < 1 or idx > collCount then
                return true
            end
            
            local rawgid = collisionLayer[idx]
            if rawgid and rawgid ~= 0 then
                local gid = decodeGid(rawgid)
                local props = tileProperties[gid]
                if props then
                    if props.blocked == true then
                        return true
                    end
                    -- water tiles are blocked until unlocked
                    if props.water then
                        local key = waterKey(x, y)
                        if not (unlockedWaterAll or unlockedWater[key]) then
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

-- Check if player position is on grass
function M.isPositionOnGrass(tx, ty)
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
                if props and props.grass then
                    return true
                end
            end
        end
    end
    return false
end

-- Get the route ID at a given pixel position
function M.getRouteAt(px, py)
    for _, route in ipairs(M.routes) do
        if px >= route.x and px <= route.x + route.width and
           py >= route.y and py <= route.y + route.height then
            return route.id
        end
    end
    return nil
end

-- Get encounter terrain type at position ("grass", "water", or nil)
function M.getEncounterTerrainAt(tx, ty)
    if M.isPositionOnGrass(tx, ty) then
        return "grass"
    elseif M.isPositionOnWater(tx, ty) then
        return "water"
    end
    return nil
end

-- Unlock water tile at position
function M.unlockWaterAt(tx, ty)
    local key = waterKey(tx, ty)
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
    -- Check if map is already cached
    if M.mapCache[path] then
        -- Restore from cache
        local cached = M.mapCache[path]
        M.currentPath = path
        M.width = cached.width
        M.height = cached.height
        M.groundLayer = cached.groundLayer
        M.collisionLayer = cached.collisionLayer
        M.tileProperties = cached.tileProperties
        M.warps = cached.warps
        M.interactables = cached.interactables
        M.routes = cached.routes or {}
        -- Note: tileset and quads are shared, no need to reload
        return
    end
    
    -- Not cached, load normally
    M.warps = {}
    M.interactables = {}
    M.routes = {}
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

    -- Get map tile size
    local tsTileW = tonumber(tmx:match('tilewidth="(%d+)"'))
    local tsTileH = tonumber(tmx:match('tileheight="(%d+)"'))
    M.tileSize = tsTileW
    M.tileW, M.tileH = tsTileW, tsTileH

    -- Parse all tilesets (both embedded and external) and build quads
    M.quads = {}
    local baseDir = path:match("(.*/)") or ""
    
    -- Parse embedded tilesets (those with <tileset>...</tileset>)
    for tilesetBlock in tmx:gmatch("<tileset%s+.-</tileset>") do
        local firstgid = tonumber(tilesetBlock:match('firstgid="(%d+)"')) or 1
        local imageSource = tilesetBlock:match('<image.-source="([^"]+)"')
        
        if imageSource then
            -- Fix path
            imageSource = imageSource:gsub('^%.%./', 'tiled/')
            imageSource = imageSource:gsub('^sprites/', 'tiled/sprites/')
            imageSource = imageSource:gsub('^%./', '')
            
            -- Load tileset image
            local tileset = love.graphics.newImage(imageSource)
            if not M.tileset then M.tileset = tileset end  -- Set first as main
            
            -- Build quads for this tileset
            local gid = firstgid
            for y = 0, tileset:getHeight() - M.tileH, M.tileH do
                for x = 0, tileset:getWidth() - M.tileW, M.tileW do
                    M.quads[gid] = {
                        quad = love.graphics.newQuad(x, y, M.tileW, M.tileH, tileset:getWidth(), tileset:getHeight()),
                        image = tileset
                    }
                    gid = gid + 1
                end
            end
        end
    end
    
    -- Parse external tilesets (self-closing tags with source="...")
    for tilesetRef in tmx:gmatch("<tileset%s+.-/>") do
        local firstgid = tonumber(tilesetRef:match('firstgid="(%d+)"')) or 1
        local source = tilesetRef:match('source="([^"]+)"')
        
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
                local imageSource = tilesetContent:match('<image.-source="([^"]+)"')
                if imageSource then
                    -- Fix path (relative to tiled/ directory)
                    imageSource = imageSource:gsub('^%.%./', 'tiled/')
                    imageSource = imageSource:gsub('^sprites/', 'tiled/sprites/')
                    imageSource = imageSource:gsub('^%./', 'tiled/')
                    
                    -- Load tileset image
                    local tileset = love.graphics.newImage(imageSource)
                    if not M.tileset then M.tileset = tileset end
                    
                    -- Build quads for this tileset
                    local gid = firstgid
                    for y = 0, tileset:getHeight() - M.tileH, M.tileH do
                        for x = 0, tileset:getWidth() - M.tileW, M.tileW do
                            M.quads[gid] = {
                                quad = love.graphics.newQuad(x, y, M.tileW, M.tileH, tileset:getWidth(), tileset:getHeight()),
                                image = tileset
                            }
                            gid = gid + 1
                        end
                    end
                end
            end
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
    -- First, remove self-closing objectgroups (empty layers) to prevent regex issues
    local tmxClean = tmx:gsub("<objectgroup[^>]*/>", "")
    for og in tmxClean:gmatch("<objectgroup.->.-</objectgroup>") do
        local layerName = og:match('name="([^"]+)"') or ""
        for obj in og:gmatch("<object.->.-</object>") do
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
            elseif layerName == "routes" then
                -- Parse route objects - store the id property directly for easy access
                local route = {
                    x = o.x,
                    y = o.y,
                    width = o.width,
                    height = o.height,
                    id = o.properties.id or o.properties.route_id or "unknown"
                }
                table.insert(M.routes, route)
            else
                table.insert(M.warps, o)
            end
        end
    end
    
    -- Cache the loaded map state
    M.mapCache[path] = {
        width = M.width,
        height = M.height,
        groundLayer = M.groundLayer,
        collisionLayer = M.collisionLayer,
        tileProperties = M.tileProperties,
        warps = M.warps,
        interactables = M.interactables,
        routes = M.routes
    }

    return tmx
end

-------------------------------------------------
-- DRAWING
-------------------------------------------------

-- Camera bounds for culling (set by draw function)
M.cullMinX = 0
M.cullMinY = 0
M.cullMaxX = 0
M.cullMaxY = 0

-- Set the visible area for tile culling (call before draw)
function M.setVisibleArea(camX, camY, viewW, viewH)
    -- Convert camera pixel coordinates to tile coordinates with padding
    M.cullMinX = math.max(1, math.floor(camX / M.tileSize))
    M.cullMinY = math.max(1, math.floor(camY / M.tileSize))
    M.cullMaxX = math.min(M.width, math.ceil((camX + viewW) / M.tileSize) + 1)
    M.cullMaxY = math.min(M.height, math.ceil((camY + viewH) / M.tileSize) + 1)
end

function M.draw()
    if not M.tileset then return end
    
    -- Use culling bounds if set, otherwise draw all (fallback)
    local minX = M.cullMinX > 0 and M.cullMinX or 1
    local minY = M.cullMinY > 0 and M.cullMinY or 1
    local maxX = M.cullMaxX > 0 and M.cullMaxX or M.width
    local maxY = M.cullMaxY > 0 and M.cullMaxY or M.height
    
    -- Cache frequently accessed values
    local groundLayer = M.groundLayer
    local quads = M.quads
    local tileset = M.tileset
    local tileW = M.tileW
    local tileH = M.tileH
    local tileSize = M.tileSize
    local width = M.width
    local decodeGid = M.decodeGid
    local halfW = tileW * 0.5
    local halfH = tileH * 0.5
    local pi = math.pi
    local draw = love.graphics.draw
    
    for y = minY, maxY do
        local rowOffset = (y - 1) * width
        local drawY = (y - 1) * tileSize + halfH
        
        for x = minX, maxX do
            local idx = rowOffset + x
            local rawgid = groundLayer[idx]
            if rawgid and rawgid > 0 then
                local gid, fh, fv, fd = decodeGid(rawgid)
                local quadData = quads[gid]
                if quadData then
                    local quad = quadData.quad or quadData
                    local image = quadData.image or tileset
                    
                    local sx, sy, rot = 1, 1, 0
                    if fd then
                        if fh and not fv then
                            rot = pi/2
                        elseif fh and fv then
                            rot = pi
                            sx = -1
                        elseif not fh and fv then
                            rot = -pi/2
                        else
                            sy = -1
                        end
                    else
                        if fh then sx = -1 end
                        if fv then sy = -1 end
                    end

                    local drawX = (x - 1) * tileSize + halfW
                    draw(image, quad, drawX, drawY, rot, sx, sy, halfW, halfH)
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
            local warpId = tonumber(w.properties.warp_id)
            local targetMap = w.properties.target_map
            local stepDir = w.properties.step_dir or "down"
            if warpId and targetMap then
                return {
                    warpId = warpId,
                    targetMap = targetMap,
                    stepDir = stepDir,
                    currentX = w.x,
                    currentY = w.y
                }
            end
        end
    end
    return nil
end

-- Find warp by ID in current map (excluding the warp at excludeX, excludeY)
function M.findWarpById(warpId, excludeX, excludeY)
    for _, w in ipairs(M.warps) do
        local id = tonumber(w.properties.warp_id)
        -- Skip if this is the same warp we're standing on
        if id == warpId and not (w.x == excludeX and w.y == excludeY) then
            -- Calculate tile position from pixel position
            local tx = math.floor(w.x / M.tileSize) + 1
            local ty = math.floor(w.y / M.tileSize) + 1
            local stepDir = w.properties.step_dir or "down"
            return tx, ty, stepDir
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
