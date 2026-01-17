-- main.lua
-- Main game loop - uses modular components for cleaner organization

local animation = require("animation")
local map = require("map")
local camera = require("camera")
local input = require("input")
local menu = require("menu")
local battle = require("battle")
local shop = require("shop")
local log = require("log")
local encounters = require("encounters")

-------------------------------------------------
-- CONSTANTS
-------------------------------------------------

local RENDER_SCALE = 3
local POV_W, POV_H = 160, 144
local PLAYER_STEP = 2  -- tiles per move (16px = 2 * 8px tiles)
local TARGET_FPS = 60  -- Target frame rate for frame limiting
local MIN_DT = 1 / TARGET_FPS  -- Minimum time between frames

-------------------------------------------------
-- FRAME TIMING
-------------------------------------------------

local frameAccumulator = 0  -- Accumulates time for frame limiting

-------------------------------------------------
-- UI STATE
-------------------------------------------------

local infoText = ""
local encounterText = ""

-------------------------------------------------
-- JSON UTILITIES
-------------------------------------------------

local function decode_json(json)
    if not json or json == "" then return nil end
    local s = json
    s = s:gsub("%f[%w]null%f[%W]", "nil")
    s = s:gsub("%f[%w]true%f[%W]", "true")
    s = s:gsub("%f[%w]false%f[%W]", "false")
    s = s:gsub('%[', '{')
    s = s:gsub('%]', '}')
    s = s:gsub('"([^"\n]-)"%s*:', '["%1"]=')
    local loader = loadstring or load
    local fn, err = loader("return " .. s)
    if not fn then return nil, err end
    local ok, res = pcall(fn)
    if not ok then return nil, res end
    return res
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
    jumping = false,
    dir = "down",
    animIndex = 2,
    stepLeft = true,
    moveProgress = 0,
    currentMap = "",
    party = {},
    box = {},  -- PC Box storage for Pokemon
    bag = nil,
    money = 3000,  -- Starting money
    -- Last heal location for whiteout
    lastHealLocation = {
        map = "tiled/inside.tmx",
        tx = 9,
        ty = 25,
        dir = "right"
    }
}

-- Pokemon module reference (loaded later in love.load)
local pokemonModule = nil

-- Initialize player's inventory (bag)
do
    local ok, itemModule = pcall(require, "item")
    if ok and itemModule and itemModule.Inventory then
        player.bag = itemModule.Inventory:new()
        -- Add one of each item
        for itemId, itemData in pairs(itemModule.ItemData) do
            player.bag:add(itemId, 1)
        end
    end
end

-------------------------------------------------
-- HELPER: Spawn player on map
-------------------------------------------------

local function spawnPlayer(spawnTX, spawnTY, spawnDir)
    player.tx = spawnTX
    player.ty = spawnTY
    player.x = (spawnTX - 1) * map.tileSize
    player.y = (spawnTY - 1) * map.tileSize
    player.targetX = player.x
    player.targetY = player.y
    player.moving = false
    player.jumping = false
    player.moveProgress = 0
    
    if spawnDir then
        player.dir = spawnDir
        player.animIndex = animation.getStandingFrame(player.dir)
        local frames = animation.frames[player.dir]
        if frames and #frames == 3 then
            player.stepLeft = true
        end
    end
end

-------------------------------------------------
-- HELPER: Load map and spawn player
-------------------------------------------------

local function loadMapAndSpawn(path, spawnTX, spawnTY, spawnDir)
    map.load(path, spawnTX, spawnTY, spawnDir)
    spawnPlayer(spawnTX, spawnTY, spawnDir)
    player.currentMap = map.currentPath
    
    -- If player spawns on water, unlock all water
    if map.isPositionOnWater(player.tx, player.ty) then
        map.unlockedWaterAll = true
        map.unlockedWater = {}
    end
end

-------------------------------------------------
-- HELPER: Check for wild encounter
-- Uses the routes layer + collision tiles (grass/water) + encounters module
-------------------------------------------------

