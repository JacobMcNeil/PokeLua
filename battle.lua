local M = {}
local log = require("log")
local UI = require("ui")

M.active = false
M.p1 = nil
M.p2 = nil
M.menuOptions = { "Fight", "Pokemon", "Items", "Run" }
M.selectedOption = 1
M.mode = "menu" -- or "moves" or "items" or "choose_pokemon"
M.moveOptions = {}
M.battleLog = {}
M.maxLogLines = 1
M.logQueue = {}
M.waitingForZ = false
M.awaitingClose = false
M.faintedName = nil
M.player = nil
M.chooseIndex = 1
M.participatingPokemon = {} -- Tracks which Pokémon have participated in the battle
M.lastUsedMoveSlot = 1 -- Track which move slot was last used for cursor persistence
M.battleItems = {} -- Available items in battle
M.itemSelected = nil -- Currently selected item to use
M.itemSelectMode = false -- Whether we're selecting a target for an item
M.battleItemCategories = {"medicine", "pokeball", "battle_item", "key_item", "tm", "berry"}
M.battleCurrentCategory = 1 -- index into battleItemCategories
M.battleCategoryItems = {} -- Items in current category

-- Trainer battle state
M.isTrainerBattle = false -- true if fighting a trainer, false if wild Pokemon
M.trainer = nil -- The trainer object (if trainer battle)
M.trainerDefeated = false -- Track if trainer is out of Pokemon

-- Whiteout state
M.playerWhitedOut = false -- Set to true when player loses and needs to be teleported
M.whiteoutCallback = nil -- Callback function to handle teleporting the player

-- Animation state for HP and EXP bars
M.p1AnimatedHP = 0
M.p2AnimatedHP = 0
M.p1AnimatedExp = 0

-- Attack animation state
M.attackAnimating = false  -- true when an attack animation is playing
M.attackAnimTarget = nil   -- "p1" or "p2" - which Pokemon is attacking
M.attackAnimType = "damage" -- "damage" or "status"
M.attackAnimTime = 0       -- current animation time
M.attackAnimDuration = 0.3 -- duration of attack animation in seconds
M.attackAnimOffset = { x = 0, y = 0 } -- current offset to apply to sprite

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

-- Helper function to resolve a move name/object to a Move instance
local function resolveMoveInstance(mv)
    if not mv then return nil end
    if type(mv) == "table" then
        -- Check if this is already a Move instance (has either use or pp)
        log.log("resolveMoveInstance: got table, checking for use/pp")
        if mv.use and type(mv.use) == "function" then 
            log.log("  found use method, returning move instance")
            return mv 
        end
        if mv.pp then 
            log.log("  found pp property, returning move instance")
            return mv 
        end
        if mv.name then
            log.log("  has name property: ", mv.name)
        end
        if mv.new and type(mv.new) == "function" then
            local ok, inst = pcall(function() return mv:new() end)
            if ok and inst then return inst end
        end
    end
    if type(mv) == "string" or (type(mv) == "table" and mv.name) then
        local mvname = type(mv) == "string" and mv or mv.name
        log.log("resolveMoveInstance: trying to resolve ", mvname)
        local ok, mm = pcall(require, "moves")
        if ok and mm then
            local key = mvname
            local norm = mvname:gsub("%s+", "")
            local norm2 = norm:gsub("%p", "")
            local lkey = string.lower(key)
            local lnorm = string.lower(norm)
            local lnorm2 = string.lower(norm2)
            log.log("  trying keys: ", key, " / ", norm, " / ", norm2, " / ", lkey, " / ", lnorm, " / ", lnorm2)
            local cls = mm[key] or mm[norm] or mm[norm2] or mm[lkey] or mm[lnorm] or mm[lnorm2]
            log.log("  found class: ", cls)
            if cls and type(cls) == "table" and cls.new then
                log.log("  attempting to instantiate move class")
                local suc, inst = pcall(function() return cls:new() end)
                log.log("  instantiation result: suc=", suc, " inst=", inst)
                if suc and inst then return inst end
            elseif mm.Move and mm.Move.new then
                log.log("  creating generic move from name")
                local suc, inst = pcall(function() return mm.Move:new({ name = mvname }) end)
                log.log("  generic move result: suc=", suc, " inst=", inst)
                if suc and inst then return inst end
            end
        end
    end
    return nil
end

-- Helper function to rebuild move instances for a Pokemon (used when moves change)
local function refreshMoveInstances(p)
    if not p then return end
    
    -- Save current PP values before refreshing
    local savedPP = {}
    if p._move_instances then
        for i = 1, 4 do
            local inst = p._move_instances[i]
            if type(inst) == "table" and inst.pp then
                savedPP[i] = inst.pp
            end
        end
    end
    
    local arr = {}
    if p.moves and #p.moves > 0 then
        for i = 1, 4 do
            local mv = p.moves[i]
            local inst = resolveMoveInstance(mv)
            if inst then
                inst.maxPP = inst.maxPP or inst.pp
                -- Restore saved PP if it exists, otherwise use max
                if savedPP[i] then
                    inst.pp = savedPP[i]
                elseif inst.maxPP and (inst.pp == nil) then
                    inst.pp = inst.maxPP
                end
            end
            arr[i] = inst or ""
        end
    else
        for i = 1, 4 do arr[i] = "" end
    end
    p._move_instances = arr
end

-- Helper function to refresh battle items for the current category
function M.refreshBattleCategoryItems()
    M.battleCategoryItems = {}
    if M.player and M.player.bag then
        local category = M.battleItemCategories[M.battleCurrentCategory]
        local items = M.player.bag[category] or {}
        for itemId, item in pairs(items) do
            if item and item.quantity and item.quantity > 0 then
                table.insert(M.battleCategoryItems, item)
            end
        end
    end
    M.selectedOption = 1
end

local function queueLog(entry)
    if not entry then return end
    local item
    if type(entry) == "table" then
        if entry.text then
            -- Entry with text and action
            item = { text = entry.text, action = entry.action or function() end }
            table.insert(M.logQueue, item)
        elseif #entry > 0 then
            -- Array of messages - queue each one
            for _, msg in ipairs(entry) do
                if type(msg) == "string" and msg ~= "" then
                    table.insert(M.logQueue, { text = msg, action = function() end })
                elseif type(msg) == "table" and msg.text then
                    table.insert(M.logQueue, { text = msg.text, action = msg.action or function() end })
                end
            end
            return -- Already inserted, don't insert again below
        else
            -- Table without text or array items - skip or log warning
            log.log("queueLog: received table without .text property, skipping")
            return
        end
    else
        item = { text = tostring(entry), action = function() end }
        table.insert(M.logQueue, item)
    end
    if #M.logQueue > 200 then table.remove(M.logQueue, 1) end
end

-- Note: leveling up is now handled through the experience system in Pokemon.gainExp()
-- when a Pokémon defeats another, it gains experience that may trigger level ups

