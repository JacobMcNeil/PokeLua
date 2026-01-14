local M = {}
local log = require("log")

M.active = false
M.p1 = nil
M.p2 = nil
M.menuOptions = { "Fight", "Pokemon", "Items", "Run" }
M.selectedOption = 1
M.mode = "menu" -- or "moves"
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
    local arr = {}
    if p.moves and #p.moves > 0 then
        for i = 1, 4 do
            local mv = p.moves[i]
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
    p._move_instances = arr
end

local function queueLog(entry)
    if not entry then return end
    local item
    if type(entry) == "table" and entry.text then
        item = { text = entry.text, action = entry.action or function() end }
    else
        item = { text = tostring(entry), action = function() end }
    end
    table.insert(M.logQueue, item)
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
        if type(mvobj) == "table" then
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
            else
                log.log("battle: move execution failed. ok=", ok, " result=", result)
            end
        end
        
        if not moveSuccessful then
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
                                
                                local levelsGained = participatingPoke:gainExp(expShare)
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
                                                queueLog((participatingPoke.nickname or "Pokémon") .. " learned " .. move .. "!")
                                            end
                                        end
                                    end
                                    -- Refresh move instances if moves were learned
                                    refreshMoveInstances(participatingPoke)
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
                        M.awaitingClose = true
                        M.faintedName = M.p1 and M.p1.nickname or "Player"
                    end
                elseif defender == M.p2 then
                    M.awaitingClose = true
                    M.faintedName = M.p2 and M.p2.nickname or "Opponent"
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

    queueLog({ text = (attacker.nickname or tostring(attacker)) .. " uses " .. mvlabel, action = action })
end

