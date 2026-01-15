-- menu.lua
local M = {}
local UI = require("ui")

-- JSON encoder
local function is_array(tbl)
    if type(tbl) ~= "table" then return false end
    local i = 0
    for _ in pairs(tbl) do
        i = i + 1
        if tbl[i] == nil then return false end
    end
    return true
end

local function escape_str(s)
    return s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
end

local function encode_json(obj)
    if obj == nil then
        return "null"
    elseif type(obj) == "boolean" then
        return obj and "true" or "false"
    elseif type(obj) == "number" then
        return tostring(obj)
    elseif type(obj) == "string" then
        return '"' .. escape_str(obj) .. '"'
    elseif type(obj) == "table" then
        if is_array(obj) then
            local parts = {}
            for i, v in ipairs(obj) do
                table.insert(parts, encode_json(v))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(obj) do
                -- Skip fields starting with underscore (runtime-only fields like _move_instances)
                -- and skip functions which can't be serialized
                if type(k) == "string" and not k:match("^_") and type(v) ~= "function" then
                    table.insert(parts, '"' .. escape_str(k) .. '":' .. encode_json(v))
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

M.open = false
M.options = {"Pokemon", "Bag", "Box", "Heal", "Controls", "Save", "Exit"}
M.selected = 1
M.showPokemon = false

-- Control mode settings submenu state
M.showControlSettings = false
M.controlSettingsSelected = 1
M.controlSettingsOptions = {"Touchscreen", "Handheld", "Back"}

-- Sprite cache for Pokemon images
local spriteCache = {}

-- Helper function to load and cache a Pokemon sprite
local function loadSprite(spritePath)
    if not spritePath then return nil end
    if spriteCache[spritePath] then return spriteCache[spritePath] end
    
    local success, image = pcall(love.graphics.newImage, spritePath)
    if success and image then
        spriteCache[spritePath] = image
        return image
    end
    return nil
end

-- Helper function to draw a Pokemon sprite in a box
local function drawPokemonSprite(pokemon, x, y, width, height, isBackSprite)
    if not pokemon or not pokemon.species or not pokemon.species.sprite then
        return
    end
    
    local spritePath = isBackSprite and pokemon.species.sprite.back or pokemon.species.sprite.front
    local image = loadSprite(spritePath)
    
    if image then
        local imgWidth = image:getWidth()
        local imgHeight = image:getHeight()
        
        -- Calculate scale to fit within the box while maintaining aspect ratio
        local scaleX = width / imgWidth
        local scaleY = height / imgHeight
        local scale = math.min(scaleX, scaleY)  -- Allow upscaling
        
        local displayWidth = imgWidth * scale
        local displayHeight = imgHeight * scale
        
        -- Center the sprite in the box
        local spriteX = x + (width - displayWidth) / 2
        local spriteY = y + (height - displayHeight) / 2
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, spriteX, spriteY, 0, scale, scale)
    end
end
M.pokemonSelected = 1
M.showPokemonDetails = false
M.pokemonDetailsIndex = 1
M.showBag = false
M.bagSelected = 1
M.currentBagItems = {}
M.bagItemMenuOpen = false
M.bagItemMenuSelected = 1
M.bagItemMenuItemIndex = 1
M.bagItemMenuOptions = {"Use", "Toss"}
M.bagCategories = {"medicine", "pokeball", "battle_item", "key_item", "tm", "berry", "misc"}
M.bagCurrentCategory = 1 -- index into bagCategories
M.bagUsingItem = false
M.bagItemToUse = nil
M.bagUsePokemonSelected = 1
M.bagItemMessage = nil -- Message to display after item use
M.bagItemMessage = nil -- Message to display after item use

-- Box menu state
M.showBox = false
M.boxAccessMode = nil  -- "world" or "menu" - tracks how the box was opened
M.boxSide = "party" -- "party" or "box"
M.boxPartySelected = 1
M.boxBoxSelected = 1

-- Pokemon submenu state (Summary/Move/Cancel)
M.pokemonActionMenuOpen = false  -- Shows the action submenu for selected Pokemon
M.pokemonActionSelected = 1
M.pokemonActionOptions = {"Summary", "Move", "Cancel"}

-- Pokemon move/swap mode state
M.pokemonMoveMode = false  -- True when in move/swap mode
M.pokemonMoveFirst = nil   -- Index of first Pokemon selected for swap

-- Summary screen state
M.summaryTab = 1  -- Current tab: 1=Overview, 2=Moves, 3=IVs/EVs
M.summaryTabCount = 3
M.summaryMoveSelected = 1  -- Selected move slot in the moves tab (1-4 for current, 5+ for learnable)
M.summaryMoveSide = "current"  -- "current" or "learnable"
M.summaryLearnableSelected = 1  -- Selected learnable move
M.summarySwapMode = false  -- True when selecting a move to swap out
M.summarySwapSource = nil  -- "current" or "learnable" - which side started the swap
M.summarySwapSourceIndex = nil  -- Index of the move being swapped

-- Move PP storage - stores PP for moves that have been swapped out
-- Key: pokemonId_moveId, Value: {pp, maxPP}
M.movePPStorage = {}

local log = require("log")

-- Helper function to refresh bag items for the current category
local function refresh_bag_items()
    M.currentBagItems = {}
    if M.player and M.player.bag then
        local category = M.bagCategories[M.bagCurrentCategory]
        local items = M.player.bag[category] or {}
        for itemId, item in pairs(items) do
            if item and item.quantity and item.quantity > 0 then
                table.insert(M.currentBagItems, item)
            end
        end
    end
    M.bagSelected = 1
end

-- Helper function to get a unique key for storing move PP
local function getMoveStorageKey(pokemon, moveId)
    -- Use species + a unique identifier if available
    local pokemonKey = tostring(pokemon.speciesId or pokemon.name or "unknown")
    if pokemon.uid then
        pokemonKey = pokemonKey .. "_" .. tostring(pokemon.uid)
    end
    return pokemonKey .. "_" .. tostring(moveId)
end

-- Helper function to create a move instance from a move ID
local function createMoveInstance(moveId)
    if not moveId then return nil end
    local ok, mm = pcall(require, "moves")
    if not ok or not mm then return nil end
    
    local key = moveId
    local norm = moveId:gsub("%s+", "")
    local norm2 = norm:gsub("%p", "")
    local lkey = string.lower(key)
    local lnorm = string.lower(norm)
    local lnorm2 = string.lower(norm2)
    
    local cls = mm[key] or mm[norm] or mm[norm2] or mm[lkey] or mm[lnorm] or mm[lnorm2]
    if cls and type(cls) == "table" and cls.new then
        local suc, inst = pcall(function() return cls:new() end)
        if suc and inst then return inst end
    elseif mm.Move and mm.Move.new then
        local suc, inst = pcall(function() return mm.Move:new({ name = moveId }) end)
        if suc and inst then return inst end
    end
    return nil
end

-- Store current PP values for all moves of a Pokemon before swapping
function M.storeMovesPP(pokemon)
    if not pokemon or not pokemon.moves then return end
    
    -- Store PP from _move_instances if available
    if pokemon._move_instances then
        for i, inst in ipairs(pokemon._move_instances) do
            if type(inst) == "table" and inst.pp and pokemon.moves[i] then
                local key = getMoveStorageKey(pokemon, pokemon.moves[i])
                M.movePPStorage[key] = {
                    pp = inst.pp,
                    maxPP = inst.maxPP or inst.pp
                }
            end
        end
    end
end

-- Restore PP values for moves (used after swapping)
function M.restoreMovesPP(pokemon)
    if not pokemon or not pokemon.moves then return end
    
    -- Rebuild _move_instances with stored PP values
    local arr = {}
    for i = 1, 4 do
        local moveId = pokemon.moves[i]
        if moveId then
            local key = getMoveStorageKey(pokemon, moveId)
            local storedPP = M.movePPStorage[key]
            
            local inst = createMoveInstance(moveId)
            if inst then
                if storedPP then
                    -- Restore saved PP
                    inst.pp = storedPP.pp
                    inst.maxPP = storedPP.maxPP
                else
                    -- New move - set to max PP
                    inst.maxPP = inst.maxPP or inst.pp
                    inst.pp = inst.maxPP
                end
                arr[i] = inst
            else
                arr[i] = ""
            end
        else
            arr[i] = ""
        end
    end
    pokemon._move_instances = arr
end

-- Get all learnable moves for a Pokemon (from learnset up to current level)
-- Helper function to find pre-evolution species for a given species
function M.getPreEvolutionChain(speciesId)
    local preEvos = {}
    
    -- Scan all species to find ones that evolve into the target
    for id, species in pairs(PokemonSpecies) do
        if species.evolution then
            if species.evolution.method == "branch" and species.evolution.options then
                -- Handle branching evolutions (like Eevee)
                for _, opt in ipairs(species.evolution.options) do
                    if opt.into == speciesId then
                        table.insert(preEvos, id)
                        -- Recursively find pre-evolutions of this species
                        local earlier = M.getPreEvolutionChain(id)
                        for _, e in ipairs(earlier) do
                            table.insert(preEvos, e)
                        end
                        break
                    end
                end
            elseif species.evolution.into == speciesId then
                table.insert(preEvos, id)
                -- Recursively find pre-evolutions of this species
                local earlier = M.getPreEvolutionChain(id)
                for _, e in ipairs(earlier) do
                    table.insert(preEvos, e)
                end
            end
        end
    end
    
    return preEvos