-- Queue a move as a log entry with a deferred action. The action runs when the
-- player acknowledges the log (presses Z). If `after_cb` is provided it will
-- be invoked by the action after the move effects are applied and the target
-- remains alive.
local function queueMove(attacker, defender, mvname, after_cb)
    if not attacker or not defender then
        return
    end
    local mvlabel = tostring(mvname)
    local mvobj = resolveMoveInstance(mvname)
    if type(mvobj) == "table" and mvobj.name then mvlabel = mvobj.name end

    local function action()
        local a_hp = attacker.currentHP or 0
        local d_hp = defender.currentHP or 0
        -- don't act if attacker already fainted
        if attacker and (attacker.currentHP or 0) <= 0 then
            queueLog((attacker.nickname or "attacker") .. " can't move (fainted)")
            return
        end
        if not mvname or mvname == "" then
            queueLog((attacker.nickname or "attacker") .. " has no move")
            return
        end

        -- Fix broken instances: if mvobj has pp but not use, it might be a stale instance with broken metatable
        -- Try to recreate it or access use through metatable
        if type(mvobj) == "table" and mvobj.pp and not mvobj.use then
            log.log("battle: detected stale move instance, attempting to fix")
            -- Try to look up use in the metatable chain
            local mt = getmetatable(mvobj)
            if mt and mt.__index then
                local idx = mt.__index
                if type(idx) == "table" and idx.use then
                    log.log("  found use in metatable, patching instance")
                    mvobj.use = idx.use
                end
            end
        end

        -- Apply move damage or effects
        local moveSuccessful = false
        
        -- Load moves module for special move handling
        local ok_mvmod, mvModule = pcall(require, "moves")
        
        -- Handle charging moves (first turn = charge, second turn = attack)
        if type(mvobj) == "table" and mvobj.isChargingMove then
            if attacker.charging then
                -- Second turn - execute the attack and clear charging state
                if mvModule then mvModule.completeCharging(attacker) end
                -- Continue to normal move execution below
            else
                -- First turn - start charging
                if mvModule then
                    local chargeMsg = mvobj.chargeMessage or "is charging power!"
                    local attackerName = attacker.nickname or attacker.name or "Pokemon"
                    mvModule.startCharging(attacker, mvobj, attackerName .. " " .. chargeMsg)
                    
                    -- Apply charge effect if any (e.g., Skull Bash raises Defense)
                    if mvobj.chargeEffect then
                        mvobj.chargeEffect(attacker)
                    end
                end
                
                -- Show charge messages
                local effectMsgs = mvModule and mvModule.getEffectMessages() or {}
                for _, msg in ipairs(effectMsgs) do
                    queueLog(msg)
                end
                
                -- Return to menu/next turn without attacking
                if after_cb then after_cb() end
                return
            end
        end
        
        -- Handle locked/rampage moves (Thrash, Outrage, Petal Dance)
        if type(mvobj) == "table" and mvobj.isLockedMove then
            if not attacker.lockedMove then
                -- First use - start the locked move
                if mvModule then
                    mvModule.startLockedMove(attacker, mvobj, mvobj.lockedTurnsMin or 2, mvobj.lockedTurnsMax or 3)
                end
            end
            -- Continue to execute the move, decrement will happen after
        end
        
        -- Reset protect count if not using a protect-type move
        if type(mvobj) == "table" and not mvobj.isProtectMove then
            if mvModule then mvModule.resetProtectCount(attacker) end
        end
        
        if type(mvobj) == "table" then
            -- Trigger attack animation
            local animType = "damage" -- default to damage animation
            if mvobj.category == "status" or mvobj.power == 0 or not mvobj.power then
                animType = "status"
            end
            M.attackAnimating = true
            M.attackAnimTarget = (attacker == M.p1) and "p1" or "p2"
            M.attackAnimType = animType
            M.attackAnimTime = 0
            
            -- Try to call use method (handles both direct and metatable access)
            local ok, result = pcall(function() return mvobj:use(attacker, defender, M) end)
            if ok and result then
                moveSuccessful = true
                log.log("battle: move executed successfully: ", mvobj.name or "unknown")
                log.log("  result.message: ", result.message or "nil")
                log.log("  result.damage: ", result.damage or "nil")
                if result.message then
                    queueLog(result.message)
                end
                -- Display any effect messages (stat changes, status effects, etc.)
                if result.effectMessages and #result.effectMessages > 0 then
                    for _, effectMsg in ipairs(result.effectMessages) do
                        queueLog(effectMsg)
                    end
                end
            else
                log.log("battle: move execution failed. ok=", ok, " result=", result)
            end
        end
        
        if not moveSuccessful then
            -- Trigger attack animation for fallback damage
            M.attackAnimating = true
            M.attackAnimTarget = (attacker == M.p1) and "p1" or "p2"
            M.attackAnimType = "damage"
            M.attackAnimTime = 0
            
            -- Default damage
            log.log("battle: using fallback 20 damage. mvobj type=", type(mvobj))
            if type(mvobj) == "table" then
                log.log("  mvobj.use=", mvobj.use, " mvobj.pp=", mvobj.pp, " mvobj.name=", mvobj.name)
            end
            local dmg = 20
            defender.currentHP = (defender.currentHP or 0) - dmg
            if defender.currentHP < 0 then defender.currentHP = 0 end
            queueLog((attacker.nickname or tostring(attacker)) .. " used " .. mvlabel .. "! It dealt " .. tostring(dmg) .. " damage.")
        end
        
        -- Handle locked move continuation/ending
        if type(mvobj) == "table" and mvobj.isLockedMove and attacker.lockedMove then
            local continues = mvModule and mvModule.continueLockedMove(attacker)
            if not continues then
                -- Move ended, confusion is applied by continueLockedMove
                local effectMsgs = mvModule and mvModule.getEffectMessages() or {}
                for _, msg in ipairs(effectMsgs) do
                    queueLog(msg)
                end
            end
        end
        
        -- Check if attacker fainted from recoil
        if attacker.currentHP and attacker.currentHP <= 0 then
            local attackerName = attacker.nickname or attacker.name or "Pokemon"
            queueLog(attackerName .. " fainted!")
        end

        -- Check if defender fainted after the move
        if defender.currentHP and defender.currentHP <= 0 then
            local faint_text = (defender.nickname or "target") .. " fainted"
            queueLog({ text = faint_text, action = function()
                
                -- Award experience to all participating Pokémon (shared equally)
                if defender == M.p2 and M.participatingPokemon and #M.participatingPokemon > 0 then
                    local ok, pmod = pcall(require, "pokemon")
                    if ok and pmod and pmod.Pokemon then
                        -- Calculate base exp yield from the defeated Pokémon
                        local totalExpYield = pmod.Pokemon.calculateExpYield(defender, attacker.level)
                        -- Split equally among all participating Pokémon
                        local expShare = math.floor(totalExpYield / #M.participatingPokemon)
                        
                        for _, participatingPoke in ipairs(M.participatingPokemon) do
                            if participatingPoke and participatingPoke.gainExp and type(participatingPoke.gainExp) == "function" then
                                -- Capture moves before gaining exp to detect newly learned moves
                                local movesBefore = {}
                                if participatingPoke.moves then
                                    for _, m in ipairs(participatingPoke.moves) do
                                        movesBefore[m] = true
                                    end
                                end
                                
                                local levelsGained, pendingEvolution = participatingPoke:gainExp(expShare)
                                queueLog((participatingPoke.nickname or "Pokémon") .. " gained " .. expShare .. " Exp. Points!")
                                
                                -- Log each level up that occurred
                                if levelsGained and #levelsGained > 0 then
                                    for _, newLevel in ipairs(levelsGained) do
                                        queueLog((participatingPoke.nickname or "Pokémon") .. " grew to level " .. newLevel .. "!")
                                    end
                                    -- Check for newly learned moves
                                    if participatingPoke.moves then
                                        for _, move in ipairs(participatingPoke.moves) do
                                            if not movesBefore[move] then
                                                -- Format move name (convert "thunder_shock" to "Thunder Shock")
                                                local moveName = move:gsub("_", " "):gsub("(%l)(%w*)", function(a,b) return a:upper()..b end)
                                                queueLog((participatingPoke.nickname or "Pokémon") .. " learned " .. moveName .. "!")
                                            end
                                        end
                                    end
                                    -- Refresh move instances if moves were learned
                                    refreshMoveInstances(participatingPoke)
                                end
                                
                                -- Handle evolution if pending
                                if pendingEvolution then
                                    local oldName = participatingPoke.nickname
                                    local success, evoMessage = participatingPoke:evolve(pendingEvolution)
                                    if success then
                                        queueLog("What? " .. oldName .. " is evolving!")
                                        queueLog(evoMessage)
                                        -- Refresh move instances after evolution
                                        refreshMoveInstances(participatingPoke)
                                    end
                                end
                            end
                        end
                    end
                end
                if defender == M.p1 then
                    local party = (M.player and M.player.party) or nil
                    local hasAlive = false
                    if party then
                        for _, pp in ipairs(party) do if pp and (pp.currentHP or 0) > 0 then hasAlive = true; break end end
                    end
                    if hasAlive then
                        M.mode = "choose_pokemon"
                        M.chooseIndex = 1
                        M.faintedName = M.p1 and M.p1.nickname or "Player"
                    else
                        -- Player has no more Pokemon - they white out
                        local lostMoney = M.triggerWhiteout()
                        if M.isTrainerBattle and M.trainer then
                            queueLog({ text = "You have no more Pokémon that can fight!", action = function()
                                queueLog({ text = "You lost to " .. M.trainer:getDisplayName() .. "!", action = function()
                                    queueLog({ text = "You blacked out!", action = function()
                                        if lostMoney and lostMoney > 0 then
                                            queueLog({ text = "You lost $" .. tostring(lostMoney) .. "...", action = function()
                                                M.awaitingClose = true
                                                M.faintedName = nil
                                            end })
                                        else
                                            M.awaitingClose = true
                                            M.faintedName = nil
                                        end
                                    end })
                                end })
                            end })
                        else
                            -- Wild battle whiteout
                            queueLog({ text = "You have no more Pokémon that can fight!", action = function()
                                queueLog({ text = "You blacked out!", action = function()
                                    if lostMoney and lostMoney > 0 then
                                        queueLog({ text = "You lost $" .. tostring(lostMoney) .. "...", action = function()
                                            M.awaitingClose = true
                                            M.faintedName = nil
                                        end })
                                    else
                                        M.awaitingClose = true
                                        M.faintedName = nil
                                    end
                                end })
                            end })
                        end
                    end
                elseif defender == M.p2 then
                    -- Check if this is a trainer battle and trainer has more Pokemon
                    if M.isTrainerBattle and M.trainer and M.trainer:hasAlivePokemon() then
                        -- Trainer sends out next Pokemon
                        local nextPokemon = M.trainer:getNextAlivePokemon()
                        if nextPokemon then
                            queueLog({ text = M.trainer:getDisplayName() .. " is about to send out " .. (nextPokemon.nickname or nextPokemon.name) .. "!", action = function()
                                M.p2 = nextPokemon
                                -- Reset animated HP for the new opponent Pokemon
                                M.p2AnimatedHP = M.p2.currentHP or 0
                                
                                -- Initialize stat stages for the new Pokemon
                                local ok_moves, movesModule = pcall(require, "moves")
                                if ok_moves and movesModule and movesModule.initStatStages then
                                    movesModule.initStatStages(M.p2)
                                end
                                
                                -- Ensure the new Pokemon has move instances
                                if not M.p2._move_instances then
                                    local arr = {}
                                    if M.p2.moves and #M.p2.moves > 0 then
                                        for i = 1, 4 do
                                            local mv = M.p2.moves[i]
                                            local inst = resolveMoveInstance(mv)
                                            if inst then
                                                inst.maxPP = inst.maxPP or inst.pp
                                                if inst.maxPP and (inst.pp == nil) then inst.pp = inst.maxPP end
                                            end
                                            arr[i] = inst or ""
                                        end
                                    else
                                        for i = 1, 4 do arr[i] = "" end
                                    end
                                    M.p2._move_instances = arr
                                end
                                queueLog(M.trainer:getDisplayName() .. " sent out " .. (nextPokemon.nickname or nextPokemon.name) .. "!")
                                -- Return to menu for next turn
                                M.mode = "menu"
                                M.selectedOption = 1
                                M.moveOptions = {}
                            end })
                        else
                            M.awaitingClose = true
                            M.faintedName = M.p2 and M.p2.nickname or "Opponent"
                        end
                    else
                        -- Wild battle or trainer out of Pokemon - battle ends
                        if M.isTrainerBattle and M.trainer then
                            M.trainerDefeated = true
                            M.trainer:setDefeated()
                            -- Award prize money
                            local prizeMoney = M.trainer:getPrizeMoney()
                            if M.player then
                                M.player.money = (M.player.money or 0) + prizeMoney
                            end
                            queueLog({ text = "You defeated " .. M.trainer:getDisplayName() .. "!", action = function()
                                queueLog({ text = M.trainer.defeatMessage or "...", action = function()
                                    queueLog({ text = "You received $" .. tostring(prizeMoney) .. " for winning!", action = function()
                                        M.awaitingClose = true
                                        M.faintedName = nil
                                    end })
                                end })
                            end })
                        else
                            M.awaitingClose = true
                            M.faintedName = M.p2 and M.p2.nickname or "Opponent"
                        end
                    end
                end
            end })
            return
        end

        -- If there's an after-callback and the defender survived, call it to queue the next action
        if after_cb then
            if not (defender.currentHP and defender.currentHP <= 0) then
                after_cb()
            end
        else
            -- end of turn: apply status effects (burn, poison, leech seed, etc.)
            local ok_moves, movesModule = pcall(require, "moves")
            if ok_moves and movesModule then
                -- Reset protect status at end of turn
                if movesModule.resetProtect then
                    movesModule.resetProtect(attacker)
                    movesModule.resetProtect(defender)
                end
                
                -- Clear enduring status at end of turn
                if attacker then attacker.enduring = nil end
                if defender then defender.enduring = nil end
                
                if movesModule.applyEndOfTurnEffects then
                    -- Apply end of turn effects to attacker (player's Pokemon)
                    if attacker and (attacker.currentHP or 0) > 0 then
                        local attackerMsgs = movesModule.applyEndOfTurnEffects(attacker, M)
                        if attackerMsgs then
                            for _, msg in ipairs(attackerMsgs) do
                                queueLog(msg)
                            end
                        end
                        -- Check if attacker fainted from status damage
                        if attacker.currentHP and attacker.currentHP <= 0 then
                        local faint_text = (attacker.nickname or "Pokemon") .. " fainted!"
                        queueLog({ text = faint_text, action = function()
                            -- Handle faint properly - check if it's player or opponent
                            if attacker == M.p1 then
                                -- Player's Pokemon fainted from status
                                local party = (M.player and M.player.party) or nil
                                local hasAlive = false
                                if party then
                                    for _, pp in ipairs(party) do if pp and (pp.currentHP or 0) > 0 then hasAlive = true; break end end
                                end
                                if hasAlive then
                                    M.mode = "choose_pokemon"
                                    M.chooseIndex = 1
                                    M.faintedName = M.p1 and M.p1.nickname or "Player"
                                else
                                    -- Player lost - no more Pokemon - white out
                                    local lostMoney = M.triggerWhiteout()
                                    if M.isTrainerBattle and M.trainer then
                                        queueLog({ text = "You have no more Pokémon that can fight!", action = function()
                                            queueLog({ text = "You lost to " .. M.trainer:getDisplayName() .. "!", action = function()
                                                queueLog({ text = "You blacked out!", action = function()
                                                    if lostMoney and lostMoney > 0 then
                                                        queueLog({ text = "You lost $" .. tostring(lostMoney) .. "...", action = function()
                                                            M.awaitingClose = true
                                                            M.faintedName = nil
                                                        end })
                                                    else
                                                        M.awaitingClose = true
                                                        M.faintedName = nil
                                                    end
                                                end })
                                            end })
                                        end })
                                    else
                                        -- Wild battle whiteout
                                        queueLog({ text = "You have no more Pokémon that can fight!", action = function()
                                            queueLog({ text = "You blacked out!", action = function()
                                                if lostMoney and lostMoney > 0 then
                                                    queueLog({ text = "You lost $" .. tostring(lostMoney) .. "...", action = function()
                                                        M.awaitingClose = true
                                                        M.faintedName = nil
                                                    end })
                                                else
                                                    M.awaitingClose = true
                                                    M.faintedName = nil
                                                end
                                            end })
                                        end })
                                    end
                                end
                            elseif attacker == M.p2 then
                                -- Opponent's Pokemon fainted from status
                                if M.isTrainerBattle and M.trainer and M.trainer:hasAlivePokemon() then
                                    -- Trainer sends out next Pokemon
                                    local nextPokemon = M.trainer:getNextAlivePokemon()
                                    if nextPokemon then
                                        queueLog({ text = M.trainer:getDisplayName() .. " is about to send out " .. (nextPokemon.nickname or nextPokemon.name) .. "!", action = function()
                                            M.p2 = nextPokemon
                                            M.p2AnimatedHP = M.p2.currentHP or 0
                                            
                                            local ok_moves2, movesModule2 = pcall(require, "moves")
                                            if ok_moves2 and movesModule2 and movesModule2.initStatStages then
                                                movesModule2.initStatStages(M.p2)
                                            end
                                            
                                            if not M.p2._move_instances then
                                                local arr = {}
                                                if M.p2.moves and #M.p2.moves > 0 then
                                                    for i = 1, 4 do
                                                        local mv = M.p2.moves[i]
                                                        local inst = resolveMoveInstance(mv)
                                                        if inst then
                                                            inst.maxPP = inst.maxPP or inst.pp
                                                            if inst.maxPP and (inst.pp == nil) then inst.pp = inst.maxPP end
                                                        end
                                                        arr[i] = inst or ""
                                                    end
                                                else
                                                    for i = 1, 4 do arr[i] = "" end
                                                end
                                                M.p2._move_instances = arr
                                            end
                                            queueLog(M.trainer:getDisplayName() .. " sent out " .. (nextPokemon.nickname or nextPokemon.name) .. "!")
                                            M.mode = "menu"
                                            M.selectedOption = 1
                                            M.moveOptions = {}
                                        end })
                                    else
                                        M.awaitingClose = true
                                        M.faintedName = M.p2 and M.p2.nickname or "Opponent"
                                    end
                                else
                                    -- Wild battle or trainer out of Pokemon
                                    if M.isTrainerBattle and M.trainer then
                                        M.trainerDefeated = true
                                        M.trainer:setDefeated()
                                        local prizeMoney = M.trainer:getPrizeMoney()
                                        if M.player then
                                            M.player.money = (M.player.money or 0) + prizeMoney
                                        end
                                        queueLog({ text = "You defeated " .. M.trainer:getDisplayName() .. "!", action = function()
                                            queueLog({ text = "You won $" .. tostring(prizeMoney) .. "!", action = function()
                                                M.awaitingClose = true
                                                M.faintedName = nil
                                            end })
                                        end })
                                    else
                                        M.awaitingClose = true
                                        M.faintedName = M.p2 and M.p2.nickname or "Opponent"
                                    end
                                end
                            end
                        end })
                        return  -- Don't continue to menu if someone fainted
                    end
                end
                
                -- Also apply end of turn effects to defender (opponent's Pokemon)
                if defender and (defender.currentHP or 0) > 0 then
                    local defenderMsgs = movesModule.applyEndOfTurnEffects(defender, M)
                    if defenderMsgs then
                        for _, msg in ipairs(defenderMsgs) do
                            queueLog(msg)
                        end
                    end
                    -- Check if defender fainted from status damage
                    if defender.currentHP and defender.currentHP <= 0 then
                        local faint_text = (defender.nickname or "Pokemon") .. " fainted!"
                        queueLog({ text = faint_text, action = function()
                            -- Handle faint properly - check if it's player or opponent
                            if defender == M.p1 then
                                -- Player's Pokemon fainted from status
                                local party = (M.player and M.player.party) or nil
                                local hasAlive = false
                                if party then
                                    for _, pp in ipairs(party) do if pp and (pp.currentHP or 0) > 0 then hasAlive = true; break end end
                                end
                                if hasAlive then
                                    M.mode = "choose_pokemon"
                                    M.chooseIndex = 1
                                    M.faintedName = M.p1 and M.p1.nickname or "Player"
                                else
                                    -- Player lost - no more Pokemon - white out
                                    local lostMoney = M.triggerWhiteout()
                                    if M.isTrainerBattle and M.trainer then
                                        queueLog({ text = "You have no more Pokémon that can fight!", action = function()
                                            queueLog({ text = "You lost to " .. M.trainer:getDisplayName() .. "!", action = function()
                                                queueLog({ text = "You blacked out!", action = function()
                                                    if lostMoney and lostMoney > 0 then
                                                        queueLog({ text = "You lost $" .. tostring(lostMoney) .. "...", action = function()
                                                            M.awaitingClose = true
                                                            M.faintedName = nil
                                                        end })
                                                    else
                                                        M.awaitingClose = true
                                                        M.faintedName = nil
                                                    end
                                                end })
                                            end })
                                        end })
                                    else
                                        -- Wild battle whiteout
                                        queueLog({ text = "You have no more Pokémon that can fight!", action = function()
                                            queueLog({ text = "You blacked out!", action = function()
                                                if lostMoney and lostMoney > 0 then
                                                    queueLog({ text = "You lost $" .. tostring(lostMoney) .. "...", action = function()
                                                        M.awaitingClose = true
                                                        M.faintedName = nil
                                                    end })
                                                else
                                                    M.awaitingClose = true
                                                    M.faintedName = nil
                                                end
                                            end })
                                        end })
                                    end
                                end
                            elseif defender == M.p2 then
                                -- Opponent's Pokemon fainted from status
                                if M.isTrainerBattle and M.trainer and M.trainer:hasAlivePokemon() then
                                    -- Trainer sends out next Pokemon
                                    local nextPokemon = M.trainer:getNextAlivePokemon()
                                    if nextPokemon then
                                        queueLog({ text = M.trainer:getDisplayName() .. " is about to send out " .. (nextPokemon.nickname or nextPokemon.name) .. "!", action = function()
                                            M.p2 = nextPokemon
                                            M.p2AnimatedHP = M.p2.currentHP or 0
                                            
                                            local ok_moves2, movesModule2 = pcall(require, "moves")
                                            if ok_moves2 and movesModule2 and movesModule2.initStatStages then
                                                movesModule2.initStatStages(M.p2)
                                            end
                                            
                                            if not M.p2._move_instances then
                                                local arr = {}
                                                if M.p2.moves and #M.p2.moves > 0 then
                                                    for i = 1, 4 do
                                                        local mv = M.p2.moves[i]
                                                        local inst = resolveMoveInstance(mv)
                                                        if inst then
                                                            inst.maxPP = inst.maxPP or inst.pp
                                                            if inst.maxPP and (inst.pp == nil) then inst.pp = inst.maxPP end
                                                        end
                                                        arr[i] = inst or ""
                                                    end
                                                else
                                                    for i = 1, 4 do arr[i] = "" end
                                                end
                                                M.p2._move_instances = arr
                                            end
                                            queueLog(M.trainer:getDisplayName() .. " sent out " .. (nextPokemon.nickname or nextPokemon.name) .. "!")
                                            M.mode = "menu"
                                            M.selectedOption = 1
                                            M.moveOptions = {}
                                        end })
                                    else
                                        M.awaitingClose = true
                                        M.faintedName = M.p2 and M.p2.nickname or "Opponent"
                                    end
                                else
                                    -- Wild battle or trainer out of Pokemon
                                    if M.isTrainerBattle and M.trainer then
                                        M.trainerDefeated = true
                                        M.trainer:setDefeated()
                                        local prizeMoney = M.trainer:getPrizeMoney()
                                        if M.player then
                                            M.player.money = (M.player.money or 0) + prizeMoney
                                        end
                                        queueLog({ text = "You defeated " .. M.trainer:getDisplayName() .. "!", action = function()
                                            queueLog({ text = "You won $" .. tostring(prizeMoney) .. "!", action = function()
                                                M.awaitingClose = true
                                                M.faintedName = nil
                                            end })
                                        end })
                                    else
                                        M.awaitingClose = true
                                        M.faintedName = M.p2 and M.p2.nickname or "Opponent"
                                    end
                                end
                            end
                        end })
                        return  -- Don't continue to menu if someone fainted
                    end
                end
                end
            end
            
            -- end of turn: if nobody fainted and we're not in choose_pokemon, return to menu
            if M.active and not M.awaitingClose and M.mode ~= "choose_pokemon" then
                M.mode = "menu"
                M.selectedOption = 1
                M.moveOptions = {}
                M.awaitingClose = false
                M.faintedName = nil
            end
        end
    end

    -- Check if the attacker can move BEFORE showing "used" message
    -- This way we don't say "X used Move!" if they're asleep/frozen/etc.
    local ok_moves, movesModule = pcall(require, "moves")
    local canMoveResult = true
    local preStatusMessages = {}
    local forceMove = nil
    if ok_moves and movesModule and movesModule.checkCanMove then
        canMoveResult, preStatusMessages, forceMove = movesModule.checkCanMove(attacker, M)
    end
    
    -- If there's a forced move (from charging or locked move), use it instead
    if forceMove then
        mvname = forceMove
        mvobj = resolveMoveInstance(forceMove)
        if type(mvobj) == "table" and mvobj.name then mvlabel = mvobj.name end
    end
    
    if not canMoveResult then
        -- Pokemon can't move - show status messages (includes faint message if they died from confusion)
        -- We need to queue these messages with a proper action to handle faint state
        queueLog({ text = "", action = function()
            -- Show all the status messages first
            if preStatusMessages and type(preStatusMessages) == "table" then
                for _, msg in ipairs(preStatusMessages) do
                    if msg and msg ~= "" then
                        queueLog(msg)
                    end
                end
            end
            
            -- After messages are shown, check if attacker fainted (e.g., from confusion)
            if attacker and attacker.currentHP and attacker.currentHP <= 0 then
                -- Attacker fainted - handle battle end logic
                if attacker == M.p1 then
                    -- Player's Pokemon fainted
                    local party = (M.player and M.player.party) or nil
                    local hasAlive = false
                    if party then
                        for _, pp in ipairs(party) do if pp and (pp.currentHP or 0) > 0 then hasAlive = true; break end end
                    end
                    if hasAlive then
                        M.mode = "choose_pokemon"
                        M.chooseIndex = 1
                        M.faintedName = M.p1 and M.p1.nickname or "Player"
                    else
                        -- Player lost
                        if M.isTrainerBattle and M.trainer then
                            local lostMoney = 0
                            if M.player and M.player.money then
                                lostMoney = math.floor(M.player.money / 2)
                                M.player.money = M.player.money - lostMoney
                            end
                            queueLog({ text = "You have no more Pokémon that can fight!", action = function()
                                queueLog({ text = "You lost to " .. M.trainer:getDisplayName() .. "!", action = function()
                                    if lostMoney > 0 then
                                        queueLog({ text = "You paid $" .. tostring(lostMoney) .. " to the winner...", action = function()
                                            M.awaitingClose = true
                                            M.faintedName = nil
                                        end })
                                    else
                                        M.awaitingClose = true
                                        M.faintedName = nil
                                    end
                                end })
                            end })
                        else
                            M.awaitingClose = true
                            M.faintedName = M.p1 and M.p1.nickname or "Player"
                        end
                    end
                elseif attacker == M.p2 then
                    -- Opponent's Pokemon fainted
                    if M.isTrainerBattle and M.trainer and M.trainer:hasAlivePokemon() then
                        local nextPokemon = M.trainer:getNextAlivePokemon()
                        if nextPokemon then
                            queueLog({ text = M.trainer:getDisplayName() .. " is about to send out " .. (nextPokemon.nickname or nextPokemon.name) .. "!", action = function()
                                M.p2 = nextPokemon
                                M.p2AnimatedHP = M.p2.currentHP or 0
                                
                                local ok_moves2, movesModule2 = pcall(require, "moves")
                                if ok_moves2 and movesModule2 and movesModule2.initStatStages then
                                    movesModule2.initStatStages(M.p2)
                                end
                                
                                if not M.p2._move_instances then
                                    local arr = {}
                                    if M.p2.moves and #M.p2.moves > 0 then
                                        for i = 1, 4 do
                                            local mv = M.p2.moves[i]
                                            local inst = resolveMoveInstance(mv)
                                            if inst then
                                                inst.maxPP = inst.maxPP or inst.pp
                                                if inst.maxPP and (inst.pp == nil) then inst.pp = inst.maxPP end
                                            end
                                            arr[i] = inst or ""
                                        end
                                    else
                                        for i = 1, 4 do arr[i] = "" end
                                    end
                                    M.p2._move_instances = arr
                                end
                                queueLog(M.trainer:getDisplayName() .. " sent out " .. (nextPokemon.nickname or nextPokemon.name) .. "!")
                                M.mode = "menu"
                                M.selectedOption = 1
                                M.moveOptions = {}
                            end })
                        else
                            M.awaitingClose = true
                            M.faintedName = M.p2 and M.p2.nickname or "Opponent"
                        end
                    else
                        -- Wild battle or trainer out of Pokemon
                        if M.isTrainerBattle and M.trainer then
                            M.trainerDefeated = true
                            M.trainer:setDefeated()
                            local prizeMoney = M.trainer:getPrizeMoney()
                            if M.player then
                                M.player.money = (M.player.money or 0) + prizeMoney
                            end
                            queueLog({ text = "You defeated " .. M.trainer:getDisplayName() .. "!", action = function()
                                queueLog({ text = "You won $" .. tostring(prizeMoney) .. "!", action = function()
                                    M.awaitingClose = true
                                    M.faintedName = nil
                                end })
                            end })
                        else
                            M.awaitingClose = true
                            M.faintedName = M.p2 and M.p2.nickname or "Opponent"
                        end
                    end
                end
                return -- Don't continue if attacker fainted
            end
            
            -- If attacker didn't faint, continue with after_cb
            if after_cb then
                if not (defender.currentHP and defender.currentHP <= 0) then
                    after_cb()
                end
            end
        end })
        return
    end
    
    -- Pokemon can move - show any pre-status messages (like "X snapped out of confusion!")
    -- then show "used" message
    if preStatusMessages and type(preStatusMessages) == "table" and #preStatusMessages > 0 then
        for _, msg in ipairs(preStatusMessages) do
            if msg and msg ~= "" then
                queueLog(msg)
            end
        end
    end
    
    queueLog({ text = (attacker.nickname or tostring(attacker)) .. " used " .. mvlabel .. "!", action = action })
end

local function chooseTwo(list)
    if not list or #list == 0 then return nil, nil end
    if #list == 1 then return list[1], nil end
    local i = math.random(1, #list)
    local j = math.random(1, #list)
    while j == i do j = math.random(1, #list) end
    return list[i], list[j]
end

-- Internal helper to set up move instances for a Pokemon
local function setupMoveInstances(pokemon)
    if not pokemon then return end
    if not pokemon._move_instances then
        local arr = {}
        if pokemon.moves and #pokemon.moves > 0 then
            for i = 1, 4 do
                local mv = pokemon.moves[i]
                local inst = resolveMoveInstance(mv)
                if inst then
                    inst.maxPP = inst.maxPP or inst.pp
                    if inst.maxPP and (inst.pp == nil) then
                        inst.pp = inst.maxPP
                    end
                end
                arr[i] = inst or ""
            end
        else
            for i = 1, 4 do arr[i] = "" end
        end
        pokemon._move_instances = arr
    end
end

-- Internal helper to get player's first alive Pokemon
local function getFirstAlivePokemon(playerObj)
    if not playerObj or not playerObj.party then return nil end
    for _, p in ipairs(playerObj.party) do
        if p and (p.currentHP == nil or p.currentHP > 0) then
            return p
        end
    end
    return playerObj.party[1] -- fallback to first slot if none alive
end

-- Internal helper to initialize common battle state
local function initBattleState(playerObj)
    M.active = true
    M.selectedOption = 1
    M.mode = "menu"
    M.player = playerObj
    M.chooseIndex = 1
    M.battleLog = {}
    M.logQueue = {}
    M.waitingForZ = false
    M.awaitingClose = false
    M.faintedName = nil
    M.lastUsedMoveSlot = 1
    M.participatingPokemon = {}
    M.trainerDefeated = false
    
    -- Initialize animated HP and EXP values
    M.p1AnimatedHP = (M.p1 and M.p1.currentHP) or 0
    M.p2AnimatedHP = (M.p2 and M.p2.currentHP) or 0
    M.p1AnimatedExp = (M.p1 and M.p1.exp) or 0
    
    -- Initialize stat stages for both Pokemon (this is the new stat stage system)
    local ok, movesModule = pcall(require, "moves")
    if ok and movesModule then
        if M.p1 then
            movesModule.initStatStages(M.p1)
            -- Clear all volatile battle status from previous battles
            M.p1.recharging = nil
            M.p1.charging = nil
            M.p1.chargingMove = nil
            M.p1.lockedMove = nil
            M.p1.protectCount = nil
            M.p1.confused = nil
            M.p1.confusedTurns = nil
            M.p1.seeded = nil
            M.p1.infatuated = nil
            M.p1.trapped = nil
            M.p1.curse = nil
            M.p1.nightmare = nil
        end
        if M.p2 then
            movesModule.initStatStages(M.p2)
            -- Clear all volatile battle status from previous battles
            M.p2.recharging = nil
            M.p2.charging = nil
            M.p2.chargingMove = nil
            M.p2.lockedMove = nil
            M.p2.protectCount = nil
            M.p2.confused = nil
            M.p2.confusedTurns = nil
            M.p2.seeded = nil
            M.p2.infatuated = nil
            M.p2.trapped = nil
            M.p2.curse = nil
            M.p2.nightmare = nil
        end
    end
    
    -- Track p1 as participating
    if M.p1 then
        table.insert(M.participatingPokemon, M.p1)
    end
end

-- Start a wild Pokemon battle
function M.startWildBattle(wildPokemon, playerObj)
    log.log("battle.startWildBattle: starting wild battle")
    
    -- Reset trainer battle state
    M.isTrainerBattle = false
    M.trainer = nil
    
    -- Get player's Pokemon
    M.p1 = getFirstAlivePokemon(playerObj)
    
    -- Set wild Pokemon as opponent
    if wildPokemon then
        if type(wildPokemon) == "table" and wildPokemon.currentHP then
            -- It's already a Pokemon instance
            M.p2 = wildPokemon
        elseif type(wildPokemon) == "table" and #wildPokemon > 0 then
            -- It's a list of Pokemon, pick random one
            local idx = math.random(1, #wildPokemon)
            M.p2 = wildPokemon[idx]
        else
            -- Try to create a default wild Pokemon
            local ok, pmod = pcall(require, "pokemon")
            if ok and pmod and pmod.Pokemon then
                M.p2 = pmod.Pokemon:new("pikachu", 5)
            end
        end
    else
        -- Create default wild Pokemon
        local ok, pmod = pcall(require, "pokemon")
        if ok and pmod and pmod.Pokemon then
            M.p2 = pmod.Pokemon:new("pikachu", 5)
        end
    end
    
    -- Set up move instances
    setupMoveInstances(M.p1)
    setupMoveInstances(M.p2)
    
    -- Initialize common battle state
    initBattleState(playerObj)
    
    -- Queue encounter message
    local wildName = M.p2 and (M.p2.nickname or M.p2.name) or "wild Pokémon"
    queueLog("A wild " .. wildName .. " appeared!")
end

-- Start a trainer battle
function M.startTrainerBattle(trainerOrId, playerObj)
    log.log("battle.startTrainerBattle: starting trainer battle")
    
    -- Set trainer battle state
    M.isTrainerBattle = true
    M.trainerDefeated = false
    
    -- Get or create trainer instance
    if type(trainerOrId) == "string" then
        -- It's a trainer ID, create instance
        local ok, trainerMod = pcall(require, "trainer")
        if ok and trainerMod and trainerMod.Trainer then
            M.trainer = trainerMod.Trainer:new(trainerOrId)
        else
            log.log("battle.startTrainerBattle: failed to load trainer module")
            return
        end
    elseif type(trainerOrId) == "table" then
        -- It's already a trainer instance
        M.trainer = trainerOrId
    else
        log.log("battle.startTrainerBattle: invalid trainer argument")
        return
    end
    
    if not M.trainer then
        log.log("battle.startTrainerBattle: trainer is nil")
        return
    end
    
    -- Get player's Pokemon
    M.p1 = getFirstAlivePokemon(playerObj)
    
    -- Get trainer's first Pokemon
    M.p2 = M.trainer:getNextAlivePokemon()
    
    if not M.p2 then
        log.log("battle.startTrainerBattle: trainer has no Pokemon")
        return
    end
    
    -- Set up move instances
    setupMoveInstances(M.p1)
    setupMoveInstances(M.p2)
    
    -- Initialize common battle state
    initBattleState(playerObj)
    
    -- Queue trainer encounter messages
    local trainerName = M.trainer:getDisplayName()
    local pokemonName = M.p2.nickname or M.p2.name or "Pokémon"
    queueLog(trainerName .. " wants to battle!")
    queueLog(trainerName .. " sent out " .. pokemonName .. "!")
end

-- Legacy start function - defaults to wild battle for backwards compatibility
function M.start(pokemonList, playerObj)
    local list = pokemonList
    if not list then
        local ok, pmod = pcall(require, "pokemon")
        log.log("battle.start: require ok=", ok, "module_type=", type(pmod))
        if ok and pmod and pmod.Pokemon then
            -- create a small manual list of wild Pokemon using the new speciesId-based constructor
            list = {
                pmod.Pokemon:new("pikachu", 5),
                pmod.Pokemon:new("bulbasaur", 5),
                pmod.Pokemon:new("squirtle", 5),
                pmod.Pokemon:new("charmander", 5),
            }
            log.log("battle.start: created manual pokemon list, len=", #list)
        end
    end

    -- Use the new startWildBattle function
    M.startWildBattle(list, playerObj)
end

function M.isActive()
    return M.active
end

-- Set the callback function for handling whiteout (teleporting player)
function M.setWhiteoutCallback(callback)
    M.whiteoutCallback = callback
end

-- Function to trigger whiteout - heals all Pokemon and teleports player
function M.triggerWhiteout()
    if not M.player then return end
    
    -- Calculate money to lose (half of current money)
    local lostMoney = 0
    if M.player.money and M.player.money > 0 then
        lostMoney = math.floor(M.player.money / 2)
        M.player.money = M.player.money - lostMoney
    end
    
    -- Heal all player's Pokemon
    if M.player.party then
        for _, pokemon in ipairs(M.player.party) do
            if pokemon and pokemon.stats and pokemon.stats.hp then
                pokemon.currentHP = pokemon.stats.hp
                -- Clear all status conditions
                pokemon.status = nil
                -- Clear volatile status conditions
                pokemon.confused = nil
                pokemon.confusedTurns = nil
                pokemon.seeded = nil
                pokemon.infatuated = nil
                pokemon.trapped = nil
                pokemon.curse = nil
                pokemon.nightmare = nil
                pokemon.perishCount = nil
                -- Restore PP for all moves
                if pokemon._move_instances then
                    for _, moveInst in ipairs(pokemon._move_instances) do
                        if type(moveInst) == "table" and moveInst.maxPP then
                            moveInst.pp = moveInst.maxPP
                        end
                    end
                end
            end
        end
    end
    
    M.playerWhitedOut = true
    return lostMoney
end

M["end"] = function()
    -- Check if player whited out and needs to be teleported
    local whitedOut = M.playerWhitedOut
    local whiteoutCb = M.whiteoutCallback
    local playerRef = M.player
    
    M.active = false
    M.p1 = nil
    M.p2 = nil
    M.participatingPokemon = {}
    M.selectedOption = 1
    M.mode = "menu"
    M.moveOptions = {}
    M.battleLog = {}
    M.logQueue = {}
    M.waitingForZ = false
    M.awaitingClose = false
    M.faintedName = nil
    M.chooseIndex = 1
    M.choose_context = nil
    M.player = nil
    M.lastUsedMoveSlot = 1
    -- Reset trainer battle state
    M.isTrainerBattle = false
    M.trainer = nil
    M.trainerDefeated = false
    -- Reset animation state
    M.p1AnimatedHP = 0
    M.p2AnimatedHP = 0
    M.p1AnimatedExp = 0
    -- Reset whiteout state
    M.playerWhitedOut = false
    
    -- Execute whiteout callback after resetting state
    if whitedOut and whiteoutCb and playerRef then
        whiteoutCb(playerRef)
    end
end

function M.keypressed(key)
    if not M.active then return end
    -- If we're waiting for the player to press Z to advance the battle log, block other inputs
    if M.waitingForZ then
        if key == "z" then
            -- Execute and remove the deferred action associated with the most recently displayed log
            -- (the end of the `M.battleLog` list).
            local actionCount = 0
            for _, v in ipairs(M.battleLog) do if v and v.action then actionCount = actionCount + 1 end end
            log.log("battle.keypressed Z: logCount=", #M.battleLog, " actionCount=", actionCount, " queue=", #M.logQueue)
            local act = nil
            if #M.battleLog > 0 then
                local last = M.battleLog[#M.battleLog]
                act = last and last.action
            end
            if act then
                local ok, err = pcall(act)
                if not ok then log.log("battle action error:", err) end
            else
                log.log("battle.keypressed: no action to run")
            end
            -- remove the displayed log entry after running its action (so the action
            -- can append/replace logs without creating duplicates)
            if #M.battleLog > 0 then table.remove(M.battleLog, #M.battleLog) end
            log.log("battle.keypressed after run: logCount=", #M.battleLog, " queue=", #M.logQueue)
            M.waitingForZ = false
        end
        return
    end
    -- if a Pokemon fainted and we're awaiting close, only accept 'z' to exit
    if M.awaitingClose then
        if key == "z" then
            M["end"]()
        end
        return
    end

    -- If player must choose a replacement Pokemon, handle navigation separately
    if M.mode == "choose_pokemon" then
        local party = (M.player and M.player.party) or {}
        local count = #party
        -- up/down wrap through party + Back option
        if key == "up" then
            M.chooseIndex = M.chooseIndex - 1
            if M.chooseIndex < 1 then M.chooseIndex = count + 1 end
            return
        elseif key == "down" then
            M.chooseIndex = M.chooseIndex + 1
            if M.chooseIndex > count + 1 then M.chooseIndex = 1 end
            return
        elseif key == "space" or key == "b" then
            -- Back button: act like selecting the Back option
            if M.choose_context == "menu_switch" then
                -- Return to battle menu if this was a voluntary switch
                M.mode = "menu"
                M.selectedOption = 2  -- Pokemon option
                M.choose_context = nil
            else
                -- For forced replacements, back button does nothing (must select a pokemon)
                -- Don't forfeit the battle
            end
            return
        elseif key == "return" or key == "z" or key == "enter" then
            if M.chooseIndex == count + 1 then
                -- Back option: if the player opened the party from the menu to switch,
                -- then Back should return to the battle menu. If this was a forced
                -- replacement (context "forced"), treat Back as a forfeit and end.
                if M.choose_context == "menu_switch" then
                    M.mode = "menu"
                    M.selectedOption = 2  -- Pokemon option
                    M.choose_context = nil
                    return
                else
                    -- Back / forfeit
                    M["end"]()
                    return
                end
            else
                local sel = party[M.chooseIndex]
                -- Do not allow selecting a fainted Pokémon (currentHP <= 0).
                -- If currentHP is nil, treat the Pokémon as selectable (unknown/full).
                local sel_alive = false
                if sel then
                    if not (sel.currentHP ~= nil and sel.currentHP <= 0) then sel_alive = true end
                end
                if sel and sel_alive then
                    -- Reset stat stages and volatile statuses on the outgoing Pokemon
                    local ok_moves, movesModule = pcall(require, "moves")
                    if ok_moves and movesModule then
                        if M.p1 then
                            -- Reset stat stages when switching out (like the real games)
                            movesModule.resetStatStages(M.p1)
                            -- Cure volatile statuses (confusion, seeded, infatuated, etc.)
                            if movesModule.cureVolatileStatus then
                                movesModule.cureVolatileStatus(M.p1)
                            end
                        end
                    end
                    
                    M.p1 = sel
                    
                    -- Initialize stat stages for the new Pokemon
                    if ok_moves and movesModule then
                        movesModule.initStatStages(M.p1)
                    end
                    
                    -- Ensure stats are properly initialized (Pokemon from party should already have these)
                    if not M.p1.stats or not M.p1.stats.hp then
                        -- Shouldn't happen, but provide defaults just in case
                        M.p1.stats = { hp = 100, attack = 10, defense = 10, spAttack = 10, spDefense = 10, speed = 10 }
                        M.p1.currentHP = M.p1.stats.hp
                    end
                    -- ensure the selected pokemon has per-pokemon move instances
                    if not M.p1._move_instances then
                        local arr = {}
                        if M.p1.moves and #M.p1.moves > 0 then
                            for i = 1, 4 do
                                local mv = M.p1.moves[i]
                                local inst = resolveMoveInstance(mv)
                                if inst then
                                    inst.maxPP = inst.maxPP or inst.pp
                                    if inst.maxPP and (inst.pp == nil) then inst.pp = inst.maxPP end
                                end
                                arr[i] = inst or ""
                            end
                        else
                            for i = 1, 4 do arr[i] = "" end
                        end
                        M.p1._move_instances = arr
                    end
                    -- announce the switch
                    queueLog("Switched to " .. (M.p1.nickname or "Pokémon"))
                    
                    -- Reset animated HP and EXP for the new Pokemon
                    M.p1AnimatedHP = M.p1.currentHP or 0
                    M.p1AnimatedExp = M.p1.exp or 0
                    
                    -- Track this Pokémon as having participated in the battle
                    local alreadyParticipating = false
                    for _, p in ipairs(M.participatingPokemon) do
                        if p == M.p1 then
                            alreadyParticipating = true
                            break
                        end
                    end
                    if not alreadyParticipating then
                        table.insert(M.participatingPokemon, M.p1)
                    end

                    -- If this selection was initiated from the menu as a switch, it consumes the turn
                    if M.choose_context == "menu_switch" then
                        -- opponent selects a move and immediately attacks the switched-in Pokemon
                        local omv = ""
                        if M.p2 and M.p2.moves and #M.p2.moves > 0 then
                            omv = M.p2.moves[math.random(1, #M.p2.moves)] or ""
                        end
                        -- ensure stats
                        if not M.p1.stats then M.p1.stats = { hp = 10 } end
                        if not M.p2.stats then M.p2.stats = { hp = 10 } end
                        M.p1.speed = (M.p1.speed ~= nil) and M.p1.speed or 10
                        M.p2.speed = (M.p2.speed ~= nil) and M.p2.speed or 10

                        -- Queue the opponent's move; its effects will occur when the
                        -- associated log is acknowledged by the player. The queued
                        -- action will handle fainting and menu transitions.
                        queueMove(M.p2, M.p1, omv)
                        M.choose_context = nil
                        M.mode = "menu"
                        M.selectedOption = 1
                        M.moveOptions = {}
                    else
                        -- normal forced or non-consuming selection: just return to menu
                        M.mode = "menu"
                        M.selectedOption = 1
                        M.moveOptions = {}
                        M.awaitingClose = false
                        M.faintedName = nil
                    end
                end
                return
            end
        end
    end
    
    -- Navigation for selecting a Pokemon to use an item on (check this BEFORE items menu)
    if M.itemSelectMode then
        local party = (M.player and M.player.party) or nil
        local count = party and #party or 0
        
        if key == "up" then
            M.chooseIndex = M.chooseIndex - 1
            if M.chooseIndex < 1 then M.chooseIndex = count + 1 end
            return
        elseif key == "down" then
            M.chooseIndex = M.chooseIndex + 1
            if M.chooseIndex > count + 1 then M.chooseIndex = 1 end
            return
        elseif key == "space" then
            -- Cancel item use
            M.itemSelectMode = false
            M.itemSelected = nil
            M.mode = "items"
            M.selectedOption = 1
            return
        elseif key == "return" or key == "z" or key == "enter" then
            if M.chooseIndex == count + 1 then
                -- Back option
                M.itemSelectMode = false
                M.itemSelected = nil
                M.mode = "items"
                M.selectedOption = 1
                return
            else
                -- Use item on selected Pokemon
                local pokemon = party[M.chooseIndex]
                local item = M.itemSelected
                
                if pokemon and item then
                    local ok, itemModule = pcall(require, "item")
                    if ok and itemModule and itemModule.useItem then
                        local success = itemModule.useItem(item, {
                            type = "battle",
                            target = pokemon,
                            flags = {}
                        })
                        if success then
                            queueLog({ text = "Used " .. item.data.name .. " on " .. (pokemon.nickname or pokemon.name) })
                        else
                            queueLog({ text = item.data.name .. " had no effect!" })
                        end
                    end
                end
                
                -- Item always goes first in battle
                -- Opponent selects a move
                local omv = ""
                if M.p2 and M.p2.moves and #M.p2.moves > 0 then
                    omv = M.p2.moves[math.random(1, #M.p2.moves)] or ""
                end
                
                -- Queue opponent's move after item
                if M.p2 and (M.p2.currentHP or 0) > 0 then
                    queueMove(M.p2, M.p1, omv)
                end
                
                -- Return to menu
                M.itemSelectMode = false
                M.itemSelected = nil
                M.mode = "menu"
                M.selectedOption = 1
                return
            end
        end
        return
    end
    
    -- navigation for items menu
    if M.mode == "items" then
        if key == "left" then
            -- Previous category
            M.battleCurrentCategory = M.battleCurrentCategory - 1
            if M.battleCurrentCategory < 1 then
                M.battleCurrentCategory = #M.battleItemCategories
            end
            M.refreshBattleCategoryItems()
            M.selectedOption = 1
            return
        elseif key == "right" then
            -- Next category
            M.battleCurrentCategory = M.battleCurrentCategory + 1
            if M.battleCurrentCategory > #M.battleItemCategories then
                M.battleCurrentCategory = 1
            end
            M.refreshBattleCategoryItems()
            M.selectedOption = 1
            return
        elseif key == "up" then
            M.selectedOption = M.selectedOption - 1
            if M.selectedOption < 1 then M.selectedOption = #M.battleCategoryItems + 1 end
            return
        elseif key == "down" then
            M.selectedOption = M.selectedOption + 1
            if M.selectedOption > #M.battleCategoryItems + 1 then M.selectedOption = 1 end
            return
        elseif key == "space" then
            -- Cancel items menu
            M.mode = "menu"
            M.selectedOption = 3 -- Back to Items option
            return
        elseif key == "return" or key == "z" or key == "enter" then
            if M.selectedOption == #M.battleCategoryItems + 1 then
                -- Back option
                M.mode = "menu"
                M.selectedOption = 3
                return
            else
                -- Item selected
                M.itemSelected = M.battleCategoryItems[M.selectedOption]
                if M.itemSelected and M.itemSelected:canUse("battle") then
                    -- Check if this is a Pokeball (catch effect)
                    if M.itemSelected.data.effect and M.itemSelected.data.effect.type == "catch" then
                        -- Block pokeball usage in trainer battles
                        if M.isTrainerBattle then
                            queueLog({ text = "You can't catch another trainer's Pokémon!" })
                            M.itemSelected = nil
                            M.mode = "menu"
                            M.selectedOption = 1
                            return
                        end
                        
                        -- Throw Pokeball at wild Pokemon immediately
                        local ok, itemModule = pcall(require, "item")
                        if ok and itemModule and itemModule.useItem then
                            local result = itemModule.useItem(M.itemSelected, {
                                type = "battle",
                                target = M.p2, -- The wild Pokemon
                                player = M.player,
                                flags = {}
                            })
                            
                            local pokemonName = M.p2 and (M.p2.nickname or M.p2.name) or "wild Pokémon"
                            
                            if result == "caught" then
                                queueLog({ text = "You threw a " .. M.itemSelected.data.name .. "!" })
                                queueLog({ text = "Gotcha! " .. pokemonName .. " was caught!", action = function()
                                    -- End battle after catching
                                    M.awaitingClose = true
                                    M.faintedName = nil
                                end })
                            elseif result == "sent_to_box" then
                                queueLog({ text = "You threw a " .. M.itemSelected.data.name .. "!" })
                                queueLog({ text = "Gotcha! " .. pokemonName .. " was caught!" })
                                queueLog({ text = "Your party is full! " .. pokemonName .. " was sent to the Box.", action = function()
                                    -- End battle after catching
                                    M.awaitingClose = true
                                    M.faintedName = nil
                                end })
                            else
                                queueLog({ text = "You threw a " .. M.itemSelected.data.name .. "!" })
                                queueLog({ text = "Oh no! " .. pokemonName .. " broke free!" })
                                -- Opponent gets to attack after failed catch
                                local omv = ""
                                if M.p2 and M.p2.moves and #M.p2.moves > 0 then
                                    omv = M.p2.moves[math.random(1, #M.p2.moves)] or ""
                                end
                                if M.p2 and (M.p2.currentHP or 0) > 0 then
                                    queueMove(M.p2, M.p1, omv)
                                end
                            end
                        end
                        
                        -- Return to menu
                        M.itemSelected = nil
                        M.mode = "menu"
                        M.selectedOption = 1
                    else
                        -- Other items - proceed to Pokemon selection
                        M.itemSelectMode = true
                        M.chooseIndex = 1
                    end
                else
                    queueLog({ text = "Cannot use this item now!" })
                    M.mode = "menu"
                    M.selectedOption = 3
                end
                return
            end
        end
        return
    end
    
    -- 2x2 grid navigation (left side): indices arranged as
    -- 1 2
    -- 3 4
    local function idx_to_rc(idx)
        local r = math.floor((idx - 1) / 2)
        local c = (idx - 1) % 2
        return r, c
    end
    local function rc_to_idx(r, c)
        return r * 2 + c + 1
    end

    if key == "left" or key == "a" then
        local r, c = idx_to_rc(M.selectedOption)
        c = c - 1
        if c < 0 then c = 1 end
        M.selectedOption = rc_to_idx(r, c)
        return
    end
    if key == "right" or key == "d" then
        local r, c = idx_to_rc(M.selectedOption)
        c = c + 1
        if c > 1 then c = 0 end
        M.selectedOption = rc_to_idx(r, c)
        return
    end
    if key == "up" or key == "w" then
        local r, c = idx_to_rc(M.selectedOption)
        r = r - 1
        if r < 0 then r = 1 end
        M.selectedOption = rc_to_idx(r, c)
        return
    end
    if key == "down" or key == "s" then
        local r, c = idx_to_rc(M.selectedOption)
        r = r + 1
        if r > 1 then r = 0 end
        M.selectedOption = rc_to_idx(r, c)
        return
    end

    -- cancel/back when in moves
    if key == "b" and M.mode == "moves" then
        M.mode = "menu"
        M.selectedOption = 1
        return
    end

    -- select / confirm
    if key == "return" or key == "z" or key == "enter" then
        if M.mode == "menu" then
            local opt = M.menuOptions[M.selectedOption]
            if opt == "Run" then
                -- Cannot run from trainer battles
                if M.isTrainerBattle then
                    queueLog({ text = "You can't run from a trainer battle!" })
                    return
                end
                M["end"]()
            elseif opt == "Fight" then
                -- if player's pokemon is fainted, force choose replacement instead of fighting
                if M.p1 and (M.p1.currentHP or 0) <= 0 then
                    local party = (M.player and M.player.party) or nil
                    local hasAlive = false
                    if party then
                        for _, pp in ipairs(party) do if pp and (pp.currentHP or 0) > 0 then hasAlive = true; break end end
                    end
                    if hasAlive then
                        M.mode = "choose_pokemon"
                        M.choose_context = "forced"
                        M.chooseIndex = 1
                        return
                    else
                        M.awaitingClose = true
                        M.faintedName = M.p1 and M.p1.nickname or "Player"
                        return
                    end
                end
                
                -- Check if Pokemon must recharge (Hyper Beam, Giga Impact, etc.)
                if M.p1 and M.p1.recharging then
                    -- Pokemon must recharge - skip move selection entirely
                    local ok_mvmod, mvModule = pcall(require, "moves")
                    
                    -- Choose opponent move
                    local omv = ""
                    if M.p2 and M.p2.moves and #M.p2.moves > 0 then
                        omv = M.p2.moves[math.random(1, #M.p2.moves)] or ""
                    end
                    
                    -- Ensure stats defaults exist
                    if not M.p1.stats then M.p1.stats = { hp = 10 } end
                    if not M.p2.stats then M.p2.stats = { hp = 10 } end
                    
                    -- Clear recharging flag and show message
                    M.p1.recharging = nil
                    local p1Name = M.p1.nickname or M.p1.name or "Pokemon"
                    queueLog({ text = p1Name .. " must recharge!", action = function()
                        -- Opponent gets a free turn to attack
                        if M.p2 and (M.p2.currentHP or 0) > 0 and M.p1 and (M.p1.currentHP or 0) > 0 then
                            queueMove(M.p2, M.p1, omv)
                        end
                    end })
                    
                    if M.active and not M.awaitingClose and M.mode ~= "choose_pokemon" then
                        M.mode = "menu"
                        M.selectedOption = 1
                    end
                    return
                end
                
                -- Check if Pokemon is locked into a move (charging, recharging, or rampage move)
                local ok_mvmod, mvModule = pcall(require, "moves")
                local lockedMove = nil
                
                -- Check for charging move (second turn)
                if M.p1 and M.p1.charging and M.p1.charging.move then
                    lockedMove = M.p1.charging.move
                end
                
                -- Check for locked/rampage move (Thrash, Outrage, etc.)
                if M.p1 and M.p1.lockedMove and M.p1.lockedMove.move then
                    lockedMove = M.p1.lockedMove.move
                end
                
                -- If locked into a move, skip move selection and execute immediately
                if lockedMove then
                    -- Choose opponent move
                    local omv = ""
                    if M.p2 and M.p2.moves and #M.p2.moves > 0 then
                        omv = M.p2.moves[math.random(1, #M.p2.moves)] or ""
                    end
                    
                    -- Ensure stats defaults exist
                    if not M.p1.stats then M.p1.stats = { hp = 10 } end
                    if not M.p2.stats then M.p2.stats = { hp = 10 } end
                    
                    -- Determine order by speed
                    local p1spd, p2spd
                    if mvModule and mvModule.getEffectiveStat then
                        p1spd = mvModule.getEffectiveStat(M.p1, "speed")
                        p2spd = mvModule.getEffectiveStat(M.p2, "speed")
                    else
                        p1spd = (M.p1.stats and M.p1.stats.speed) or 10
                        p2spd = (M.p2.stats and M.p2.stats.speed) or 10
                    end
                    if M.p1.status == "paralyzed" then p1spd = math.floor(p1spd / 4) end
                    if M.p2.status == "paralyzed" then p2spd = math.floor(p2spd / 4) end
                    
                    local p1first = p1spd > p2spd or (p1spd == p2spd and math.random(0, 1) == 1)
                    
                    if p1first then
                        queueMove(M.p1, M.p2, lockedMove, function()
                            if M.p2 and (M.p2.currentHP or 0) > 0 then
                                queueMove(M.p2, M.p1, omv)
                            end
                        end)
                    else
                        queueMove(M.p2, M.p1, omv, function()
                            if M.p1 and (M.p1.currentHP or 0) > 0 then
                                queueMove(M.p1, M.p2, lockedMove)
                            end
                        end)
                    end
                    
                    if M.active and not M.awaitingClose and M.mode ~= "choose_pokemon" then
                        M.mode = "menu"
                        M.selectedOption = 1
                    end
                    return
                end
                
                -- populate moves into a 4-slot grid using per-battle instances
                M.moveOptions = {}
                local insts = (M.p1 and M.p1._move_instances) or nil
                if insts then
                    for i = 1, 4 do
                        M.moveOptions[i] = insts[i] or ""
                    end
                else
                    if M.p1 and M.p1.moves then
                        for i = 1, 4 do
                            M.moveOptions[i] = M.p1.moves[i] or ""
                        end
                    else
                        for i = 1, 4 do M.moveOptions[i] = "" end
                    end
                end
                M.mode = "moves"
                M.selectedOption = M.lastUsedMoveSlot
            elseif opt == "Pokemon" then
                -- allow switching from the menu; this will consume the player's turn
                local party = (M.player and M.player.party) or nil
                local hasAlive = false
                if party then
                    for _, pp in ipairs(party) do if pp and (pp.currentHP or 0) > 0 then hasAlive = true; break end end
                end
                if hasAlive then
                    M.mode = "choose_pokemon"
                    M.chooseIndex = 1
                    M.choose_context = "menu_switch"
                end
            elseif opt == "Items" then
                -- Open bag with category-based browsing
                M.battleCurrentCategory = 1 -- Start on medicine
                M.refreshBattleCategoryItems()
                M.mode = "items"
                M.selectedOption = 1
            end
        elseif M.mode == "moves" then
            local mv = M.moveOptions[M.selectedOption]
            if mv and mv ~= "" then
                -- Track the last used move slot for cursor persistence
                M.lastUsedMoveSlot = M.selectedOption
                
                -- choose opponent move
                local omv = ""
                if M.p2 and M.p2.moves and #M.p2.moves > 0 then
                    omv = M.p2.moves[math.random(1, #M.p2.moves)] or ""
                end

                -- ensure stats defaults exist
                if not M.p1.stats then M.p1.stats = { hp = 10 } end
                if not M.p2.stats then M.p2.stats = { hp = 10 } end

                -- determine order by effective speed stat (considering stat stages and paralysis)
                local ok_moves, movesModule = pcall(require, "moves")
                local p1spd, p2spd
                if ok_moves and movesModule and movesModule.getEffectiveStat then
                    p1spd = movesModule.getEffectiveStat(M.p1, "speed")
                    p2spd = movesModule.getEffectiveStat(M.p2, "speed")
                else
                    p1spd = (M.p1.stats and M.p1.stats.speed) or 10
                    p2spd = (M.p2.stats and M.p2.stats.speed) or 10
                end
                -- Apply paralysis speed reduction (quartered)
                if M.p1.status == "paralyzed" then
                    p1spd = math.floor(p1spd / 4)
                end
                if M.p2.status == "paralyzed" then
                    p2spd = math.floor(p2spd / 4)
                end
                
                -- Check for priority moves
                local p1priority = 0
                local p2priority = 0
                local p1moveObj = resolveMoveInstance(mv)
                local p2moveObj = resolveMoveInstance(omv)
                if p1moveObj and p1moveObj.priority then
                    p1priority = p1moveObj.priority
                end
                if p2moveObj and p2moveObj.priority then
                    p2priority = p2moveObj.priority
                end
                
                -- Priority takes precedence over speed
                local p1first = false
                if p1priority > p2priority then
                    p1first = true
                elseif p1priority < p2priority then
                    p1first = false
                elseif p1spd > p2spd then
                    p1first = true
                elseif p2spd > p1spd then
                    p1first = false
                else
                    -- tie: randomize
                    p1first = (math.random(0, 1) == 1)
                end
                
                if p1first then
                    -- player first: queue player's move, then queue opponent if still alive
                    queueMove(M.p1, M.p2, mv, function()
                        if M.p2 and (M.p2.currentHP or 0) > 0 then
                            queueMove(M.p2, M.p1, omv)
                        end
                    end)
                else
                    -- opponent first
                    queueMove(M.p2, M.p1, omv, function()
                        if M.p1 and (M.p1.currentHP or 0) > 0 then
                            queueMove(M.p1, M.p2, mv)
                        end
                    end)
                end
                -- after turn return to menu only if no one fainted and player is not choosing a replacement
                if M.active and not M.awaitingClose and M.mode ~= "choose_pokemon" then
                    M.mode = "menu"
                    M.selectedOption = 1
                end
            end
        end
        return
    end
    
    -- Handle back button (space, b, escape) based on current mode
    if key == "space" or key == "b" or key == "escape" then
        if M.mode == "moves" then
            -- Back to main menu from move selection
            M.mode = "menu"
            M.selectedOption = 1
            return
        elseif M.mode == "items" then
            -- Back to main menu from items
            M.mode = "menu"
            M.selectedOption = 3 -- Items option
            return
        elseif M.mode == "menu" then
            -- In main menu, back button does nothing (use Run option to run)
            return
        end
    end
end

function M.update(dt)
    -- If there are queued messages and we're not currently waiting for Z,
    -- move one message from the queue into the visible battleLog and pause.
    if M.active and not M.waitingForZ and #M.logQueue > 0 then
        log.log("battle.update: moving queued log -> visible; queue=", #M.logQueue, " logs=", #M.battleLog)
        local item = table.remove(M.logQueue, 1)
        table.insert(M.battleLog, item)
        if #M.battleLog > M.maxLogLines then
            table.remove(M.battleLog, 1)
        end
        M.waitingForZ = true
    end
    
    -- Animate HP bars
    if M.p1 and M.p1.currentHP then
        local targetHP = M.p1.currentHP
        local diff = targetHP - M.p1AnimatedHP
        if math.abs(diff) > 0.5 then
            M.p1AnimatedHP = M.p1AnimatedHP + diff * 8 * dt
        else
            M.p1AnimatedHP = targetHP
        end
    end
    
    if M.p2 and M.p2.currentHP then
        local targetHP = M.p2.currentHP
        local diff = targetHP - M.p2AnimatedHP
        if math.abs(diff) > 0.5 then
            M.p2AnimatedHP = M.p2AnimatedHP + diff * 8 * dt
        else
            M.p2AnimatedHP = targetHP
        end
    end
    
    -- Animate EXP bar
    if M.p1 and M.p1.exp then
        local targetExp = M.p1.exp
        local diff = targetExp - M.p1AnimatedExp
        if math.abs(diff) > 0.5 then
            M.p1AnimatedExp = M.p1AnimatedExp + diff * 6 * dt
        else
            M.p1AnimatedExp = targetExp
        end
    end
    
    -- Update attack animation
    if M.attackAnimating then
        M.attackAnimTime = M.attackAnimTime + dt
        
        local progress = M.attackAnimTime / M.attackAnimDuration
        if progress >= 1 then
            -- Animation complete
            M.attackAnimating = false
            M.attackAnimOffset.x = 0
            M.attackAnimOffset.y = 0
        else
            -- Calculate animation offset based on type
            if M.attackAnimType == "damage" then
                -- Damage animation: move toward target and back
                -- Use a sine wave for smooth motion
                local distance = 40
                local wave = math.sin(progress * math.pi) -- 0 to 1 to 0
                
                if M.attackAnimTarget == "p1" then
                    -- Player attacks (moves right toward opponent)
                    M.attackAnimOffset.x = distance * wave
                else
                    -- Opponent attacks (moves left toward player)
                    M.attackAnimOffset.x = -distance * wave
                end
            else
                -- Status animation: bob up and down
                local bobHeight = 15
                local wave = math.sin(progress * math.pi * 2) -- oscillate up and down
                M.attackAnimOffset.y = -bobHeight * math.abs(wave)
            end
        end
    end
end

function M.draw()
    if not M.active then return end
    love.graphics.push()
    love.graphics.origin()
    local ww, hh = UI.getGameScreenDimensions()
    
    -- Battle background - light gray gradient feel
    love.graphics.setColor(0.9, 0.92, 0.9, 1)
    love.graphics.rectangle("fill", 0, 0, ww, hh)
    
    local font = love.graphics.getFont()
    local lineH = (font and font:getHeight() or 12) + 4
    
    -- Show different title for trainer vs wild battles
    local battleTitle = "WILD BATTLE"
    if M.isTrainerBattle and M.trainer then
        battleTitle = "VS " .. M.trainer:getDisplayName()
    end
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.printf(battleTitle, 0, hh * 0.02, ww, "center")

    local function name_with_level(p)
        if not p then return "---" end
        local nm = p.nickname or p.name or tostring(p)
        local lv = p.level or p.l or nil
        if lv then
            return string.format("%s Lv%s", tostring(nm), tostring(lv))
        end
        return tostring(nm)
    end
    
    -- Opponent info panel (top-left)
    local oppPanelW = ww * 0.45
    local oppPanelH = 55
    local oppPanelX = 10
    local oppPanelY = hh * 0.08
    UI.drawBox(oppPanelX, oppPanelY, oppPanelW, oppPanelH, 2)
    
    local oppName = name_with_level(M.p2)
    local oppCur = (M.p2 and (M.p2.currentHP ~= nil)) and M.p2.currentHP or 0
    local oppMax = (M.p2 and M.p2.stats and M.p2.stats.hp) and M.p2.stats.hp or 1
    
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.print(oppName, oppPanelX + 10, oppPanelY + 8)
    
    -- Opponent status condition badge
    if M.p2 and M.p2.status then
        UI.drawStatusBadge(M.p2.status, oppPanelX + 10 + font:getWidth(oppName) + 8, oppPanelY + 8)
    end
    
    -- Opponent HP bar (use animated value)
    local oppAnimatedHP = math.floor(M.p2AnimatedHP)
    UI.drawHPBar(oppAnimatedHP, oppMax, oppPanelX + 10, oppPanelY + 28, oppPanelW - 20, 12)
    
    -- Show remaining Pokemon count for trainer battles (as pokeball icons placeholder)
    if M.isTrainerBattle and M.trainer then
        local remaining = M.trainer:getRemainingPokemonCount()
        local total = #M.trainer.party
        love.graphics.setColor(unpack(UI.colors.textGray))
        love.graphics.print(remaining .. "/" .. total, oppPanelX + oppPanelW - 35, oppPanelY + 8)
    end
    
    -- Opponent sprite area (top-right) - larger size without box
    local oppSpriteW = hh * 0.35
    local oppSpriteX = ww - oppSpriteW - 20
    local oppSpriteY = hh * 0.05
    
    -- Draw opponent's Pokemon sprite (front view)
    if M.p2 then
        local offsetX = 0
        local offsetY = 0
        if M.attackAnimating and M.attackAnimTarget == "p2" then
            offsetX = M.attackAnimOffset.x
            offsetY = M.attackAnimOffset.y
        end
        drawPokemonSprite(M.p2, oppSpriteX + offsetX, oppSpriteY + offsetY, oppSpriteW, oppSpriteW, false)
    end

    -- Player info panel (right side, middle)
    local playerPanelW = ww * 0.45
    local playerPanelH = 80
    local playerPanelX = ww - playerPanelW - 10
    local playerPanelY = hh * 0.40
    UI.drawBox(playerPanelX, playerPanelY, playerPanelW, playerPanelH, 2)
    
    local playerName = name_with_level(M.p1)
    local playerCur = (M.p1 and (M.p1.currentHP ~= nil)) and M.p1.currentHP or 0
    local playerMax = (M.p1 and M.p1.stats and M.p1.stats.hp) and M.p1.stats.hp or 1
    
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.print(playerName, playerPanelX + 10, playerPanelY + 8)
    
    -- Player status condition badge
    if M.p1 and M.p1.status then
        UI.drawStatusBadge(M.p1.status, playerPanelX + 10 + font:getWidth(playerName) + 8, playerPanelY + 8)
    end
    
    -- Player HP bar (use animated value)
    local playerAnimatedHP = math.floor(M.p1AnimatedHP)
    UI.drawHPBar(playerAnimatedHP, playerMax, playerPanelX + 10, playerPanelY + 28, playerPanelW - 20, 12)
    
    -- HP text
    local playerHpText = tostring(playerCur) .. "/" .. tostring(playerMax)
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.print(playerHpText, playerPanelX + playerPanelW - 60, playerPanelY + 26)
    
    -- Player EXP bar (use animated value)
    local expAnimated = math.floor(M.p1AnimatedExp)
    local expThisLvl = (M.p1 and M.p1.getExpForLevel) and M.p1:getExpForLevel(M.p1.level) or 0
    local expNextLvl = (M.p1 and M.p1.getExpForLevel) and M.p1:getExpForLevel(M.p1.level + 1) or 1
    UI.drawEXPBar(expAnimated, expThisLvl, expNextLvl, playerPanelX + 10, playerPanelY + 48, playerPanelW - 20, 10)
    
    -- Player sprite area (left side, middle) - larger size without box
    local playerSpriteW = hh * 0.35
    local playerSpriteX = 20
    local playerSpriteY = hh * 0.30
    
    -- Draw player's Pokemon sprite (back view)
    if M.p1 then
        local offsetX = 0
        local offsetY = 0
        if M.attackAnimating and M.attackAnimTarget == "p1" then
            offsetX = M.attackAnimOffset.x
            offsetY = M.attackAnimOffset.y
        end
        drawPokemonSprite(M.p1, playerSpriteX + offsetX, playerSpriteY + offsetY, playerSpriteW, playerSpriteW, true)
    end

    -- Draw player's menu/moves grid or the choose-pokemon party list
    if M.itemSelectMode then
        -- Draw overlay box for Pokemon selection
        local boxW = ww * 0.5
        local boxH = hh * 0.45
        local boxX = (ww - boxW) / 2
        local boxY = hh * 0.28
        
        UI.drawOverlay()
        UI.drawBox(boxX, boxY, boxW, boxH, 3)
        
        UI.drawTitle("USE ON WHICH POKEMON?", boxX, boxY + 8, boxW)
        
        local party = (M.player and M.player.party) or {}
        local lh = (font and font:getHeight() or 12) + 8
        local count = #party
        local listX = boxX + 20
        local listY = boxY + 35
        
        if count == 0 then
            love.graphics.setColor(unpack(UI.colors.textGray))
            love.graphics.print("No Pokemon", listX, listY)
        else
            for i, p in ipairs(party) do
                local y = listY + (i-1) * lh
                local name = tostring(p.nickname or p.name or "Unknown")
                local lvl = tostring(p.level or "?")
                local hp = tostring(p.currentHP or 0)
                local max = tostring((p.stats and p.stats.hp) or p.maxHp or p.hp or "?")
                local statusStr = UI.getStatusString(p)
                local line = string.format("%s  Lv%s  HP:%s/%s", name, lvl, hp, max)
                if statusStr then line = line .. "  [" .. statusStr .. "]" end
                UI.drawOption(line, listX, y, i == M.chooseIndex)
            end
        end
        
        -- Cancel option
        local cancelY = listY + count * lh
        UI.drawOption("Cancel", listX, cancelY, M.chooseIndex == count + 1)
        
    elseif M.mode == "choose_pokemon" then
        -- Draw overlay box for Pokemon selection
        local boxW = ww * 0.5
        local boxH = hh * 0.5
        local boxX = (ww - boxW) / 2
        local boxY = hh * 0.25
        
        UI.drawOverlay()
        UI.drawBox(boxX, boxY, boxW, boxH, 3)
        
        UI.drawTitle("POKEMON", boxX, boxY + 8, boxW)
        
        local party = (M.player and M.player.party) or {}
        local lh = (font and font:getHeight() or 12) + 8
        local count = #party
        local listX = boxX + 20
        local listY = boxY + 35
        
        if count == 0 then
            love.graphics.setColor(unpack(UI.colors.textGray))
            love.graphics.print("No Pokemon", listX, listY)
            local backY = listY + lh
            UI.drawOption("Back", listX, backY, M.chooseIndex == 1)
        else
            for i, p in ipairs(party) do
                local y = listY + (i-1) * lh
                local name = tostring(p.nickname or p.name or "Unknown")
                local lvl = tostring(p.level or "?")
                local hp = tostring(p.currentHP or 0)
                local max = tostring((p.stats and p.stats.hp) or p.maxHp or p.hp or "?")
                local statusStr = UI.getStatusString(p)
                local line = string.format("%s  Lv%s  HP:%s/%s", name, lvl, hp, max)
                if statusStr then line = line .. "  [" .. statusStr .. "]" end
                UI.drawOption(line, listX, y, i == M.chooseIndex)
            end
            -- Back option
            local by = listY + count * lh
            UI.drawOption("Back", listX, by, M.chooseIndex == count + 1)
        end
    elseif M.mode == "items" then
        -- Draw items overlay box
        local boxW = ww * 0.55
        local boxH = hh * 0.5
        local boxX = (ww - boxW) / 2
        local boxY = hh * 0.25
        
        UI.drawOverlay()
        UI.drawBox(boxX, boxY, boxW, boxH, 3)
        
        UI.drawTitle("ITEMS", boxX, boxY + 8, boxW)
        
        local lh = (font and font:getHeight() or 12) + 8
        local listX = boxX + 20
        local listY = boxY + 55
        
        -- Show category tabs with left/right arrows
        local category = M.battleItemCategories[M.battleCurrentCategory]
        local categoryDisplay = (category:gsub("_", " ")):sub(1,1):upper() .. (category:gsub("_", " ")):sub(2)
        local categoryText = "<  " .. categoryDisplay .. "  >"
        love.graphics.setColor(unpack(UI.colors.textHighlight))
        love.graphics.printf(categoryText, boxX, boxY + 32, boxW, "center")
        
        local itemCount = #M.battleCategoryItems
        
        if itemCount == 0 then
            love.graphics.setColor(unpack(UI.colors.textGray))
            love.graphics.print("No items", listX, listY)
            local backY = listY + lh
            UI.drawOption("Back", listX, backY, M.selectedOption == 1)
        else
            for i, item in ipairs(M.battleCategoryItems) do
                local y = listY + (i-1) * lh
                -- Show if item can be used in battle
                local usable = item:canUse("battle")
                local line = string.format("%s x%s%s", item.data.name, tostring(item.quantity), usable and "" or " (X)")
                
                if i == M.selectedOption then
                    love.graphics.setColor(unpack(UI.colors.textSelected))
                    love.graphics.print(">", listX - 15, y)
                end
                
                if not usable then
                    love.graphics.setColor(unpack(UI.colors.textGray))
                else
                    love.graphics.setColor(unpack(UI.colors.textDark))
                end
                love.graphics.print(line, listX, y)
            end
            -- Back option
            local by = listY + itemCount * lh
            UI.drawOption("Back", listX, by, M.selectedOption == itemCount + 1)
        end
    else
        local opts = (M.mode == "menu") and M.menuOptions or M.moveOptions
        -- Bottom action panel area
        local actionPanelH = hh * 0.3
        local actionPanelY = hh - actionPanelH
        
        -- Draw action panel background
        UI.drawBox(0, actionPanelY, ww, actionPanelH, 3)
        
        local cols = 2
        local pad = 15
        if opts and #opts > 0 then
            local menuAreaW = (M.mode == "moves") and (ww * 0.6) or (ww * 0.9)
            local cellW = (menuAreaW - pad * 3) / cols
            local cellH = (font and font:getHeight() or 12) + 12
            local menuX = pad
            local menuY = actionPanelY + 20
            
            for i, opt in ipairs(opts) do
                local r = math.floor((i - 1) / cols)
                local c = (i - 1) % cols
                local x = menuX + c * (cellW + pad)
                local y = menuY + r * (cellH + 8)
                local label = opt
                if type(opt) == "table" and opt.name then 
                    label = opt.name 
                elseif type(opt) == "string" then
                    -- Convert move IDs like "thunder_shock" to "Thunder Shock"
                    label = opt:gsub("_", " "):gsub("(%l)(%w*)", function(a,b) return a:upper()..b end)
                end
                if M.mode == "moves" then if not label or label == "" then label = "---" end end
                
                -- Draw option cell with border
                if i == M.selectedOption then
                    love.graphics.setColor(0.9, 0.95, 1, 1)
                    love.graphics.rectangle("fill", x - 5, y - 3, cellW + 10, cellH + 2, 3)
                    love.graphics.setColor(unpack(UI.colors.textSelected))
                    love.graphics.rectangle("line", x - 5, y - 3, cellW + 10, cellH + 2, 3)
                    love.graphics.setColor(unpack(UI.colors.textSelected))
                else
                    love.graphics.setColor(unpack(UI.colors.textDark))
                end
                love.graphics.printf(label, x, y, cellW, "center")
            end

            -- Draw move info panel when in moves mode
            if M.mode == "moves" then
                local infoW = ww * 0.35
                local infoH = actionPanelH - 20
                local infoX = ww - infoW - 10
                local infoY = actionPanelY + 10
                
                -- Info panel with border
                love.graphics.setColor(0.95, 0.97, 0.95, 1)
                love.graphics.rectangle("fill", infoX, infoY, infoW, infoH, 5)
                love.graphics.setColor(unpack(UI.colors.borderDark))
                love.graphics.rectangle("line", infoX, infoY, infoW, infoH, 5)

                -- Resolve the selected move object (try to require moves module)
                local sel = M.moveOptions[M.selectedOption]
                local mvobj = nil
                if sel then
                    if type(sel) == "table" then mvobj = sel
                    elseif type(sel) == "string" then
                        local ok, mm = pcall(require, "moves")
                        if ok and mm then
                            local key = sel
                            local norm = sel:gsub("%s+", "")
                            local norm2 = norm:gsub("%p", "")
                            local lkey = string.lower(key)
                            local lnorm = string.lower(norm)
                            local lnorm2 = string.lower(norm2)
                            local cls = mm[key] or mm[norm] or mm[norm2] or mm[lkey] or mm[lnorm] or mm[lnorm2]
                            if cls and type(cls) == "table" and cls.new then
                                local suc, inst = pcall(function() return cls:new() end)
                                if suc and inst then mvobj = inst end
                            elseif mm.Move and mm.Move.new then
                                local suc, inst = pcall(function() return mm.Move:new({ name = sel }) end)
                                if suc and inst then mvobj = inst end
                            end
                        end
                    end
                end
                -- Fallback to a minimal object with name
                if not mvobj then mvobj = (type(sel) == "string") and { name = sel } or mvobj end

                local function getfirst(o, ...)
                    if not o then return nil end
                    for ii = 1, select('#', ...) do
                        local k = select(ii, ...)
                        if o[k] ~= nil then return o[k] end
                    end
                    return nil
                end

                local mvname = getfirst(mvobj, 'name', 'Name') or "Unknown"
                local mvtype = getfirst(mvobj, 'type', 't', 'moveType') or "-"
                local ppcur = getfirst(mvobj, 'pp', 'current_pp', 'currentPP')
                local pptot = getfirst(mvobj, 'total_pp', 'maxpp', 'pp_max', 'ppTotal', 'maxPP', 'max_pp')
                -- If only one pp field present, show as / total if possible
                if ppcur == nil and pptot ~= nil then ppcur = pptot end
                if pptot == nil and ppcur ~= nil then pptot = ppcur end

                local linesp = 22
                love.graphics.setColor(unpack(UI.colors.textDark))
                love.graphics.printf(tostring(mvname), infoX, infoY + 10, infoW, "center")
                love.graphics.setColor(unpack(UI.colors.textGray))
                love.graphics.printf("Type: " .. tostring(mvtype), infoX + 10, infoY + 10 + linesp, infoW - 20, "left")
                local pptext = "PP: " .. (pptot and tostring(ppcur or "-") .. "/" .. tostring(pptot) or "-/-")
                love.graphics.printf(pptext, infoX + 10, infoY + 10 + linesp * 2, infoW - 20, "left")
            end
        end
    end
    
    -- Draw battle log overlay at bottom only when waiting for acknowledgement.
    if M.waitingForZ and #M.battleLog > 0 then
        UI.drawMessageBox(M.battleLog[#M.battleLog].text or tostring(M.battleLog[#M.battleLog] or ""), 0, hh * 0.75, ww, hh * 0.2)
    end
    
    -- Prompt at the very bottom
    love.graphics.setColor(unpack(UI.colors.textGray))
    if M.waitingForZ then
        love.graphics.printf("Press Z to continue", 0, hh * 0.96, ww, "center")
    elseif M.awaitingClose and M.faintedName then
        local msg = (M.faintedName or "Pokemon") .. " fainted. Press Z to exit"
        love.graphics.printf(msg, 0, hh * 0.96, ww, "center")
    else
        love.graphics.printf("Press SPACE/B to exit", 0, hh * 0.96, ww, "center")
    end
    love.graphics.pop()
end

return M