local function chooseTwo(list)
    if not list or #list == 0 then return nil, nil end
    if #list == 1 then return list[1], nil end
    local i = math.random(1, #list)
    local j = math.random(1, #list)
    while j == i do j = math.random(1, #list) end
    return list[i], list[j]
end

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

    if not list or #list == 0 then
        -- fallback simple names
        M.p1 = { nickname = "WildMonA", currentHP = 10, speed = 10, stats = { hp = 10 } }
        M.p2 = { nickname = "WildMonB", currentHP = 10, speed = 10, stats = { hp = 10 } }
    else
        -- If a player object with a party is provided, use their first party member as p1
        if playerObj and playerObj.party and #playerObj.party >= 1 then
            -- choose the first alive pokemon in the player's party (currentHP > 0).
            local chosen = nil
            for _, p in ipairs(playerObj.party) do
                if p then
                    if p.currentHP == nil or p.currentHP > 0 then
                        chosen = p
                        break
                    end
                end
            end
            -- fallback to first slot if none alive
            if not chosen then chosen = playerObj.party[1] end
            M.p1 = chosen
            -- pick a random opponent from the wild list
            local idx = math.random(1, #list)
            M.p2 = list[idx]
        else
            M.p1, M.p2 = chooseTwo(list)
        end
    end
    -- Ensure each Pokemon has its own move instances so PP persists per-pokemon.
    for _, p in ipairs({M.p1, M.p2}) do
        if p then
            if not p._move_instances then
                local arr = {}
                if p.moves and #p.moves > 0 then
                    for i = 1, 4 do
                        local mv = p.moves[i]
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
                p._move_instances = arr
            end
        end
    end
    M.active = true
    M.selectedOption = 1
    M.mode = "menu"
    -- store player object for party access when switching Pokemon
    M.player = playerObj
    M.chooseIndex = 1
    
    -- Initialize participation tracking: mark p1 as having participated
    M.participatingPokemon = {}
    if M.p1 then
        table.insert(M.participatingPokemon, M.p1)
    end
end

function M.isActive()
    return M.active
end

M["end"] = function()
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
        elseif key == "space" then
            -- cancel/forfeit battle
            M["end"]()
            return
        elseif key == "return" or key == "z" or key == "enter" then
            if M.chooseIndex == count + 1 then
                -- Back option: if the player opened the party from the menu to switch,
                -- then Back should return to the battle menu. If this was a forced
                -- replacement (context "forced"), treat Back as a forfeit and end.
                if M.choose_context == "menu_switch" then
                    M.mode = "menu"
                    M.selectedOption = 1
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
                    M.p1 = sel
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

                -- determine order by speed stat (higher first). ties: random
                local p1spd = (M.p1.stats and M.p1.stats.speed) or 10
                local p2spd = (M.p2.stats and M.p2.stats.speed) or 10
                if p1spd > p2spd then
                    -- player first: queue player's move, then queue opponent if still alive
                    queueMove(M.p1, M.p2, mv, function()
                        if M.p2 and (M.p2.currentHP or 0) > 0 then
                            queueMove(M.p2, M.p1, omv)
                        end
                    end)
                elseif p2spd > p1spd then
                    -- opponent first
                    queueMove(M.p2, M.p1, omv, function()
                        if M.p1 and (M.p1.currentHP or 0) > 0 then
                            queueMove(M.p1, M.p2, mv)
                        end
                    end)
                else
                    -- tie: randomize who goes first
                    if math.random(0,1) == 1 then
                        queueMove(M.p1, M.p2, mv, function()
                            if M.p2 and (M.p2.currentHP or 0) > 0 then
                                queueMove(M.p2, M.p1, omv)
                            end
                        end)
                    else
                        queueMove(M.p2, M.p1, omv, function()
                            if M.p1 and (M.p1.currentHP or 0) > 0 then
                                queueMove(M.p1, M.p2, mv)
                            end
                        end)
                    end
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
    -- quick exits (existing behavior)
    if key == "space" or key == "b" or key == "escape" then
        M["end"]()
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
end

function M.draw()
    if not M.active then return end
    love.graphics.push()
    love.graphics.origin()
    local ww, hh = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, ww, hh)
    love.graphics.setColor(1,1,1,1)
    local font = love.graphics.getFont()
    love.graphics.printf("BATTLE", 0, hh * 0.08, ww, "center")

    local function name_with_level(p)
        if not p then return "---" end
        local nm = p.nickname or p.name or tostring(p)
        local lv = p.level or p.l or nil
        if lv then
            return string.format("%s L:%s", tostring(nm), tostring(lv))
        end
        return tostring(nm)
    end
    -- Opponent area (top): sprite on right, name+hp on left
    local lineH = (font and font:getHeight() or 12) + 4
    local oppAreaY = hh * 0.06
    local oppAreaH = hh * 0.28
    local oppSpriteW = math.min(oppAreaH * 0.8, ww * 0.28)
    local oppSpriteX = ww - oppSpriteW - 20
    local oppSpriteY = oppAreaY + (oppAreaH - oppSpriteW) / 2
    local oppTextX = 20
    local oppTextW = oppSpriteX - oppTextX - 12
    local oppName = name_with_level(M.p2)
    local oppCur = (M.p2 and (M.p2.currentHP ~= nil)) and tostring(M.p2.currentHP) or "-"
    local oppMax = (M.p2 and M.p2.stats and M.p2.stats.hp) and tostring(M.p2.stats.hp) or "-"
    local oppHpText = oppCur .. "/" .. oppMax
    love.graphics.printf(oppName, oppTextX, oppAreaY + 8, oppTextW, "left")
    love.graphics.printf("HP: " .. oppHpText, oppTextX, oppAreaY + 8 + lineH, oppTextW, "left")
    -- sprite placeholder (if sprite drawing exists, replace this)
    love.graphics.setColor(1,1,1,0.08)
    love.graphics.rectangle("fill", oppSpriteX, oppSpriteY, oppSpriteW, oppSpriteW)
    love.graphics.setColor(1,1,1,1)

    -- Player area (just above menus): sprite on left, name+hp on right
    local playerAreaY = hh * 0.46
    local playerAreaH = hh * 0.24
    local playerSpriteW = math.min(playerAreaH * 0.8, ww * 0.28)
    local playerSpriteX = 20
    local playerSpriteY = playerAreaY + (playerAreaH - playerSpriteW) / 2
    -- Place player's name/hp block at the far right of the screen
    local playerTextW = math.min(ww * 0.45, ww - playerSpriteX - playerSpriteW - 40)
    local playerTextX = ww - playerTextW - 20
    local playerName = name_with_level(M.p1)
    local playerCur = (M.p1 and (M.p1.currentHP ~= nil)) and tostring(M.p1.currentHP) or "-"
    local playerMax = (M.p1 and M.p1.stats and M.p1.stats.hp) and tostring(M.p1.stats.hp) or "-"
    local playerHpText = playerCur .. "/" .. playerMax
    love.graphics.setColor(1,1,1,1)
    love.graphics.printf(playerName, playerTextX, playerAreaY + 8, playerTextW, "right")
    love.graphics.printf("HP: " .. playerHpText, playerTextX, playerAreaY + 8 + lineH, playerTextW, "right")
    love.graphics.setColor(1,1,1,0.08)
    love.graphics.rectangle("fill", playerSpriteX, playerSpriteY, playerSpriteW, playerSpriteW)
    love.graphics.setColor(1,1,1,1)

    -- Draw player's menu/moves grid or the choose-pokemon party list
    if M.mode == "choose_pokemon" then
        love.graphics.printf("POKEMON", 0, hh * 0.32, ww, "center")
        local party = (M.player and M.player.party) or {}
        local startY = hh * 0.38
        local lh = (font and font:getHeight() or 12) + 8
        local count = #party
        if count == 0 then
            love.graphics.print("No Pokemon", ww * 0.4, startY)
            local backY = startY + lh
            if M.chooseIndex == 1 then
                love.graphics.setColor(1, 0.9, 0, 1)
                love.graphics.print(">", ww * 0.35, backY)
                love.graphics.setColor(1,1,1,1)
            end
            love.graphics.print("Back", ww * 0.4, backY)
        else
            for i, p in ipairs(party) do
                local y = startY + (i-1) * lh
                if i == M.chooseIndex then
                    love.graphics.setColor(1, 0.9, 0, 1)
                    love.graphics.print(">", ww * 0.35, y)
                    love.graphics.setColor(1,1,1,1)
                end
                local name = tostring(p.nickname or p.name or "Unknown")
                local lvl = tostring(p.level or "?")
                local hp = tostring(p.currentHP or 0)
                local max = tostring((p.stats and p.stats.hp) or p.maxHp or p.hp or "?")
                local line = string.format("%s  L:%s  HP:%s/%s", name, lvl, hp, max)
                love.graphics.print(line, ww * 0.4, y)
            end
            -- Back option
            local by = startY + count * lh
            if M.chooseIndex == count + 1 then
                love.graphics.setColor(1, 0.9, 0, 1)
                love.graphics.print(">", ww * 0.35, by)
                love.graphics.setColor(1,1,1,1)
            end
            love.graphics.print("Back", ww * 0.4, by)
        end
    else
        local opts = (M.mode == "menu") and M.menuOptions or M.moveOptions
        -- Place the fight/move menus in the same bottom area used for the log,
        -- reserving space on the right for move info when in `moves` mode.
        local logX = 0
        local logW = ww
        local logY = hh * 0.72
        local cols = 2
        local pad = 8
        if opts and #opts > 0 then
            local menuAreaW = logW * 0.65
            local infoW = logW - menuAreaW - pad * 3
            if infoW < 140 then infoW = 140 end
            local cellW = (menuAreaW - pad * 2) / cols
            local cellH = hh * 0.04
            -- Move menus lower so they sit directly above the log overlay
            local menuY = logY - cellH * 1.0
            for i, opt in ipairs(opts) do
                local r = math.floor((i - 1) / cols)
                local c = (i - 1) % cols
                local x = logX + pad + c * cellW
                local y = menuY + r * (cellH + 6)
                local label = opt
                if type(opt) == "table" and opt.name then 
                    label = opt.name 
                elseif type(opt) == "string" then
                    -- Convert move IDs like "thunder_shock" to "Thunder Shock"
                    label = opt:gsub("_", " "):gsub("(%l)(%w*)", function(a,b) return a:upper()..b end)
                end
                if M.mode == "moves" then if not label or label == "" then label = "---" end end
                if i == M.selectedOption then
                    love.graphics.setColor(1, 1, 0, 1)
                else
                    love.graphics.setColor(1, 1, 1, 1)
                end
                love.graphics.printf(label, x, y, cellW, "center")
            end
            love.graphics.setColor(1,1,1,1)

            -- Draw move info panel when in moves mode
            if M.mode == "moves" then
                local infoX = logX + menuAreaW + pad * 2
                local infoY = menuY
                love.graphics.setColor(0,0,0,0.6)
                love.graphics.rectangle("fill", infoX - pad/2, infoY - pad/2, infoW + pad, cellH * 3 + pad)
                love.graphics.setColor(1,1,1,1)

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
                    for i = 1, select('#', ...) do
                        local k = select(i, ...)
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

                love.graphics.printf(tostring(mvname), infoX, infoY, infoW, "center")
                local linesp = cellH
                local ly = infoY + linesp
                love.graphics.printf("Type: " .. tostring(mvtype), infoX + 6, ly, infoW - 12, "left")
                ly = ly + linesp
                local pptext = "PP: " .. (pptot and tostring(ppcur or "-") .. "/" .. tostring(pptot) or "-/-")
                love.graphics.printf(pptext, infoX + 6, ly, infoW - 12, "left")
            end
        end
    end
    -- Draw battle log overlay at bottom only when waiting for acknowledgement.
    local logX = 0
    local logW = ww
    local logY = hh * 0.72
    local lineH = hh * 0.04
    if M.waitingForZ and #M.battleLog > 0 then
        -- Make overlay smaller but still cover the menus; reduce height
        local overlayTop = logY - hh * 0.08
        if overlayTop < 0 then overlayTop = 0 end
        local overlayH = (hh - overlayTop)
        love.graphics.setColor(0,0,0,0.9)
        love.graphics.rectangle("fill", logX, overlayTop, logW, overlayH)
        love.graphics.setColor(1,1,1,1)
        local itm = M.battleLog[#M.battleLog]
        local text = (itm and itm.text) and itm.text or tostring(itm or "")
        -- Draw the log text near the top of the overlay so it sits above menus
        love.graphics.printf(text, logX + 12, overlayTop + lineH * 0.6, logW - 24, "left")
    end
    -- Prompt: either waiting for next log, or awaiting close, or generic exit hint
    if M.waitingForZ then
        love.graphics.printf("Press Z to continue", 0, hh * 0.92, ww, "center")
    elseif M.awaitingClose and M.faintedName then
        local msg = (M.faintedName or "Pokémon") .. " fainted. Press Z to exit"
        love.graphics.printf(msg, 0, hh * 0.92, ww, "center")
    else
        love.graphics.printf("Press SPACE/B to exit", 0, hh * 0.92, ww, "center")
    end
    love.graphics.pop()
end

return M