end

function M.getLearnableMoves(pokemon)
    if not pokemon or not pokemon.species or not pokemon.species.learnset then
        return {}
    end
    
    local moves = {}
    local seenMoves = {}
    
    -- Helper to collect moves from a species learnset
    local function collectMovesFromSpecies(species, level)
        if not species or not species.learnset then return end
        for lvl, moveList in pairs(species.learnset) do
            if lvl <= level then
                for _, moveId in ipairs(moveList) do
                    if not seenMoves[moveId] then
                        seenMoves[moveId] = true
                        table.insert(moves, moveId)
                    end
                end
            end
        end
    end
    
    -- Collect moves from current species
    collectMovesFromSpecies(pokemon.species, pokemon.level)
    
    -- Collect moves from pre-evolution species (all levels they could have learned)
    local preEvos = M.getPreEvolutionChain(pokemon.speciesId)
    for _, preEvoId in ipairs(preEvos) do
        local preEvoSpecies = PokemonSpecies[preEvoId]
        if preEvoSpecies then
            -- Pre-evolutions contribute all moves up to current level
            collectMovesFromSpecies(preEvoSpecies, pokemon.level)
        end
    end
    
    -- Sort moves alphabetically for easier browsing
    table.sort(moves)
    
    return moves
end

function M.toggle()
    M.open = not M.open
    if M.open then
        M.showPokemon = false
        M.showBag = false
        M.showBox = false
        M.showControlSettings = false
        M.selected = 1
        M.pokemonSelected = 1
        M.bagSelected = 1
        M.boxPartySelected = 1
        M.boxBoxSelected = 1
        M.boxSide = "party"
        M.controlSettingsSelected = 1
    else
        M.showPokemon = false
        M.showBag = false
        M.showBox = false
        M.showControlSettings = false
    end
end

function M.close()
    M.open = false
    M.showPokemon = false
    M.showBag = false
    M.showBox = false
    M.showControlSettings = false
    M.bagItemMenuOpen = false
    M.bagUsingItem = false
    M.boxAccessMode = nil
    M.selected = 1
    M.pokemonSelected = 1
    M.bagSelected = 1
    M.bagItemMenuSelected = 1
    M.bagUsePokemonSelected = 1
    M.boxPartySelected = 1
    M.boxBoxSelected = 1
    M.boxSide = "party"
    M.controlSettingsSelected = 1
    -- Reset Pokemon menu state
    M.pokemonActionMenuOpen = false
    M.pokemonActionSelected = 1
    M.pokemonMoveMode = false
    M.pokemonMoveFirst = nil
    M.showPokemonDetails = false
    M.summaryTab = 1
    M.summaryMoveSelected = 1
    M.summaryMoveSide = "current"
    M.summaryLearnableSelected = 1
    M.summarySwapMode = false
    M.summarySwapSource = nil
    M.summarySwapSourceIndex = nil
end

function M.isOpen()
    return M.open
end

-- Open the PC Box directly (for interacting with PC in the world)
function M.openBoxMenu()
    M.open = true
    M.showPokemon = false
    M.showBag = false
    M.showBox = true
    M.boxAccessMode = "world"  -- Mark that it was opened from world
    M.boxSide = "party"
    M.boxPartySelected = 1
    M.boxBoxSelected = 1
end

function M.update(dt)
    -- reserved for future menu animation/logic
end