local function checkEncounter()
    if battle.isActive and battle.isActive() then return end
    
    -- Get player center position for route detection
    local cx = player.x + player.size * 0.5
    local cy = player.y + player.size * 0.5
    
    -- Check what terrain type we're on (grass or water)
    local terrainType = map.getEncounterTerrainAt(player.tx, player.ty)
    if not terrainType then return end  -- Not on grass or water
    
    -- Get the route we're in
    local routeId = map.getRouteAt(cx, cy)
    if not routeId then return end  -- Not in any route zone
    
    -- Check if this route has encounters for this terrain type
    if not encounters.hasEncounters(routeId, terrainType) then return end
    
    -- Roll for encounter (10% chance)
    local roll = math.random(1, 100)
    if roll > 10 then return end
    
    -- Check for repel effect
    if player.repelSteps and player.repelSteps > 0 then
        local leadPokemon = player.party and player.party[1]
        local leadLevel = leadPokemon and leadPokemon.level or 1
        
        -- Get minimum encounter level for this route/terrain
        local minEncounterLevel = encounters.getMinEncounterLevel(routeId, terrainType)
        
        if minEncounterLevel < leadLevel then
            -- Repel prevents this encounter
            return
        end
    end
    
    -- Roll for the specific Pokemon encounter
    local encounterData = encounters.rollEncounter(routeId, terrainType)
    if not encounterData then return end
    
    -- Create the wild Pokemon
    local ok, pmod = pcall(require, "pokemon")
    if not ok or not pmod or not pmod.Pokemon then return end
    
    local wildPokemon = pmod.Pokemon:new(encounterData.species, encounterData.level)
    if wildPokemon then
        battle.start({wildPokemon}, player)
    end
end

-------------------------------------------------
-- HELPER: Check for warp
-------------------------------------------------