function M.keypressed(key)
    if not M.open then return end
    
    -- Handle Control Settings menu
    if M.showControlSettings then
        local inputModule = require("input")
        if key == "up" then
            M.controlSettingsSelected = M.controlSettingsSelected - 1
            if M.controlSettingsSelected < 1 then M.controlSettingsSelected = #M.controlSettingsOptions end
        elseif key == "down" then
            M.controlSettingsSelected = M.controlSettingsSelected + 1
            if M.controlSettingsSelected > #M.controlSettingsOptions then M.controlSettingsSelected = 1 end
        elseif key == "space" then
            -- Close control settings
            M.showControlSettings = false
        elseif key == "return" or key == "z" or key == "Z" then
            local choice = M.controlSettingsOptions[M.controlSettingsSelected]
            if choice == "Touchscreen" then
                inputModule.setControlMode("touchscreen")
                -- Resize window to include control panel
                local RENDER_SCALE = 3
                local POV_W, POV_H = 160, 144
                local gameW = POV_W * RENDER_SCALE
                local gameH = POV_H * RENDER_SCALE
                love.window.setMode(gameW, gameH + inputModule.controlPanelHeight)
                inputModule.gameScreenWidth = gameW
                inputModule.gameScreenHeight = gameH
                inputModule.init()
                M.showControlSettings = false
                infoText = "Touchscreen mode enabled"
            elseif choice == "Handheld" then
                inputModule.setControlMode("handheld")
                -- Resize window to game-only (no control panel)
                local RENDER_SCALE = 3
                local POV_W, POV_H = 160, 144
                local gameW = POV_W * RENDER_SCALE
                local gameH = POV_H * RENDER_SCALE
                love.window.setMode(gameW, gameH)
                inputModule.gameScreenWidth = gameW
                inputModule.gameScreenHeight = gameH
                inputModule.init()
                M.showControlSettings = false
                infoText = "Handheld mode enabled"
            elseif choice == "Back" then
                M.showControlSettings = false
            end
        end
        return
    end
    
    if M.showBag then
        -- Handle message acknowledgment
        if M.bagItemMessage then
            if key == "return" or key == "z" or key == "Z" or key == "space" then
                M.bagItemMessage = nil
                M.bagUsingItem = false
                M.bagItemToUse = nil
                M.bagItemMenuOpen = false
                return
            end
            return -- Block other input while showing message
        end
        
        if M.bagUsingItem then
            -- Pokemon selection menu for item use
            if key == "up" then
                M.bagUsePokemonSelected = M.bagUsePokemonSelected - 1
                if M.bagUsePokemonSelected < 1 then
                    local count = (M.player and M.player.party) and #M.player.party or 0
                    M.bagUsePokemonSelected = count + 1
                end
            elseif key == "down" then
                local count = (M.player and M.player.party) and #M.player.party or 0
                M.bagUsePokemonSelected = M.bagUsePokemonSelected + 1
                if M.bagUsePokemonSelected > count + 1 then M.bagUsePokemonSelected = 1 end
            elseif key == "space" then
                -- cancel item use
                M.bagUsingItem = false
                M.bagItemToUse = nil
                return
            elseif key == "return" or key == "z" or key == "Z" then
                local count = (M.player and M.player.party) and #M.player.party or 0
                if M.bagUsePokemonSelected == count + 1 then
                    -- Cancel selected
                    M.bagUsingItem = false
                    M.bagItemToUse = nil
                    return
                else
                    -- Use item on selected Pokemon
                    local pokemon = M.player.party[M.bagUsePokemonSelected]
                    local item = M.bagItemToUse
                    if pokemon and item then
                        local ok, itemModule = pcall(require, "item")
                        if ok and itemModule and itemModule.useItem then
                            local success, message = itemModule.useItem(item, {
                                type = "overworld",
                                target = pokemon,
                                flags = {}
                            })
                            
                            -- Store the message to display
                            if message then
                                M.bagItemMessage = message
                            elseif success then
                                M.bagItemMessage = "Used " .. tostring(item.data.name) .. " on " .. tostring(pokemon.name)
                            else
                                M.bagItemMessage = "Item had no effect"
                            end
                            
                            -- Log the message
                            log.log(M.bagItemMessage)
                            
                            -- Decrease quantity if item was consumable and successful
                            if success and item.quantity <= 0 then
                                -- Item was consumed, remove from bag
                                local itemIndex = M.bagItemMenuItemIndex
                                table.remove(M.currentBagItems, itemIndex)
                                if M.bagSelected > #M.currentBagItems then
                                    M.bagSelected = math.max(1, #M.currentBagItems)
                                end
                            end
                        end
                    end
                    -- Don't close yet - wait for message acknowledgment
                    return
                end
            end
            return
        end
        if M.bagItemMenuOpen then
            -- Item menu navigation
            if key == "up" then
                M.bagItemMenuSelected = M.bagItemMenuSelected - 1
                if M.bagItemMenuSelected < 1 then
                    M.bagItemMenuSelected = #M.bagItemMenuOptions
                end
            elseif key == "down" then
                M.bagItemMenuSelected = M.bagItemMenuSelected + 1
                if M.bagItemMenuSelected > #M.bagItemMenuOptions then
                    M.bagItemMenuSelected = 1
                end
            elseif key == "space" or key == "z" or key == "Z" then
                -- go back to bag list
                if key == "space" then
                    M.bagItemMenuOpen = false
                    M.bagItemMenuSelected = 1
                    return
                end
                if key == "z" or key == "Z" then
                    -- confirm selection
                    local choice = M.bagItemMenuOptions[M.bagItemMenuSelected]
                    local itemIndex = M.bagItemMenuItemIndex
                    local item = M.currentBagItems[itemIndex]
                    
                    if choice == "Use" then
                        -- Check if item can be used in overworld
                        if item:canUse("overworld") then
                            M.bagUsingItem = true
                            M.bagItemToUse = item
                            M.bagUsePokemonSelected = 1
                            log.log("Select a Pokemon to use " .. tostring(item.data.name) .. " on")
                        else
                            log.log("Cannot use " .. tostring(item.data.name) .. " here")
                        end
                    elseif choice == "Toss" then
                        -- Remove 1 of the item from the player's bag
                        if M.player and M.player.bag then
                            M.player.bag:remove(item.id, 1)
                            -- Remove from current list if quantity is now 0
                            if item.quantity <= 0 then
                                table.remove(M.currentBagItems, itemIndex)
                            end
                            M.bagItemMenuOpen = false
                            M.bagItemMenuSelected = 1
                            -- Adjust selection if we're past the end
                            if M.bagSelected > #M.currentBagItems then
                                M.bagSelected = math.max(1, #M.currentBagItems)
                            end
                            log.log("Tossed 1x " .. tostring(item.data.name))
                        end
                    end
                    return
                end
            elseif key == "return" then
                -- confirm selection
                local choice = M.bagItemMenuOptions[M.bagItemMenuSelected]
                local itemIndex = M.bagItemMenuItemIndex
                local item = M.currentBagItems[itemIndex]
                
                if choice == "Use" then
                    -- Check if item can be used in overworld
                    if item:canUse("overworld") then
                        M.bagUsingItem = true
                        M.bagItemToUse = item
                        M.bagUsePokemonSelected = 1
                        log.log("Select a Pokemon to use " .. tostring(item.data.name) .. " on")
                    else
                        log.log("Cannot use " .. tostring(item.data.name) .. " here")
                    end
                elseif choice == "Toss" then
                    -- Remove 1 of the item from the player's bag
                    if M.player and M.player.bag then
                        M.player.bag:remove(item.id, 1)
                        -- Remove from current list if quantity is now 0
                        if item.quantity <= 0 then
                            table.remove(M.currentBagItems, itemIndex)
                        end
                        M.bagItemMenuOpen = false
                        M.bagItemMenuSelected = 1
                        -- Adjust selection if we're past the end
                        if M.bagSelected > #M.currentBagItems then
                            M.bagSelected = math.max(1, #M.currentBagItems)
                        end
                        log.log("Tossed 1x " .. tostring(item.data.name))
                    end
                end
                return
            end
            return
        end
        if key == "left" then
            -- Previous category
            M.bagCurrentCategory = M.bagCurrentCategory - 1
            if M.bagCurrentCategory < 1 then
                M.bagCurrentCategory = #M.bagCategories
            end
            refresh_bag_items()
        elseif key == "right" then
            -- Next category
            M.bagCurrentCategory = M.bagCurrentCategory + 1
            if M.bagCurrentCategory > #M.bagCategories then
                M.bagCurrentCategory = 1
            end
            refresh_bag_items()
        elseif key == "up" then
            M.bagSelected = M.bagSelected - 1
            if M.bagSelected < 1 then
                M.bagSelected = #M.currentBagItems + 1 -- wrap to back option
            end
        elseif key == "down" then
            M.bagSelected = M.bagSelected + 1
            if M.bagSelected > #M.currentBagItems + 1 then M.bagSelected = 1 end
        elseif key == "space" then
            -- close menu from bag
            M.close()
            return
        elseif key == "return" or key == "z" or key == "Z" then
            if M.bagSelected == #M.currentBagItems + 1 then
                -- Back selected
                M.showBag = false
                M.bagSelected = 1
                return
            else
                -- Item selected - open item menu
                M.bagItemMenuOpen = true
                M.bagItemMenuSelected = 1
                M.bagItemMenuItemIndex = M.bagSelected
                return
            end
        end
        return
    end
    if M.showBox then
        local partyCount = (M.player and M.player.party) and #M.player.party or 0
        local boxCount = (M.player and M.player.box) and #M.player.box or 0
        
        if key == "left" then
            -- Switch to party side
            M.boxSide = "party"
        elseif key == "right" then
            -- Switch to box side
            M.boxSide = "box"
        elseif key == "up" then
            if M.boxSide == "party" then
                M.boxPartySelected = M.boxPartySelected - 1
                if M.boxPartySelected < 1 then
                    M.boxPartySelected = partyCount + 1 -- +1 for Back option
                end
            else
                M.boxBoxSelected = M.boxBoxSelected - 1
                if M.boxBoxSelected < 1 then
                    M.boxBoxSelected = math.max(1, boxCount)
                end
            end
        elseif key == "down" then
            if M.boxSide == "party" then
                M.boxPartySelected = M.boxPartySelected + 1
                if M.boxPartySelected > partyCount + 1 then
                    M.boxPartySelected = 1
                end
            else
                M.boxBoxSelected = M.boxBoxSelected + 1
                if M.boxBoxSelected > boxCount then
                    M.boxBoxSelected = 1
                end
            end
        elseif key == "space" then
            -- close menu / back
            if M.showBox then
                -- If box is open and was opened from world, close everything
                if M.boxAccessMode == "world" then
                    M.close()
                else
                    -- If opened from menu, go back to main menu
                    M.showBox = false
                    M.boxPartySelected = 1
                    M.boxBoxSelected = 1
                    M.boxSide = "party"
                end
            else
                M.close()
            end
            return
        elseif key == "return" or key == "z" or key == "Z" then
            if M.boxSide == "party" then
                if M.boxPartySelected == partyCount + 1 then
                    -- Back selected
                    if M.boxAccessMode == "world" then
                        -- Opened from world - close everything
                        M.close()
                    else
                        -- Opened from menu - go back to main menu
                        M.showBox = false
                        M.boxPartySelected = 1
                        M.boxBoxSelected = 1
                        M.boxSide = "party"
                    end
                    return
                else
                    -- Move party Pokemon to box (but keep at least 1 in party)
                    if partyCount > 1 then
                        local pokemon = M.player.party[M.boxPartySelected]
                        if pokemon then
                            if not M.player.box then M.player.box = {} end
                            table.insert(M.player.box, pokemon)
                            table.remove(M.player.party, M.boxPartySelected)
                            -- Adjust selection if needed
                            if M.boxPartySelected > #M.player.party then
                                M.boxPartySelected = math.max(1, #M.player.party)
                            end
                            log.log("Moved " .. tostring(pokemon.nickname or pokemon.name) .. " to Box")
                        end
                    else
                        log.log("Cannot deposit - must keep at least one Pokemon in party!")
                    end
                end
            else
                -- Move box Pokemon to party (if party has room)
                if boxCount > 0 and partyCount < 6 then
                    local pokemon = M.player.box[M.boxBoxSelected]
                    if pokemon then
                        table.insert(M.player.party, pokemon)
                        table.remove(M.player.box, M.boxBoxSelected)
                        -- Adjust selection if needed
                        if M.boxBoxSelected > #M.player.box then
                            M.boxBoxSelected = math.max(1, #M.player.box)
                        end
                        log.log("Withdrew " .. tostring(pokemon.nickname or pokemon.name) .. " from Box")
                    end
                elseif partyCount >= 6 then
                    log.log("Party is full!")
                end
            end
        end
        return
    end
    if M.showPokemon then
        local count = (M.player and M.player.party) and #M.player.party or 0
        
        -- Summary screen (with tabs)
        if M.showPokemonDetails then
            local idx = M.pokemonDetailsIndex or 1
            local p = (M.player and M.player.party and M.player.party[idx]) and M.player.party[idx] or nil
            
            -- Tab 2: Moves management - handle swap mode
            if M.summaryTab == 2 and M.summarySwapMode then
                -- In swap mode - selecting a target move to swap with
                if key == "left" then
                    if M.summaryMoveSide == "learnable" then
                        M.summaryMoveSide = "current"
                    end
                    return
                elseif key == "right" then
                    if M.summaryMoveSide == "current" then
                        M.summaryMoveSide = "learnable"
                    end
                    return
                elseif key == "up" then
                    if M.summaryMoveSide == "current" then
                        M.summaryMoveSelected = M.summaryMoveSelected - 1
                        if M.summaryMoveSelected < 1 then M.summaryMoveSelected = 4 end
                    else
                        local learnableMoves = M.getLearnableMoves(p)
                        M.summaryLearnableSelected = M.summaryLearnableSelected - 1
                        if M.summaryLearnableSelected < 1 then 
                            M.summaryLearnableSelected = math.max(1, #learnableMoves)
                        end
                    end
                    return
                elseif key == "down" then
                    if M.summaryMoveSide == "current" then
                        M.summaryMoveSelected = M.summaryMoveSelected + 1
                        if M.summaryMoveSelected > 4 then M.summaryMoveSelected = 1 end
                    else
                        local learnableMoves = M.getLearnableMoves(p)
                        M.summaryLearnableSelected = M.summaryLearnableSelected + 1
                        if M.summaryLearnableSelected > #learnableMoves then 
                            M.summaryLearnableSelected = 1
                        end
                    end
                    return
                elseif key == "space" then
                    -- Cancel swap
                    M.summarySwapMode = false
                    M.summarySwapSource = nil
                    M.summarySwapSourceIndex = nil
                    return
                elseif key == "return" or key == "z" or key == "Z" then
                    -- Perform the swap based on source and target
                    if p then
                        if M.summarySwapSource == "current" then
                            -- Source is a current move
                            local sourceIdx = M.summarySwapSourceIndex
                            if M.summaryMoveSide == "current" then
                                -- Swapping two current moves (reorder)
                                local targetIdx = M.summaryMoveSelected
                                if sourceIdx ~= targetIdx and p.moves[sourceIdx] and p.moves[targetIdx] then
                                    -- Swap the moves
                                    local temp = p.moves[sourceIdx]
                                    p.moves[sourceIdx] = p.moves[targetIdx]
                                    p.moves[targetIdx] = temp
                                    -- Swap move instances for PP
                                    if p._move_instances then
                                        local tempInst = p._move_instances[sourceIdx]
                                        p._move_instances[sourceIdx] = p._move_instances[targetIdx]
                                        p._move_instances[targetIdx] = tempInst
                                    end
                                    log.log("Swapped move positions " .. sourceIdx .. " and " .. targetIdx)
                                end
                            else
                                -- Swapping current move with a learnable move
                                local learnableMoves = M.getLearnableMoves(p)
                                local newMoveId = learnableMoves[M.summaryLearnableSelected]
                                local oldMoveId = p.moves[sourceIdx]
                                
                                if newMoveId and oldMoveId then
                                    -- Check if new move is already known
                                    local alreadyKnown = false
                                    for _, m in ipairs(p.moves) do
                                        if m == newMoveId then alreadyKnown = true; break end
                                    end
                                    
                                    if not alreadyKnown then
                                        M.storeMovesPP(p)
                                        p.moves[sourceIdx] = newMoveId
                                        M.restoreMovesPP(p)
                                        log.log("Replaced " .. tostring(oldMoveId) .. " with " .. tostring(newMoveId))
                                    else
                                        log.log("Already knows " .. tostring(newMoveId))
                                    end
                                end
                            end
                        elseif M.summarySwapSource == "learnable" then
                            -- Source is a learnable move, target must be current
                            if M.summaryMoveSide == "current" then
                                local learnableMoves = M.getLearnableMoves(p)
                                local newMoveId = learnableMoves[M.summarySwapSourceIndex]
                                local targetIdx = M.summaryMoveSelected
                                local oldMoveId = p.moves[targetIdx]
                                
                                if newMoveId and oldMoveId then
                                    -- Check if new move is already known
                                    local alreadyKnown = false
                                    for _, m in ipairs(p.moves) do
                                        if m == newMoveId then alreadyKnown = true; break end
                                    end
                                    
                                    if not alreadyKnown then
                                        M.storeMovesPP(p)
                                        p.moves[targetIdx] = newMoveId
                                        M.restoreMovesPP(p)
                                        log.log("Replaced " .. tostring(oldMoveId) .. " with " .. tostring(newMoveId))
                                    else
                                        log.log("Already knows " .. tostring(newMoveId))
                                    end
                                end
                            end
                        end
                    end
                    M.summarySwapMode = false
                    M.summarySwapSource = nil
                    M.summarySwapSourceIndex = nil
                    M.summaryMoveSide = "current"
                    return
                end
                return
            end
            
            -- Tab 2: Moves management - normal navigation
            if M.summaryTab == 2 then
                if key == "left" then
                    if M.summaryMoveSide == "learnable" then
                        M.summaryMoveSide = "current"
                    else
                        -- Switch to previous tab
                        M.summaryTab = M.summaryTab - 1
                        if M.summaryTab < 1 then M.summaryTab = M.summaryTabCount end
                    end
                    return
                elseif key == "right" then
                    if M.summaryMoveSide == "current" then
                        M.summaryMoveSide = "learnable"
                    else
                        -- Switch to next tab
                        M.summaryTab = M.summaryTab + 1
                        if M.summaryTab > M.summaryTabCount then M.summaryTab = 1 end
                    end
                    return
                elseif key == "up" then
                    if M.summaryMoveSide == "current" then
                        M.summaryMoveSelected = M.summaryMoveSelected - 1
                        if M.summaryMoveSelected < 1 then M.summaryMoveSelected = 4 end
                    else
                        local learnableMoves = M.getLearnableMoves(p)
                        M.summaryLearnableSelected = M.summaryLearnableSelected - 1
                        if M.summaryLearnableSelected < 1 then 
                            M.summaryLearnableSelected = math.max(1, #learnableMoves)
                        end
                    end
                    return
                elseif key == "down" then
                    if M.summaryMoveSide == "current" then
                        M.summaryMoveSelected = M.summaryMoveSelected + 1
                        if M.summaryMoveSelected > 4 then M.summaryMoveSelected = 1 end
                    else
                        local learnableMoves = M.getLearnableMoves(p)
                        M.summaryLearnableSelected = M.summaryLearnableSelected + 1
                        if M.summaryLearnableSelected > #learnableMoves then 
                            M.summaryLearnableSelected = 1
                        end
                    end
                    return
                elseif key == "return" or key == "z" or key == "Z" then
                    if M.summaryMoveSide == "current" then
                        -- Selected a current move - enter swap mode
                        local moveIdx = M.summaryMoveSelected
                        if p and p.moves and p.moves[moveIdx] then
                            M.summarySwapMode = true
                            M.summarySwapSource = "current"
                            M.summarySwapSourceIndex = moveIdx
                            log.log("Selected current move " .. tostring(p.moves[moveIdx]) .. " to swap")
                        end
                    else
                        -- Selected a learnable move
                        local learnableMoves = M.getLearnableMoves(p)
                        local selectedMove = learnableMoves[M.summaryLearnableSelected]
                        if selectedMove and p then
                            local alreadyKnown = false
                            for _, m in ipairs(p.moves) do
                                if m == selectedMove then
                                    alreadyKnown = true
                                    break
                                end
                            end
                            if not alreadyKnown then
                                -- If less than 4 moves, just learn it
                                if #p.moves < 4 then
                                    table.insert(p.moves, selectedMove)
                                    M.restoreMovesPP(p)
                                    log.log("Learned " .. tostring(selectedMove))
                                else
                                    -- Enter swap mode - select which move to replace
                                    M.summarySwapMode = true
                                    M.summarySwapSource = "learnable"
                                    M.summarySwapSourceIndex = M.summaryLearnableSelected
                                    M.summaryMoveSide = "current"
                                    M.summaryMoveSelected = 1
                                end
                            else
                                log.log("Already knows " .. tostring(selectedMove))
                            end
                        end
                    end
                    return
                end
            end
            
            -- General summary navigation (tabs 1 and 3, or tab 2 when not in special modes)
            if key == "left" then
                M.summaryTab = M.summaryTab - 1
                if M.summaryTab < 1 then M.summaryTab = M.summaryTabCount end
                M.summaryMoveSide = "current"
                M.summaryMoveSelected = 1
                return
            elseif key == "right" then
                M.summaryTab = M.summaryTab + 1
                if M.summaryTab > M.summaryTabCount then M.summaryTab = 1 end
                M.summaryMoveSide = "current"
                M.summaryMoveSelected = 1
                return
            elseif key == "up" then
                -- Switch to previous Pokemon in party
                M.pokemonDetailsIndex = M.pokemonDetailsIndex - 1
                if M.pokemonDetailsIndex < 1 then M.pokemonDetailsIndex = count end
                M.summaryMoveSelected = 1
                M.summaryLearnableSelected = 1
                return
            elseif key == "down" then
                -- Switch to next Pokemon in party
                M.pokemonDetailsIndex = M.pokemonDetailsIndex + 1
                if M.pokemonDetailsIndex > count then M.pokemonDetailsIndex = 1 end
                M.summaryMoveSelected = 1
                M.summaryLearnableSelected = 1
                return
            elseif key == "z" or key == "Z" then
                -- Exit summary
                M.showPokemonDetails = false
                M.summaryTab = 1
                M.summaryMoveSelected = 1
                M.summaryLearnableSelected = 1
                M.summaryMoveSide = "current"
                M.summarySwapMode = false
                return
            elseif key == "space" then
                -- Also exit summary
                M.showPokemonDetails = false
                M.summaryTab = 1
                return
            end
            return
        end
        
        -- Pokemon action submenu (Summary/Move/Cancel)
        if M.pokemonActionMenuOpen then
            if key == "up" then
                M.pokemonActionSelected = M.pokemonActionSelected - 1
                if M.pokemonActionSelected < 1 then 
                    M.pokemonActionSelected = #M.pokemonActionOptions 
                end
            elseif key == "down" then
                M.pokemonActionSelected = M.pokemonActionSelected + 1
                if M.pokemonActionSelected > #M.pokemonActionOptions then 
                    M.pokemonActionSelected = 1 
                end
            elseif key == "space" then
                -- Cancel - close submenu
                M.pokemonActionMenuOpen = false
                M.pokemonActionSelected = 1
                return
            elseif key == "return" or key == "z" or key == "Z" then
                local choice = M.pokemonActionOptions[M.pokemonActionSelected]
                if choice == "Cancel" then
                    M.pokemonActionMenuOpen = false
                    M.pokemonActionSelected = 1
                elseif choice == "Move" then
                    -- Enter move/swap mode
                    M.pokemonMoveMode = true
                    M.pokemonMoveFirst = M.pokemonSelected
                    M.pokemonActionMenuOpen = false
                    M.pokemonActionSelected = 1
                elseif choice == "Summary" then
                    -- Open summary screen
                    M.showPokemonDetails = true
                    M.pokemonDetailsIndex = M.pokemonSelected
                    M.summaryTab = 1
                    M.pokemonActionMenuOpen = false
                    M.pokemonActionSelected = 1
                    -- Log stats for debugging
                    local p = M.player.party[M.pokemonDetailsIndex]
                    if p then
                        log.log("Viewing summary for: " .. tostring(p.nickname or p.name))
                    end
                end
                return
            end
            return
        end
        
        -- Pokemon move/swap mode
        if M.pokemonMoveMode then
            if key == "up" then
                M.pokemonSelected = M.pokemonSelected - 1
                if M.pokemonSelected < 1 then M.pokemonSelected = count end
            elseif key == "down" then
                M.pokemonSelected = M.pokemonSelected + 1
                if M.pokemonSelected > count then M.pokemonSelected = 1 end
            elseif key == "space" then
                -- Cancel move mode
                M.pokemonMoveMode = false
                M.pokemonMoveFirst = nil
                return
            elseif key == "return" or key == "z" or key == "Z" then
                -- Swap the two Pokemon
                local first = M.pokemonMoveFirst
                local second = M.pokemonSelected
                if first and second and first ~= second and M.player and M.player.party then
                    local temp = M.player.party[first]
                    M.player.party[first] = M.player.party[second]
                    M.player.party[second] = temp
                    log.log("Swapped Pokemon " .. first .. " and " .. second)
                end
                M.pokemonMoveMode = false
                M.pokemonMoveFirst = nil
                return
            end
            return
        end
        
        -- Normal Pokemon list navigation
        if key == "up" then
            M.pokemonSelected = M.pokemonSelected - 1
            if M.pokemonSelected < 1 then
                -- wrap to back option
                M.pokemonSelected = count + 1
            end
        elseif key == "down" then
            M.pokemonSelected = M.pokemonSelected + 1
            if M.pokemonSelected > count + 1 then M.pokemonSelected = 1 end
        elseif key == "space" then
            -- close menu from any submenu
            M.close()
            return
        elseif key == "return" or key == "z" or key == "Z" then
            if M.pokemonSelected == count + 1 then
                -- Back selected
                M.showPokemon = false
                M.pokemonSelected = 1
                return
            else
                -- Open action submenu for selected Pokemon
                M.pokemonActionMenuOpen = true
                M.pokemonActionSelected = 1
                return
            end
        end
        return
    end
    if key == "up" then
        M.selected = M.selected - 1
        if M.selected < 1 then M.selected = #M.options end
    elseif key == "down" then
        M.selected = M.selected + 1
        if M.selected > #M.options then M.selected = 1 end
    elseif key == "space" then
        M.toggle()
    elseif key == "return" or key == "z" or key == "Z" then
        local choice = M.options[M.selected]
        if choice == "Exit" then
            love.event.quit()
        elseif choice == "Save" then
            -- serialize `M.player` to JSON and write to save/player.json
            if M.player then
                local ok, err = pcall(function()
                    local json = encode_json(M.player)
                    -- ensure folder 'save' path is used; love.filesystem will create file if needed
                    love.filesystem.createDirectory("save")
                    love.filesystem.write("save/player.json", json)
                end)
                if ok then
                    infoText = "Game saved"
                    M.close()
                else
                    infoText = "Save failed"
                end
            else
                infoText = "No player to save"
            end
        elseif choice == "Heal" then
            if M.player and M.player.party then
                for _, p in ipairs(M.player.party) do
                    if p and p.stats and p.stats.hp then
                        p.currentHP = p.stats.hp
                    end
                    -- Restore PP for this pokemon's moves to max
                    if p then
                        -- helper to create a move instance from a string or table
                        local function make_move_instance(mv)
                            if not mv then return nil end
                            if type(mv) == "table" then
                                if mv.use or mv.pp then return mv end
                                if mv.new and type(mv.new) == "function" then
                                    local ok, inst = pcall(mv.new)
                                    if ok and inst then return inst end
                                end
                            elseif type(mv) == "string" then
                                local ok, mm = pcall(require, "moves")
                                if ok and mm then
                                    local key = mv
                                    local norm = mv:gsub("%s+", "")
                                    local norm2 = norm:gsub("%p", "")
                                    local lkey = string.lower(key)
                                    local lnorm = string.lower(norm)
                                    local lnorm2 = string.lower(norm2)
                                    local cls = mm[key] or mm[norm] or mm[norm2] or mm[lkey] or mm[lnorm] or mm[lnorm2]
                                    if cls and type(cls) == "table" and cls.new then
                                        local suc, inst = pcall(function() return cls:new() end)
                                        if suc and inst then return inst end
                                    elseif mm.Move and mm.Move.new then
                                        local suc, inst = pcall(function() return mm.Move:new({ name = mv }) end)
                                        if suc and inst then return inst end
                                    end
                                end
                            end
                            return nil
                        end

                        if p._move_instances then
                            for _, inst in ipairs(p._move_instances) do
                                if type(inst) == "table" and inst.maxPP then
                                    inst.pp = inst.maxPP
                                end
                            end
                        else
                            -- create instances from p.moves and set pp to maxPP
                            if p.moves and #p.moves > 0 then
                                local arr = {}
                                for i = 1, 4 do
                                    local mv = p.moves[i]
                                    local inst = make_move_instance(mv)
                                    if inst then
                                        inst.maxPP = inst.maxPP or inst.pp
                                        if inst.maxPP then inst.pp = inst.maxPP end
                                        arr[i] = inst
                                    else
                                        arr[i] = ""
                                    end
                                end
                                p._move_instances = arr
                            end
                        end
                    end
                end
                infoText = "Party healed"
            else
                infoText = "No party to heal"
            end
            M.close()
        elseif choice == "Bag" then
            -- open bag
            M.showBag = true
            M.bagSelected = 1
            M.bagCurrentCategory = 1
            refresh_bag_items()
            return
        elseif choice == "Box" then
            -- open Box (PC storage) view
            M.showBox = true
            M.boxAccessMode = "menu"  -- Mark that it was opened from menu
            M.boxPartySelected = 1
            M.boxBoxSelected = 1
            M.boxSide = "party"
            return
        elseif choice == "Controls" then
            -- open Controls settings view
            M.showControlSettings = true
            M.controlSettingsSelected = 1
            return
        elseif choice == "Pokemon" then
            -- open Pokemon party view
            M.showPokemon = true
            M.pokemonSelected = 1
            return
        else
            infoText = "Selected: " .. choice
        end
    end
end

-- Helper function to draw a Pokemon-style menu box (white bg, dark border)
local function drawMenuBox(x, y, w, h, borderWidth)
    UI.drawBox(x, y, w, h, borderWidth)
end

-- Helper to draw text in dark color (for white backgrounds)
local function setMenuTextColor(selected)
    if selected then
        love.graphics.setColor(unpack(UI.colors.textSelected))
    else
        love.graphics.setColor(unpack(UI.colors.textDark))
    end
end

function M.draw()
    if not M.open then return end
    love.graphics.push()
    love.graphics.origin()
    local ww, hh = UI.getGameScreenDimensions()
    
    -- Semi-transparent dark overlay
    UI.drawOverlay(0.5)
    
    local font = love.graphics.getFont()
    local lh = (font and font:getHeight() or 12) + 8
    
    if M.showBag then
        -- Bag menu box
        local boxW = ww * 0.75
        local boxH = hh * 0.7
        local boxX = (ww - boxW) / 2
        local boxY = hh * 0.12
        UI.drawBoxWithShadow(boxX, boxY, boxW, boxH)
        
        -- Title
        love.graphics.setColor(unpack(UI.colors.textDark))
        love.graphics.printf("BAG", boxX, boxY + 12, boxW, "center")
        
        -- Show category tabs
        local category = M.bagCategories[M.bagCurrentCategory]
        local categoryDisplay = (category:gsub("_", " ")):sub(1,1):upper() .. (category:gsub("_", " ")):sub(2)
        local itemCount = #M.currentBagItems
        local categoryText = "<  " .. categoryDisplay .. "  >"
        love.graphics.setColor(unpack(UI.colors.textGray))
        love.graphics.printf(categoryText, boxX, boxY + 12 + lh, boxW, "center")
        
        -- Item list
        local listStartY = boxY + 20 + lh * 2
        local listX = boxX + 35
        
        if itemCount == 0 then
            love.graphics.setColor(unpack(UI.colors.textGray))
            love.graphics.print("No items", listX, listStartY)
            -- Back option
            local backY = listStartY + lh
            UI.drawOption("Back", listX, backY, M.bagSelected == 1)
        else
            for i, item in ipairs(M.currentBagItems) do
                local y = listStartY + (i-1) * lh
                local line = string.format("%s x%s", item.data.name, tostring(item.quantity))
                UI.drawOption(line, listX, y, i == M.bagSelected)
            end
            -- Back option
            local by = listStartY + itemCount * lh
            UI.drawOption("Back", listX, by, M.bagSelected == itemCount + 1)
        end
        
        -- Show item menu overlay in bottom right
        if M.bagItemMenuOpen then
            local menuW = ww * 0.25
            local menuH = lh * (#M.bagItemMenuOptions + 0.5) + 15
            local menuX = boxX + boxW - menuW - 15
            local menuY = boxY + boxH - menuH - 15
            UI.drawActionMenu(M.bagItemMenuOptions, M.bagItemMenuSelected, menuX, menuY, menuW, menuH)
        end
        
        -- Show Pokemon selection for item use
        if M.bagUsingItem and M.bagItemToUse then
            UI.drawOverlay(0.4)
            
            local selectBoxW = ww * 0.6
            local count = (M.player and M.player.party) and #M.player.party or 0
            local selectBoxH = lh * (count + 2) + 30
            local selectBoxX = (ww - selectBoxW) / 2
            local selectBoxY = (hh - selectBoxH) / 2
            UI.drawBoxWithShadow(selectBoxX, selectBoxY, selectBoxW, selectBoxH)
            
            love.graphics.setColor(unpack(UI.colors.textDark))
            love.graphics.printf("Use on which Pokemon?", selectBoxX, selectBoxY + 12, selectBoxW, "center")
            
            local listY = selectBoxY + 12 + lh * 1.5
            local listX = selectBoxX + 30
            
            if count == 0 then
                love.graphics.setColor(unpack(UI.colors.textGray))
                love.graphics.print("No Pokemon", listX, listY)
            else
                for i, p in ipairs(M.player.party) do
                    local y = listY + (i-1) * lh
                    local name = tostring(p.nickname or p.name or "Unknown")
                    local lvl = tostring(p.level or "?")
                    local hp = tostring(p.currentHP or 0)
                    local max = tostring(p.stats and p.stats.hp or "?")
                    local statusStr = UI.getStatusString(p)
                    local line = string.format("%s  Lv%s  HP:%s/%s", name, lvl, hp, max)
                    if statusStr then line = line .. "  [" .. statusStr .. "]" end
                    UI.drawOption(line, listX, y, i == M.bagUsePokemonSelected)
                end
            end
            
            -- Cancel option
            local cancelY = listY + count * lh
            UI.drawOption("Cancel", listX, cancelY, M.bagUsePokemonSelected == count + 1)
        end
        
        -- Show message after item use (overlays everything)
        if M.bagItemMessage then
            UI.drawOverlay(0.7)
            local msgBoxW = ww * 0.65
            local msgBoxH = hh * 0.2
            local msgBoxX = (ww - msgBoxW) / 2
            local msgBoxY = (hh - msgBoxH) / 2
            UI.drawMessageBox(M.bagItemMessage, msgBoxX, msgBoxY, msgBoxW, msgBoxH, "(Press Z or Space to continue)")
        end
        
    elseif M.showBox then
        -- PC Box menu
        local boxW = ww * 0.85
        local boxH = hh * 0.75
        local mainBoxX = (ww - boxW) / 2
        local mainBoxY = hh * 0.1
        UI.drawBoxWithShadow(mainBoxX, mainBoxY, boxW, boxH)
        
        love.graphics.setColor(unpack(UI.colors.textDark))
        love.graphics.printf("PC BOX", mainBoxX, mainBoxY + 10, boxW, "center")
        love.graphics.setColor(unpack(UI.colors.textGray))
        love.graphics.printf("(Use Left/Right to switch sides)", mainBoxX, mainBoxY + 10 + lh, boxW, "center")
        
        local partyCount = (M.player and M.player.party) and #M.player.party or 0
        local boxCount = (M.player and M.player.box) and #M.player.box or 0
        
        -- Draw Party column on left
        local partyX = mainBoxX + 25
        local pcBoxX = mainBoxX + boxW * 0.52
        local listY = mainBoxY + 15 + lh * 2.5
        
        -- Party header
        local partyHeader = "PARTY"
        if M.boxSide == "party" then
            love.graphics.setColor(unpack(UI.colors.textSelected))
            partyHeader = "> " .. partyHeader
        else
            love.graphics.setColor(unpack(UI.colors.textDark))
        end
        love.graphics.print(partyHeader, partyX, listY - lh)
        
        -- Box header
        local boxHeader = "BOX"
        if M.boxSide == "box" then
            love.graphics.setColor(unpack(UI.colors.textSelected))
            boxHeader = "> " .. boxHeader
        else
            love.graphics.setColor(unpack(UI.colors.textDark))
        end
        love.graphics.print(boxHeader, pcBoxX, listY - lh)
        
        -- Draw party Pokemon
        if partyCount == 0 then
            love.graphics.setColor(unpack(UI.colors.textGray))
            love.graphics.print("(empty)", partyX, listY)
        else
            for i, p in ipairs(M.player.party) do
                local y = listY + (i-1) * lh
                local name = tostring(p.nickname or p.name or "???")
                local lvl = tostring(p.level or "?")
                local line = string.format("%s Lv%s", name, lvl)
                UI.drawOption(line, partyX, y, M.boxSide == "party" and i == M.boxPartySelected)
            end
        end
        
        -- Draw Back option under party
        local backY = listY + partyCount * lh
        UI.drawOption("Back", partyX, backY, M.boxSide == "party" and M.boxPartySelected == partyCount + 1)
        
        -- Draw box Pokemon
        if boxCount == 0 then
            love.graphics.setColor(unpack(UI.colors.textGray))
            love.graphics.print("(empty)", pcBoxX, listY)
        else
            -- Show scrollable list (max 6 visible at a time)
            local maxVisible = 6
            local startIdx = 1
            if M.boxBoxSelected > maxVisible then
                startIdx = M.boxBoxSelected - maxVisible + 1
            end
            local endIdx = math.min(startIdx + maxVisible - 1, boxCount)
            
            local drawIdx = 0
            for i = startIdx, endIdx do
                local p = M.player.box[i]
                if p then
                    local y = listY + drawIdx * lh
                    local name = tostring(p.nickname or p.name or "???")
                    local lvl = tostring(p.level or "?")
                    local line = string.format("%s Lv%s", name, lvl)
                    UI.drawOption(line, pcBoxX, y, M.boxSide == "box" and i == M.boxBoxSelected)
                    drawIdx = drawIdx + 1
                end
            end
            
            -- Show scroll indicators if needed
            love.graphics.setColor(unpack(UI.colors.textGray))
            if startIdx > 1 then
                love.graphics.print("^", pcBoxX + ww * 0.15, listY - lh * 0.8)
            end
            if endIdx < boxCount then
                love.graphics.print("v", pcBoxX + ww * 0.15, listY + maxVisible * lh - lh * 0.5)
            end
        end
        
        -- Show count
        love.graphics.setColor(unpack(UI.colors.textGray))
        love.graphics.print(string.format("Party: %d/6", partyCount), partyX, mainBoxY + boxH - 25)
        love.graphics.print(string.format("Box: %d", boxCount), pcBoxX, mainBoxY + boxH - 25)
    
    elseif M.showControlSettings then
        -- Control Settings menu
        local inputModule = require("input")
        local currentMode = inputModule.getControlMode()
        
        local boxW = ww * 0.6
        local boxH = lh * (#M.controlSettingsOptions + 2) + 40
        local boxX = (ww - boxW) / 2
        local boxY = (hh - boxH) / 2
        
        UI.drawBoxWithShadow(boxX, boxY, boxW, boxH)
        
        -- Title
        love.graphics.setColor(unpack(UI.colors.textDark))
        love.graphics.printf("CONTROL MODE", boxX, boxY + 12, boxW, "center")
        
        -- Current mode indicator
        love.graphics.setColor(unpack(UI.colors.textGray))
        local modeText = "Current: " .. (currentMode == "touchscreen" and "Touchscreen" or "Handheld")
        love.graphics.printf(modeText, boxX, boxY + 12 + lh, boxW, "center")
        
        -- Options list
        local listStartY = boxY + 25 + lh * 2
        local listX = boxX + 35
        
        for i, opt in ipairs(M.controlSettingsOptions) do
            local y = listStartY + (i - 1) * lh
            local isCurrentMode = (opt == "Touchscreen" and currentMode == "touchscreen") or
                                  (opt == "Handheld" and currentMode == "handheld")
            
            -- Draw option with checkmark if it's the current mode
            if isCurrentMode and opt ~= "Back" then
                UI.drawOption("● " .. opt, listX, y, i == M.controlSettingsSelected)
            else
                UI.drawOption(opt, listX, y, i == M.controlSettingsSelected)
            end
        end
        
    elseif M.showPokemon then
        local count = (M.player and M.player.party) and #M.player.party or 0
        
        -- Summary screen with tabs (detailed Pokemon view)
        if M.showPokemonDetails then
            local idx = M.pokemonDetailsIndex or 1
            local p = (M.player and M.player.party and M.player.party[idx]) and M.player.party[idx] or nil
            
            -- Main summary box
            local summaryBoxW = ww * 0.85
            local summaryBoxH = hh * 0.8
            local summaryBoxX = (ww - summaryBoxW) / 2
            local summaryBoxY = hh * 0.08
            UI.drawBoxWithShadow(summaryBoxX, summaryBoxY, summaryBoxW, summaryBoxH)
            
            -- Draw tab headers
            local tabNames = {"Summary", "Moves", "IVs/EVs"}
            local tabY = summaryBoxY + 12
            local tabStartX = summaryBoxX + 20
            local tabW = (summaryBoxW - 40) / #tabNames
            for i, tabName in ipairs(tabNames) do
                local tabX = tabStartX + (i - 1) * tabW
                if i == M.summaryTab then
                    love.graphics.setColor(unpack(UI.colors.textSelected))
                    love.graphics.printf("[ " .. tabName .. " ]", tabX, tabY, tabW, "center")
                else
                    love.graphics.setColor(unpack(UI.colors.textGray))
                    love.graphics.printf(tabName, tabX, tabY, tabW, "center")
                end
            end
            
            -- Draw Pokemon sprite area (top-right corner)
            if p then
                if M.summaryTab == 1 then
                    -- Larger sprite on Summary tab (top-right)
                    local spriteBoxW = summaryBoxW * 0.20
                    local spriteBoxH = spriteBoxW  -- Make it square
                    local spriteBoxX = summaryBoxX + summaryBoxW - spriteBoxW - 15
                    local spriteBoxY = summaryBoxY + 50
                    drawPokemonSprite(p, spriteBoxX, spriteBoxY, spriteBoxW, spriteBoxH, false)
                else
                    -- Smaller sprite on other tabs (top-right, above content)
                    local smallSpriteSize = lh * 2
                    local spriteX = summaryBoxX + summaryBoxW - smallSpriteSize - 15
                    local spriteY = summaryBoxY + 50
                    drawPokemonSprite(p, spriteX, spriteY, smallSpriteSize, smallSpriteSize, false)
                end
            end
            
            local infoY = summaryBoxY + 15 + lh * 1.5
            local infoX = summaryBoxX + 25
            
            if not p then
                love.graphics.setColor(unpack(UI.colors.textGray))
                love.graphics.print("No data", infoX, infoY)
            elseif M.summaryTab == 1 then
                -- TAB 1: Overview Summary
                local name = tostring(p.nickname or p.name or "Unknown")
                local lvl = tostring(p.level or "?")
                love.graphics.setColor(unpack(UI.colors.textDark))
                love.graphics.print(string.format("%s  Lv%s", name, lvl), infoX, infoY)
                infoY = infoY + lh

                -- HP bar
                local curHp = p.currentHP or 0
                local maxHp = (p.stats and p.stats.hp) or 1
                love.graphics.setColor(unpack(UI.colors.textDark))
                love.graphics.print("HP:", infoX, infoY)
                UI.drawHPBar(curHp, maxHp, infoX + 35, infoY + 3, 120, 12)
                love.graphics.setColor(unpack(UI.colors.textDark))
                love.graphics.print(string.format("%d/%d", curHp, maxHp), infoX + 165, infoY)
                infoY = infoY + lh * 1.3

                -- Stats in two columns
                local function eff(stat)
                    if p.stats then return p.stats[stat] or "?" else return "?" end
                end
                
                local col1X = infoX
                local col2X = infoX + summaryBoxW * 0.4
                
                love.graphics.setColor(unpack(UI.colors.textDark))
                love.graphics.print("Attack: " .. tostring(eff("attack")), col1X, infoY)
                love.graphics.print("Sp.Atk: " .. tostring(eff("spAttack")), col2X, infoY)
                infoY = infoY + lh
                love.graphics.print("Defense: " .. tostring(eff("defense")), col1X, infoY)
                love.graphics.print("Sp.Def: " .. tostring(eff("spDefense")), col2X, infoY)
                infoY = infoY + lh
                love.graphics.print("Speed: " .. tostring(eff("speed")), col1X, infoY)
                infoY = infoY + lh

                -- Moves summary
                infoY = infoY + lh * 0.5
                love.graphics.print("Moves:", col1X, infoY)
                infoY = infoY + lh
                if p.moves and #p.moves > 0 then
                    for i, moveId in ipairs(p.moves) do
                        local moveName = tostring(moveId):gsub("_", " "):gsub("(%l)(%w*)", function(a,b) return a:upper()..b end)
                        love.graphics.print("  " .. i .. ". " .. moveName, col1X, infoY)
                        infoY = infoY + lh
                    end
                else
                    love.graphics.print("  (No moves)", col1X, infoY)
                    infoY = infoY + lh
                end

                -- Experience info
                infoY = infoY + lh * 0.5
                local currentExp = p.exp or 0
                local nextLevelExp = 0
                if p.getExpForLevel and type(p.getExpForLevel) == "function" then
                    nextLevelExp = p:getExpForLevel(p.level + 1)
                end
                local expStillNeeded = nextLevelExp - currentExp
                
                love.graphics.print(string.format("EXP: %d / %d", currentExp, nextLevelExp), col1X, infoY)
                infoY = infoY + lh
                love.graphics.print(string.format("To next level: %d", expStillNeeded), col1X, infoY)
                
            elseif M.summaryTab == 2 then
                -- TAB 2: Moves Management
                local leftX = infoX
                local rightX = infoX + summaryBoxW * 0.45
                local moveListY = infoY
                
                -- Header
                love.graphics.setColor(unpack(UI.colors.textDark))
                love.graphics.print("Current Moves", leftX, infoY - lh)
                love.graphics.print("Learnable Moves", rightX, infoY - lh)
                
                -- Draw current moves (left side)
                for i = 1, 4 do
                    local y = moveListY + (i - 1) * lh
                    local moveId = p.moves and p.moves[i]
                    local moveName = moveId and tostring(moveId):gsub("_", " "):gsub("(%l)(%w*)", function(a,b) return a:upper()..b end) or "---"
                    
                    -- Get PP info
                    local ppText = ""
                    if p._move_instances and p._move_instances[i] and type(p._move_instances[i]) == "table" then
                        local inst = p._move_instances[i]
                        ppText = string.format(" PP:%d/%d", inst.pp or 0, inst.maxPP or inst.pp or 0)
                    end
                    
                    -- Highlight the swap source (orange background)
                    if M.summarySwapMode and M.summarySwapSource == "current" and i == M.summarySwapSourceIndex then
                        love.graphics.setColor(1, 0.85, 0.6, 1)
                        love.graphics.rectangle("fill", leftX - 14, y - 1, summaryBoxW * 0.4, lh)
                        love.graphics.setColor(unpack(UI.colors.textHighlight))
                        love.graphics.print("*", leftX - 12, y)
                    end
                    
                    -- Highlight current selection
                    if M.summaryMoveSide == "current" and i == M.summaryMoveSelected then
                        love.graphics.setColor(unpack(UI.colors.textSelected))
                        love.graphics.print(">", leftX - 12, y)
                    else
                        love.graphics.setColor(unpack(UI.colors.textDark))
                    end
                    
                    love.graphics.print(moveName .. ppText, leftX, y)
                end
                
                -- Draw learnable moves (right side)
                local learnableMoves = M.getLearnableMoves(p)
                -- Calculate how many moves can fit in the available space
                local availableHeight = summaryBoxH - (infoY - summaryBoxY) - lh * 2
                local maxVisible = math.max(4, math.floor(availableHeight / lh))
                local startIdx = 1
                if M.summaryLearnableSelected > maxVisible then
                    startIdx = M.summaryLearnableSelected - maxVisible + 1
                end
                
                for i = 1, maxVisible do
                    local moveIdx = startIdx + i - 1
                    local y = moveListY + (i - 1) * lh
                    
                    if moveIdx <= #learnableMoves then
                        local moveId = learnableMoves[moveIdx]
                        local moveName = tostring(moveId):gsub("_", " "):gsub("(%l)(%w*)", function(a,b) return a:upper()..b end)
                        
                        -- Check if already known
                        local alreadyKnown = false
                        for _, m in ipairs(p.moves or {}) do
                            if m == moveId then alreadyKnown = true; break end
                        end
                        
                        -- Highlight the swap source (orange background)
                        if M.summarySwapMode and M.summarySwapSource == "learnable" and moveIdx == M.summarySwapSourceIndex then
                            love.graphics.setColor(1, 0.85, 0.6, 1)
                            love.graphics.rectangle("fill", rightX - 14, y - 1, summaryBoxW * 0.4, lh)
                            love.graphics.setColor(unpack(UI.colors.textHighlight))
                            love.graphics.print("*", rightX - 12, y)
                        end
                        
                        -- Highlight current selection
                        if M.summaryMoveSide == "learnable" and moveIdx == M.summaryLearnableSelected then
                            love.graphics.setColor(unpack(UI.colors.textSelected))
                            love.graphics.print(">", rightX - 12, y)
                        end
                        
                        if alreadyKnown then
                            love.graphics.setColor(unpack(UI.colors.textGray))
                            moveName = moveName .. " (known)"
                        else
                            love.graphics.setColor(unpack(UI.colors.textDark))
                        end
                        love.graphics.print(moveName, rightX, y)
                    end
                end
                
                -- Scroll indicators
                love.graphics.setColor(unpack(UI.colors.textGray))
                if startIdx > 1 then
                    love.graphics.print("^", rightX + summaryBoxW * 0.32, moveListY - lh * 0.5)
                end
                if startIdx + maxVisible - 1 < #learnableMoves then
                    love.graphics.print("v", rightX + summaryBoxW * 0.32, moveListY + maxVisible * lh - lh * 0.5)
                end
                
                -- Instructions
                local instructY = summaryBoxY + summaryBoxH - lh - 10
                if M.summarySwapMode then
                    love.graphics.setColor(unpack(UI.colors.textHighlight))
                    if M.summarySwapSource == "current" then
                        love.graphics.printf("Select move to swap with (Space to cancel)", summaryBoxX, instructY, summaryBoxW, "center")
                    else
                        love.graphics.printf("Select move to replace (Space to cancel)", summaryBoxX, instructY, summaryBoxW, "center")
                    end
                else
                    love.graphics.setColor(unpack(UI.colors.textGray))
                    love.graphics.printf("Z: select move | Left/Right: switch side", summaryBoxX, instructY, summaryBoxW, "center")
                end
                
            elseif M.summaryTab == 3 then
                -- TAB 3: IVs and EVs
                local col1X = infoX
                local col2X = infoX + summaryBoxW * 0.35
                local col3X = infoX + summaryBoxW * 0.6
                
                -- Headers
                love.graphics.setColor(unpack(UI.colors.textGray))
                love.graphics.print("Stat", col1X, infoY)
                love.graphics.print("IV", col2X, infoY)
                love.graphics.print("EV", col3X, infoY)
                infoY = infoY + lh
                
                local statNames = {
                    {key = "hp", display = "HP"},
                    {key = "attack", display = "Attack"},
                    {key = "defense", display = "Defense"},
                    {key = "spAttack", display = "Sp. Atk"},
                    {key = "spDefense", display = "Sp. Def"},
                    {key = "speed", display = "Speed"}
                }
                
                local totalIV = 0
                local totalEV = 0
                
                for _, stat in ipairs(statNames) do
                    local iv = (p.ivs and p.ivs[stat.key]) or 0
                    local ev = (p.evs and p.evs[stat.key]) or 0
                    totalIV = totalIV + iv
                    totalEV = totalEV + ev
                    
                    love.graphics.setColor(unpack(UI.colors.textDark))
                    love.graphics.print(stat.display, col1X, infoY)
                    
                    -- Color code IVs (31 = perfect = gold, 25+ = green, 0-5 = red)
                    if iv >= 31 then
                        love.graphics.setColor(0.1, 0.7, 0.1, 1)  -- Green for perfect
                    elseif iv >= 25 then
                        love.graphics.setColor(0.3, 0.6, 0.3, 1)  -- Light green
                    elseif iv <= 5 then
                        love.graphics.setColor(0.8, 0.2, 0.2, 1)  -- Red for bad
                    else
                        love.graphics.setColor(unpack(UI.colors.textDark))
                    end
                    love.graphics.print(tostring(iv), col2X, infoY)
                    
                    love.graphics.setColor(unpack(UI.colors.textDark))
                    love.graphics.print(tostring(ev), col3X, infoY)
                    infoY = infoY + lh
                end
                
                -- Totals
                infoY = infoY + lh * 0.5
                love.graphics.setColor(unpack(UI.colors.textGray))
                love.graphics.print("Totals:", col1X, infoY)
                love.graphics.setColor(unpack(UI.colors.textDark))
                love.graphics.print(tostring(totalIV) .. "/186", col2X, infoY)
                love.graphics.print(tostring(totalEV) .. "/510", col3X, infoY)
            end
            
            -- Navigation hint at bottom
            love.graphics.setColor(unpack(UI.colors.textGray))
            love.graphics.printf("<- -> Tabs | Up/Down: Switch Pokemon | Z: Exit", summaryBoxX, summaryBoxY + summaryBoxH - lh - 10, summaryBoxW, "center")
            
            love.graphics.pop()
            return
        end
        
        -- Pokemon list (not details view)
        local pokeBoxW = ww * 0.9
        local pokeBoxH = hh * 0.8
        local pokeBoxX = (ww - pokeBoxW) / 2
        local pokeBoxY = hh * 0.1
        UI.drawBoxWithShadow(pokeBoxX, pokeBoxY, pokeBoxW, pokeBoxH)
        
        -- Pokemon list title
        love.graphics.setColor(unpack(UI.colors.textDark))
        if M.pokemonMoveMode then
            love.graphics.printf("MOVE POKEMON", pokeBoxX, pokeBoxY + 12, pokeBoxW, "center")
            love.graphics.setColor(unpack(UI.colors.textHighlight))
            love.graphics.printf("Select Pokemon to swap with", pokeBoxX, pokeBoxY + 12 + lh * 0.7, pokeBoxW, "center")
        else
            love.graphics.printf("POKEMON", pokeBoxX, pokeBoxY + 12, pokeBoxW, "center")
        end
        
        local listY = pokeBoxY + 20 + lh * 1.5
        local listX = pokeBoxX + 150
        
        if count == 0 then
            love.graphics.setColor(unpack(UI.colors.textGray))
            love.graphics.print("No Pokemon", listX, listY)
            -- draw Back option below
            local backY = listY + lh
            UI.drawOption("Back", listX, backY, M.pokemonSelected == 1)
        else
            for i, p in ipairs(M.player.party) do
                local y = listY + (i-1) * lh * 1.5
                
                -- Highlight the first selected Pokemon in move mode
                if M.pokemonMoveMode and i == M.pokemonMoveFirst then
                    love.graphics.setColor(0.85, 0.9, 1, 1)
                    love.graphics.rectangle("fill", listX - 15, y - 2, pokeBoxW - 30, lh * 1.5)
                end
                
                -- Draw small sprite thumbnail
                local spriteSize = lh * 1.5
                local spriteX = listX - spriteSize - 20
                drawPokemonSprite(p, spriteX, y - 2, spriteSize, spriteSize, false)
                
                local name = tostring(p.nickname or p.name or "Unknown")
                local lvl = tostring(p.level or "?")
                local hp = tostring(p.currentHP or 0)
                local max = tostring(p.stats and p.stats.hp or "?")
                local statusStr = UI.getStatusString(p)
                local line = string.format("%s  Lv%s  HP:%s/%s", name, lvl, hp, max)
                if statusStr then line = line .. "  [" .. statusStr .. "]" end
                UI.drawOption(line, listX, y, i == M.pokemonSelected)
            end
            
            -- Back option (not shown in move mode)
            if not M.pokemonMoveMode then
                local by = listY + count * lh * 1.5
                UI.drawOption("Back", listX, by, M.pokemonSelected == count + 1)
            end
        end
        
        -- Draw Pokemon action submenu overlay
        if M.pokemonActionMenuOpen then
            local menuW = ww * 0.28
            local menuH = lh * (#M.pokemonActionOptions + 0.5) + 15
            local menuX = pokeBoxX + pokeBoxW - menuW - 15
            local menuY = pokeBoxY + pokeBoxH - menuH - 15
            UI.drawActionMenu(M.pokemonActionOptions, M.pokemonActionSelected, menuX, menuY, menuW, menuH)
        end
    else
        -- Main menu options - Pokemon style box
        local mainBoxW = ww * 0.35
        local mainBoxH = lh * (#M.options) + 30
        local mainBoxX = ww - mainBoxW - 15
        local mainBoxY = 15
        
        UI.drawBoxWithShadow(mainBoxX, mainBoxY, mainBoxW, mainBoxH)
        
        local mainListX = mainBoxX + 25
        local mainListY = mainBoxY + 15
        
        for i, opt in ipairs(M.options) do
            local y = mainListY + (i - 1) * lh
            UI.drawOption(opt, mainListX, y, i == M.selected)
        end
    end

    love.graphics.pop()
end

return M