local function checkWarp()
    local cx = player.x + player.size * 0.5
    local cy = player.y + player.size * 0.5
    local warp = map.getWarpAt(cx, cy)
    
    if warp then
        local needsMapChange = (warp.targetMap ~= player.currentMap)
        
        if needsMapChange then
            -- Load the target map
            map.load(warp.targetMap)
            player.currentMap = warp.targetMap
        end
        
        -- Find the destination warp by ID (excluding current warp position)
        local destTX, destTY, stepDir = map.findWarpById(warp.warpId, warp.currentX, warp.currentY)
        
        if destTX and destTY then
            -- Spawn player at destination warp (don't change direction if stepDir is "none")
            spawnPlayer(destTX, destTY, stepDir ~= "none" and stepDir or nil)
            
            -- Automatically step off the warp in the step direction (unless stepDir is "none")
            if stepDir ~= "none" then
                local stepAmount = PLAYER_STEP
                if stepDir == "up" then
                    player.ty = player.ty - stepAmount
                    player.targetY = (player.ty - 1) * map.tileSize
                elseif stepDir == "down" then
                    player.ty = player.ty + stepAmount
                    player.targetY = (player.ty - 1) * map.tileSize
                elseif stepDir == "left" then
                    player.tx = player.tx - stepAmount
                    player.targetX = (player.tx - 1) * map.tileSize
                elseif stepDir == "right" then
                    player.tx = player.tx + stepAmount
                    player.targetX = (player.tx - 1) * map.tileSize
                end
                
                -- Update player position and set moving state
                player.moving = true
                player.moveProgress = 0
                player.startX = player.x
                player.startY = player.y
            else
                -- For "none", ensure standing frame is set for current direction
                player.animIndex = animation.getStandingFrame(player.dir)
            end
        end
    end
end

-------------------------------------------------
-- HELPER: Update encounter text display
-------------------------------------------------

local function updateEncounterText()
    local cx = player.x + player.size * 0.5
    local cy = player.y + player.size * 0.5
    
    -- Get terrain type and route
    local terrainType = map.getEncounterTerrainAt(player.tx, player.ty)
    local routeId = map.getRouteAt(cx, cy)
    
    encounterText = ""
    
    if routeId and terrainType then
        encounterText = "Route: " .. routeId .. " (" .. terrainType .. ")"
    elseif routeId then
        encounterText = "Route: " .. routeId
    elseif terrainType then
        encounterText = "Terrain: " .. terrainType
    end
end

-------------------------------------------------
-- LOVE.LOAD
-------------------------------------------------

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    
    -- Clear map cache to ensure fresh loading after code changes
    map.clearCache()
    
    -- Initialize Pokemon species from JSON (must be done after love is initialized)
    local ok, pmod = pcall(require, "pokemon")
    if ok and pmod then
        pokemonModule = pmod
        if pmod.init then
            pmod.init()  -- Load species data from pokemon_data.json
        end
        -- Initialize player's Pokemon party
        if pmod.Pokemon then
            table.insert(player.party, pmod.Pokemon:new("pikachu", 5))
            table.insert(player.party, pmod.Pokemon:new("squirtle", 5))
        end
    end
    
    -- Set camera viewport
    camera.viewportW = POV_W
    camera.viewportH = POV_H
    
    -- Calculate window size based on control mode
    -- Default to touchscreen mode with control panel below game
    local gameW = POV_W * RENDER_SCALE
    local gameH = POV_H * RENDER_SCALE
    
    -- Configure input module dimensions
    input.gameScreenWidth = gameW
    input.gameScreenHeight = gameH
    input.controlPanelHeight = 180  -- Height of control panel below game
    
    -- Set window size (touchscreen mode is default, includes control panel)
    if input.controlMode == "touchscreen" then
        love.window.setMode(gameW, gameH + input.controlPanelHeight)
    else
        love.window.setMode(gameW, gameH)
    end
    
    -- Load animation sprites
    animation.load()
    
    -- Initialize input buttons
    input.init()
    
    -- Default spawn
    local defaultMapPath = "tiled/johto.tmx"
    local defaultSpawnTX, defaultSpawnTY, defaultSpawnDir = 513, 953, "right"
    
    -- Load default map
    loadMapAndSpawn(defaultMapPath, defaultSpawnTX, defaultSpawnTY, defaultSpawnDir)
    
    -- Try to load saved player state
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
        -- Merge saved fields into player
        for k, v in pairs(saved) do
            player[k] = v
        end
        
        -- Reconstruct Pokemon instances in party
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
        
        -- Reconstruct Pokemon instances in box
        if player.box and #player.box > 0 then
            local ok, pmod = pcall(require, "pokemon")
            if ok and pmod and pmod.Pokemon then
                for i, pokemonData in ipairs(player.box) do
                    if type(pokemonData) == "table" and pokemonData.speciesId then
                        player.box[i] = pmod.Pokemon.fromSavedData(pokemonData)
                    end
                end
            end
        end
        
        -- Reconstruct Inventory instance
        if player.bag then
            local ok, itemModule = pcall(require, "item")
            if ok and itemModule and itemModule.Inventory then
                local newBag = itemModule.Inventory:new()
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
        
        -- Load saved map
        if player.currentMap and player.currentMap ~= "" then
            local tx = player.tx or defaultSpawnTX
            local ty = player.ty or defaultSpawnTY
            local dir = player.dir or defaultSpawnDir
            loadMapAndSpawn(player.currentMap, tx, ty, dir)
        end
        
        infoText = "Save loaded"
    else
        -- First load: give starter items
        if player.bag then
            player.bag:add("potion", 5)
            player.bag:add("pokeball", 10)
        end
    end
    
    -- Expose player to menu
    menu.player = player
    
    -- Set up whiteout callback for battle
    battle.setWhiteoutCallback(function(playerRef)
        -- Teleport player to last heal location
        if playerRef.lastHealLocation then
            local loc = playerRef.lastHealLocation
            loadMapAndSpawn(loc.map, loc.tx, loc.ty, loc.dir)
            infoText = "You woke up at the last place you healed..."
        end
    end)
    
    -- Initialize camera
    camera.init(
        player.x + player.size / 2,
        player.y + player.size / 2,
        map.width, map.height, map.tileSize
    )
end

-------------------------------------------------
-- LOVE.UPDATE
-------------------------------------------------

function love.update(dt)
    -- Frame rate limiting: if vsync isn't working, sleep to reduce CPU usage
    -- This is a soft limit that helps reduce CPU when the system allows higher than 60fps
    local sleepTime = MIN_DT - dt
    if sleepTime > 0.001 then
        love.timer.sleep(sleepTime * 0.9)  -- Sleep for most of the remaining time
    end
    
    -- Clamp dt to prevent huge jumps if game was paused
    if dt > 0.1 then dt = 0.1 end
    
    -- Update menu, battle, and shop
    if menu and menu.update then menu.update(dt) end
    if battle and battle.update then battle.update(dt) end
    if shop and shop.update then shop.update(dt) end
    -- Always update input (cooldown timer, etc.) so it decrements while moving or in menus
    if input.update then input.update(dt) end
    
    -- Skip player updates if menu, battle, or shop is active
    if (menu and menu.isOpen and menu.isOpen()) or (battle and battle.isActive and battle.isActive()) or (shop and shop.isOpen and shop.isOpen()) then
        return
    end
    
    local requestedDir, dx, dy = input.getDirection()
    
    -- Handle rotate-first behavior when not moving
    if not player.moving then
        if requestedDir and requestedDir ~= player.dir then
            player.dir = requestedDir
            player.animIndex = animation.getStandingFrame(player.dir)
            input.blockDir = requestedDir
            input.blockTimer = 0
            dx, dy = 0, 0
        end
        
        input.updateBlocking(dt, requestedDir, player.dir, player.moving)
    end
    
    -- Start movement
    if not player.moving and (dx ~= 0 or dy ~= 0) and not input.shouldBlockMovement(requestedDir) then
        local nx = player.tx + dx * PLAYER_STEP
        local ny = player.ty + dy * PLAYER_STEP
        
        -- Check for jump tiles
        local jumped = false
        if map.tileHasJumpAt(nx, ny, dx, dy) then
            jumped = true
            nx = nx + dx
            ny = ny + dy
            -- Skip consecutive jump tiles
            local tries = 0
            while map.tileHasJumpAt(nx, ny, dx, dy) and tries < 4 do
                nx = nx + dx
                ny = ny + dy
                tries = tries + 1
            end
        end
        
        -- Check if target is walkable
        if not map.isBlocked(nx, ny, dx, dy) then
            player.tx, player.ty = nx, ny
            player.startX, player.startY = player.x, player.y
            player.targetX = (nx - 1) * map.tileSize
            player.targetY = (ny - 1) * map.tileSize
            player.moving = true
            player.jumping = jumped and (dx ~= 0 or dy > 0)
            player.moveProgress = 0
            
            input.clearBlock()
            
            -- Set initial animation frame
            if player.jumping then
                player.animIndex = animation.getJumpingFrame(player.dir)
            else
                player.animIndex = animation.getStandingFrame(player.dir)
            end
        end
    end
    
    -- Update movement
    if player.moving then
        local dxp = player.targetX - player.x
        local dyp = player.targetY - player.y
        local dist = math.sqrt(dxp*dxp + dyp*dyp)
        local total = math.sqrt((player.targetX-player.startX)^2 + (player.targetY-player.startY)^2)
        
        if dist < 1 then
            -- Arrived at destination
            player.x, player.y = player.targetX, player.targetY
            player.moving = false
            player.jumping = false
            player.moveProgress = 0
            
            player.animIndex = animation.getStandingFrame(player.dir)
            animation.onStepComplete(player)
            
            -- Decrement repel steps
            if player.repelSteps and player.repelSteps > 0 then
                player.repelSteps = player.repelSteps - 1
                if player.repelSteps <= 0 then
                    player.repelSteps = nil
                    -- Could show message "Repel's effect wore off!"
                end
            end
            
            -- Check for encounters and warps after completing step
            checkEncounter()
            checkWarp()
        else
            -- Continue moving
            player.x = player.x + (dxp / dist) * player.speed * dt
            player.y = player.y + (dyp / dist) * player.speed * dt
            
            player.moveProgress = (total > 0) and (1 - dist / total) or 0
            
            -- Update animation
            if player.jumping then
                player.animIndex = animation.getJumpingFrame(player.dir)
            else
                player.animIndex = animation.getWalkingFrame(player.dir, player.moveProgress, player.stepLeft)
            end
        end
    end
    
    -- Update encounter text
    updateEncounterText()
    
    -- Re-lock water if player left water
    if not player.moving and map.unlockedWaterAll and not map.isPositionOnWater(player.tx, player.ty) then
        map.relockWater()
    end
    
    -- Update camera
    camera.update(
        player.x + player.size / 2,
        player.y + player.size / 2,
        map.width, map.height, map.tileSize
    )
end

-------------------------------------------------
-- LOVE.KEYPRESSED
-------------------------------------------------

function love.keypressed(key)
    -- Route to menu if open
    if menu and menu.isOpen and menu.isOpen() then
        if menu.keypressed then menu.keypressed(key) end
        return
    end
    
    -- Route to battle if active
    if battle and battle.isActive and battle.isActive() then
        if battle.keypressed then battle.keypressed(key) end
        return
    end
    
    -- Route to shop if open
    if shop and shop.isOpen and shop.isOpen() then
        if shop.keypressed then shop.keypressed(key) end
        return
    end
    
    -- Debug speed controls
    if key == "[" then
        player.speed = math.max(10, player.speed - 20)
        infoText = "speed: " .. tostring(player.speed)
    elseif key == "]" then
        player.speed = player.speed + 20
        infoText = "speed: " .. tostring(player.speed)
    
    -- Debug battle toggle (spawns exp_dummy for testing) - wild battle
    elseif key == "b" or key == "B" then
        if battle and battle.isActive and battle.isActive() then
            if battle["end"] then battle["end"]() end
        elseif battle and battle.startWildBattle then
            -- Create exp_dummy Pokemon for testing (gives lots of EXP)
            local ok, pmod = pcall(require, "pokemon")
            if ok and pmod and pmod.Pokemon then
                local testEnemy = pmod.Pokemon:new("exp_dummy", 5)
                battle.startWildBattle(testEnemy, player)
            end
        end
    
    -- Debug trainer battle toggle (press T to start a trainer battle)
    elseif key == "t" or key == "T" then
        if battle and battle.isActive and battle.isActive() then
            -- Don't allow ending trainer battles with T
            if not battle.isTrainerBattle then
                if battle["end"] then battle["end"]() end
            end
        elseif battle and battle.startTrainerBattle then
            -- Start a test trainer battle
            battle.startTrainerBattle("test_trainer", player)
            infoText = "Trainer battle started!"
        end
    
    -- Debug shop toggle (press S to open test shop)
    elseif key == "s" or key == "S" then
        if shop and shop.isOpen and shop.isOpen() then
            -- Don't force close - let shop handle it
        elseif shop and shop.openShop then
            shop.openShop("test_shop", player)
            infoText = "Shop opened!"
        end
    
    -- Interact / talk
    elseif key == "z" or key == "Z" then
        local dx, dy = 0, 0
        if player.dir == "up" then dy = -1 end
        if player.dir == "down" then dy = 1 end
        if player.dir == "left" then dx = -1 end
        if player.dir == "right" then dx = 1 end
        
        local tx = player.tx + dx * PLAYER_STEP
        local ty = player.ty + dy * PLAYER_STEP
        
        -- Calculate the pixel position the player is looking at (center of the target 2x2 tile area)
        local lookAtPx = (tx - 1) * map.tileSize + map.tileSize  -- Center of 2x2 area
        local lookAtPy = (ty - 1) * map.tileSize + map.tileSize
        
        -- Check for interactable objects first
        local interactable = map.getInteractableAt(lookAtPx, lookAtPy)
        if interactable and interactable.action then
            local action = interactable.action
            
            if action == "heal" then
                -- Save this location as the last heal point for whiteout
                player.lastHealLocation = {
                    map = player.currentMap,
                    tx = player.tx,
                    ty = player.ty,
                    dir = player.dir
                }
                
                -- Heal all Pokemon in the party
                for _, pokemon in ipairs(player.party) do
                    if pokemon and pokemon.stats and pokemon.stats.hp then
                        pokemon.currentHP = pokemon.stats.hp
                        -- Clear all status conditions (poison, burn, paralysis, sleep, freeze)
                        pokemon.status = nil
                        -- Clear volatile status conditions if they exist
                        pokemon.confused = nil
                        pokemon.confusedTurns = nil
                        pokemon.seeded = nil
                        pokemon.infatuated = nil
                        pokemon.trapped = nil
                        pokemon.curse = nil
                        pokemon.nightmare = nil
                        pokemon.perishCount = nil
                        -- Restore PP for all moves
                        if pokemon.moves then
                            for _, move in ipairs(pokemon.moves) do
                                if move and move.maxPP then
                                    move.pp = move.maxPP
                                end
                            end
                        end
                        -- Also restore PP through move instances if they exist
                        if pokemon._move_instances then
                            for _, moveInst in ipairs(pokemon._move_instances) do
                                if type(moveInst) == "table" and moveInst.maxPP then
                                    moveInst.pp = moveInst.maxPP
                                end
                            end
                        end
                    end
                end
                infoText = "Your Pokemon have been healed!"
                
            elseif action == "box" then
                -- Open the PC Box menu
                if menu and menu.openBoxMenu then
                    menu.openBoxMenu()
                    infoText = "Accessing PC Box..."
                else
                    infoText = "PC Box not available"
                end
                
            elseif action == "trainer" then
                -- Start a trainer battle
                local trainerId = interactable.id
                if trainerId and trainerId ~= "" then
                    if battle and battle.startTrainerBattle then
                        battle.startTrainerBattle(trainerId, player)
                        infoText = "Trainer battle started!"
                    else
                        infoText = "Battle system not available"
                    end
                else
                    infoText = "Invalid trainer ID"
                end
                
            elseif action == "shop" then
                -- Open a shop
                local shopId = interactable.id
                if shopId and shopId ~= "" then
                    if shop and shop.openShop then
                        shop.openShop(shopId, player)
                        infoText = "Welcome to the shop!"
                    else
                        infoText = "Shop system not available"
                    end
                else
                    infoText = "Invalid shop ID"
                end
            else
                infoText = "Unknown action: " .. tostring(action)
            end
            return  -- Handled interactable, don't check water
        end
        
        -- Check for water interaction
        if tx >= 1 and ty >= 1 and tx <= map.width and ty <= map.height then
            local idx = (ty - 1) * map.width + tx
            local raw = map.collisionLayer[idx]
            if raw and raw ~= 0 then
                local gid = map.decodeGid(raw)
                local props = map.tileProperties[gid]
                if props and props.water then
                    map.unlockWaterAt(tx, ty)
                    infoText = "Water unlocked"
                    
                    -- Step forward into water
                    if not player.moving and not map.isBlocked(tx, ty, dx, dy) then
                        player.tx, player.ty = tx, ty
                        player.startX, player.startY = player.x, player.y
                        player.targetX = (tx - 1) * map.tileSize
                        player.targetY = (ty - 1) * map.tileSize
                        player.moving = true
                        player.jumping = false
                        player.moveProgress = 0
                        input.clearBlock()
                        player.animIndex = animation.getStandingFrame(player.dir)
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
    
    -- Open menu
    elseif key == "space" then
        if menu and menu.toggle then menu.toggle() end
    end
end

-------------------------------------------------
-- MOUSE / TOUCH INPUT
-------------------------------------------------

local function getInputCallbacks()
    return {
        up = function()
            if menu and menu.isOpen and menu.isOpen() then
                if menu.keypressed then menu.keypressed("up") end
            elseif battle and battle.isActive and battle.isActive() then
                if battle.keypressed then battle.keypressed("up") end
            elseif shop and shop.isOpen and shop.isOpen() then
                if shop.keypressed then shop.keypressed("up") end
            end
        end,
        down = function()
            if menu and menu.isOpen and menu.isOpen() then
                if menu.keypressed then menu.keypressed("down") end
            elseif battle and battle.isActive and battle.isActive() then
                if battle.keypressed then battle.keypressed("down") end
            elseif shop and shop.isOpen and shop.isOpen() then
                if shop.keypressed then shop.keypressed("down") end
            end
        end,
        left = function()
            if menu and menu.isOpen and menu.isOpen() then
                if menu.keypressed then menu.keypressed("left") end
            elseif battle and battle.isActive and battle.isActive() then
                if battle.keypressed then battle.keypressed("left") end
            elseif shop and shop.isOpen and shop.isOpen() then
                if shop.keypressed then shop.keypressed("left") end
            end
        end,
        right = function()
            if menu and menu.isOpen and menu.isOpen() then
                if menu.keypressed then menu.keypressed("right") end
            elseif battle and battle.isActive and battle.isActive() then
                if battle.keypressed then battle.keypressed("right") end
            elseif shop and shop.isOpen and shop.isOpen() then
                if shop.keypressed then shop.keypressed("right") end
            end
        end,
        a = function()
            if menu and menu.isOpen and menu.isOpen() then
                if menu.keypressed then menu.keypressed("return") end
            elseif battle and battle.isActive and battle.isActive() then
                if battle.keypressed then battle.keypressed("z") end
            elseif shop and shop.isOpen and shop.isOpen() then
                if shop.keypressed then shop.keypressed("return") end
            else
                love.keypressed("z")
            end
        end,
        b = function()
            -- B button acts as back/cancel
            if menu and menu.isOpen and menu.isOpen() then
                if menu.keypressed then menu.keypressed("space") end
            elseif battle and battle.isActive and battle.isActive() then
                if battle.keypressed then battle.keypressed("space") end
            elseif shop and shop.isOpen and shop.isOpen() then
                if shop.keypressed then shop.keypressed("space") end
            else
                love.keypressed("x")
            end
        end,
        start = function()
            if menu and menu.isOpen and menu.isOpen() then
                if menu.keypressed then menu.keypressed("space") end
            elseif battle and battle.isActive and battle.isActive() then
                if battle.keypressed then battle.keypressed("space") end
            elseif shop and shop.isOpen and shop.isOpen() then
                if shop.keypressed then shop.keypressed("space") end
            else
                love.keypressed("space")
            end
        end
    }
end

function love.mousepressed(x, y, button)
    input.mousepressed(x, y, button, getInputCallbacks())
end

function love.mousereleased(x, y, button)
    input.mousereleased(x, y, button)
end

function love.touchpressed(id, x, y)
    input.touchpressed(id, x, y, getInputCallbacks())
end

function love.touchreleased(id, x, y)
    input.touchreleased(id, x, y)
end

-------------------------------------------------
-- LOVE.DRAW
-------------------------------------------------

function love.draw()
    -- Set visible area for tile culling before drawing
    map.setVisibleArea(camera.x, camera.y, camera.viewportW, camera.viewportH)
    
    -- Draw world (scaled)
    camera.attach(RENDER_SCALE)
    map.draw()
    animation.drawCharacter(player, map.isPositionOnWater(player.tx, player.ty))
    camera.detach()
    
    -- Draw debug text (unscaled)
    local displayText = ""
    if encounterText and encounterText ~= "" then
        displayText = encounterText
    end
    if infoText and infoText ~= "" then
        if displayText ~= "" then
            displayText = displayText .. "\n" .. infoText
        else
            displayText = infoText
        end
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
    
    -- Draw menu overlay
    if menu and menu.draw then menu.draw() end
    
    -- Draw battle overlay
    if battle and battle.draw then battle.draw() end
    
    -- Draw shop overlay
    if shop and shop.draw then shop.draw() end
    
    -- Draw on-screen buttons
    input.drawButtons()
end
