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
M.maxLogLines = 6
M.awaitingClose = false
M.faintedName = nil
M.player = nil
M.chooseIndex = 1

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
            -- create a small manual list of wild Pokemon using species classes
            list = {
                (pmod.Pikachu and pmod.Pikachu.new) and pmod.Pikachu.new() or pmod.Pokemon.new{ name = "Pikachu", level = 5, moves = {"Thunder Shock", "Quick Attack"} },
                (pmod.Bulbasaur and pmod.Bulbasaur.new) and pmod.Bulbasaur.new() or pmod.Pokemon.new{ name = "Bulbasaur", level = 5, moves = {"Tackle", "Vine Whip"} },
                (pmod.Squirtle and pmod.Squirtle.new) and pmod.Squirtle.new() or pmod.Pokemon.new{ name = "Squirtle", level = 5, moves = {"Tackle", "Water Gun"} },
                (pmod.Charmander and pmod.Charmander.new) and pmod.Charmander.new() or pmod.Pokemon.new{ name = "Charmander", level = 5, moves = {"Scratch", "Ember"} },
            }
            log.log("battle.start: created manual pokemon list, len=", #list)
        end
    end

    if not list or #list == 0 then
        -- fallback simple names
        M.p1 = { name = "WildMonA", hp = 10, speed = 10 }
        M.p2 = { name = "WildMonB", hp = 10, speed = 10 }
    else
        -- If a player object with a party is provided, use their first party member as p1
        if playerObj and playerObj.party and #playerObj.party >= 1 then
            -- choose the first alive pokemon in the player's party (hp > 0).
            local chosen = nil
            for _, p in ipairs(playerObj.party) do
                if p then
                    if p.hp == nil or p.hp > 0 then
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
    -- Ensure hp and speed are set for both pokemon (defaults)
    local function ensureStats(p)
        if not p then return end
        p.hp = (p.hp ~= nil) and p.hp or 10
        p.speed = (p.speed ~= nil) and p.speed or (p.spd or p.s or 10)
    end
    ensureStats(M.p1)
    ensureStats(M.p2)
    M.active = true
    M.selectedOption = 1
    M.mode = "menu"
    -- store player object for party access when switching Pokemon
    M.player = playerObj
    M.chooseIndex = 1
end

function M.isActive()
    return M.active
end

M["end"] = function()
    M.active = false
    M.p1 = nil
    M.p2 = nil
    M.awaitingClose = false
    M.faintedName = nil
end

function M.keypressed(key)
    if not M.active then return end
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
                -- Do not allow selecting a fainted Pokémon (hp <= 0).
                -- If hp is nil, treat the Pokémon as selectable (unknown/full).
                local sel_alive = false
                if sel then
                    if not (sel.hp ~= nil and sel.hp <= 0) then sel_alive = true end
                end
                if sel and sel_alive then
                    M.p1 = sel
                    -- initialize hp and maxHp sensibly
                    M.p1.hp = (M.p1.hp ~= nil and M.p1.hp) or (M.p1.maxHp ~= nil and M.p1.maxHp) or 10
                    M.p1.maxHp = M.p1.maxHp or M.p1.hp
                    M.p1.speed = M.p1.speed or 10
                    -- announce the switch
                    table.insert(M.battleLog, "Switched to " .. (M.p1.name or "Pokémon"))
                    if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end

                    -- If this selection was initiated from the menu as a switch, it consumes the turn
                    if M.choose_context == "menu_switch" then
                        -- opponent selects a move and immediately attacks the switched-in Pokemon
                        local omv = ""
                        if M.p2 and M.p2.moves and #M.p2.moves > 0 then
                            omv = M.p2.moves[math.random(1, #M.p2.moves)] or ""
                        end
                        -- ensure stats
                        M.p1.hp = (M.p1.hp ~= nil) and M.p1.hp or 10
                        M.p2.hp = (M.p2.hp ~= nil) and M.p2.hp or 10
                        M.p1.speed = (M.p1.speed ~= nil) and M.p1.speed or 10
                        M.p2.speed = (M.p2.speed ~= nil) and M.p2.speed or 10

                        local function performMove(attacker, defender, mvname)
                            if attacker and (attacker.hp or 0) <= 0 then
                                local entry = (attacker.name or "attacker") .. " can't move (fainted)"
                                table.insert(M.battleLog, entry)
                                if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end
                                return false
                            end
                            if not mvname or mvname == "" then
                                local entry = (attacker.name or "attacker") .. " has no move"
                                table.insert(M.battleLog, entry)
                                if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end
                                return false
                            end
                            local entry = (attacker.name or "attacker") .. " uses " .. mvname
                            table.insert(M.battleLog, entry)
                            if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end
                            local dmg = 20
                            defender.hp = (defender.hp or 0) - dmg
                            if defender.hp < 0 then defender.hp = 0 end
                            local dmgEntry = (defender.name or "target") .. " took " .. tostring(dmg) .. " dmg, hp=" .. tostring(defender.hp)
                            table.insert(M.battleLog, dmgEntry)
                            if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end
                            if defender.hp <= 0 then
                                local faintEntry = (defender.name or "target") .. " fainted"
                                table.insert(M.battleLog, faintEntry)
                                if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end
                                return true
                            end
                            return false
                        end

                        local fainted = performMove(M.p2, M.p1, omv)
                        if fainted then
                            local party = (M.player and M.player.party) or nil
                            local hasAlive = false
                            if party then
                                for _, pp in ipairs(party) do if pp and (pp.hp or 0) > 0 then hasAlive = true; break end end
                            end
                            if hasAlive then
                                M.mode = "choose_pokemon"
                                M.chooseIndex = 1
                                M.faintedName = M.p1 and M.p1.name or "Player"
                            else
                                M.awaitingClose = true
                                M.faintedName = M.p1 and M.p1.name or "Player"
                            end
                        else
                            -- opponent attacked but didn't faint the switched-in; return to menu
                            M.mode = "menu"
                            M.selectedOption = 1
                            M.moveOptions = {}
                            M.awaitingClose = false
                            M.faintedName = nil
                        end
                        M.choose_context = nil
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
                if M.p1 and (M.p1.hp or 0) <= 0 then
                    local party = (M.player and M.player.party) or nil
                    local hasAlive = false
                    if party then
                        for _, pp in ipairs(party) do if pp and (pp.hp or 0) > 0 then hasAlive = true; break end end
                    end
                    if hasAlive then
                        M.mode = "choose_pokemon"
                        M.choose_context = "forced"
                        M.chooseIndex = 1
                        return
                    else
                        M.awaitingClose = true
                        M.faintedName = M.p1 and M.p1.name or "Player"
                        return
                    end
                end
                -- populate moves into a 4-slot grid
                M.moveOptions = {}
                if M.p1 and M.p1.moves then
                    for i = 1, 4 do
                        M.moveOptions[i] = M.p1.moves[i] or ""
                    end
                else
                    for i = 1, 4 do M.moveOptions[i] = "" end
                end
                M.mode = "moves"
                M.selectedOption = 1
            elseif opt == "Pokemon" then
                -- allow switching from the menu; this will consume the player's turn
                local party = (M.player and M.player.party) or nil
                local hasAlive = false
                if party then
                    for _, pp in ipairs(party) do if pp and (pp.hp or 0) > 0 then hasAlive = true; break end end
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
                -- choose opponent move
                local omv = ""
                if M.p2 and M.p2.moves and #M.p2.moves > 0 then
                    omv = M.p2.moves[math.random(1, #M.p2.moves)] or ""
                end

                -- ensure hp and speed defaults exist
                M.p1.hp = (M.p1.hp ~= nil) and M.p1.hp or 10
                M.p2.hp = (M.p2.hp ~= nil) and M.p2.hp or 10
                M.p1.speed = (M.p1.speed ~= nil) and M.p1.speed or 10
                M.p2.speed = (M.p2.speed ~= nil) and M.p2.speed or 10

                local function performMove(attacker, defender, mvname)
                    -- do not allow a fainted attacker to act
                    if attacker and (attacker.hp or 0) <= 0 then
                        local entry = (attacker.name or "attacker") .. " can't move (fainted)"
                        table.insert(M.battleLog, entry)
                        if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end
                        return false
                    end
                    if not mvname or mvname == "" then
                        log.log("battle: ", attacker.name or "attacker", " has no move")
                        local entry = (attacker.name or "attacker") .. " has no move"
                        table.insert(M.battleLog, entry)
                        if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end
                        return false
                    end
                    log.log("battle: ", attacker.name or "attacker", " uses ", mvname)
                    local entry = (attacker.name or "attacker") .. " uses " .. mvname
                    table.insert(M.battleLog, entry)
                    if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end
                    local dmg = 20
                    defender.hp = (defender.hp or 0) - dmg
                    if defender.hp < 0 then defender.hp = 0 end
                    local dmgEntry = (defender.name or "target") .. " took " .. tostring(dmg) .. " dmg, hp=" .. tostring(defender.hp)
                    table.insert(M.battleLog, dmgEntry)
                    if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end
                    if defender.hp <= 0 then
                        local faintEntry = (defender.name or "target") .. " fainted"
                        table.insert(M.battleLog, faintEntry)
                        if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end
                        log.log("battle: "..(defender.name or "target").." fainted")
                        return true
                    end
                    return false
                end

                local function levelUpIfPlayerDefeated(attacker, defender)
                    if attacker == M.p1 and defender == M.p2 then
                        local p = attacker
                        p.level = (p.level or 1) + 1
                        p.maxHp = (p.maxHp or 10) + 5
                        p.attack = (p.attack or 5) + 2
                        p.defense = (p.defense or 5) + 2
                        p.spAttack = (p.spAttack or 5) + 2
                        p.spDefense = (p.spDefense or 5) + 2
                        p.speed = (p.speed or 10) + 1
                        local entry = (p.name or "Pokémon") .. " leveled up"
                        table.insert(M.battleLog, entry)
                        if #M.battleLog > M.maxLogLines then table.remove(M.battleLog, 1) end
                        log.log("battle: leveled up ", p.name or "pok", " to ", p.level)
                    end
                end

                -- determine order by numeric speed (higher first). ties: random
                local p1spd = tonumber(M.p1.speed) or 0
                local p2spd = tonumber(M.p2.speed) or 0
                if p1spd > p2spd then
                    -- player first
                    local fainted = performMove(M.p1, M.p2, mv)
                    if fainted then
                            levelUpIfPlayerDefeated(M.p1, M.p2)
                            M.awaitingClose = true
                            M.faintedName = M.p2 and M.p2.name or "Opponent"
                        else
                        local fainted2 = performMove(M.p2, M.p1, omv)
                        if fainted2 then
                            -- player's pokemon fainted: prompt to choose another if available
                            local party = (M.player and M.player.party) or nil
                            local hasAlive = false
                            if party then
                                for _, pp in ipairs(party) do if pp and (pp.hp or 0) > 0 then hasAlive = true; break end end
                            end
                            if hasAlive then
                                M.mode = "choose_pokemon"
                                M.chooseIndex = 1
                                M.faintedName = M.p1 and M.p1.name or "Player"
                            else
                                M.awaitingClose = true
                                M.faintedName = M.p1 and M.p1.name or "Player"
                            end
                        end
                    end
                elseif p2spd > p1spd then
                    -- opponent first
                    local fainted = performMove(M.p2, M.p1, omv)
                    if fainted then
                        local party = (M.player and M.player.party) or nil
                        local hasAlive = false
                        if party then
                            for _, pp in ipairs(party) do if pp and (pp.hp or 0) > 0 then hasAlive = true; break end end
                        end
                        if hasAlive then
                            M.mode = "choose_pokemon"
                            M.chooseIndex = 1
                            M.faintedName = M.p1 and M.p1.name or "Player"
                        else
                            M.awaitingClose = true
                            M.faintedName = M.p1 and M.p1.name or "Player"
                        end
                    else
                        local fainted2 = performMove(M.p1, M.p2, mv)
                        if fainted2 then
                            levelUpIfPlayerDefeated(M.p1, M.p2)
                            M.awaitingClose = true
                            M.faintedName = M.p2 and M.p2.name or "Opponent"
                        end
                    end
                else
                    -- tie: randomize who goes first
                    if math.random(0,1) == 1 then
                        local fainted = performMove(M.p1, M.p2, mv)
                        if fainted then
                            levelUpIfPlayerDefeated(M.p1, M.p2)
                            M.awaitingClose = true
                            M.faintedName = M.p2 and M.p2.name or "Opponent"
                        else
                            local fainted2 = performMove(M.p2, M.p1, omv)
                            if fainted2 then
                                local party = (M.player and M.player.party) or nil
                                local hasAlive = false
                                if party then
                                    for _, pp in ipairs(party) do if pp and (pp.hp or 0) > 0 then hasAlive = true; break end end
                                end
                                if hasAlive then
                                    M.mode = "choose_pokemon"
                                    M.chooseIndex = 1
                                    M.faintedName = M.p1 and M.p1.name or "Player"
                                else
                                    M.awaitingClose = true
                                    M.faintedName = M.p1 and M.p1.name or "Player"
                                end
                            end
                        end
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
    -- future battle logic
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
        local nm = p.name or tostring(p)
        local lv = p.level or p.l or nil
        if lv then
            return string.format("%s L:%s", tostring(nm), tostring(lv))
        end
        return tostring(nm)
    end
    local left = name_with_level(M.p1)
    local right = name_with_level(M.p2)
    local left_hp = M.p1 and (tostring(M.p1.hp) or "---") or "---"
    local right_hp = M.p2 and (tostring(M.p2.hp) or "---") or "---"
    love.graphics.printf(left, 0, hh * 0.36, ww * 0.45, "center")
    love.graphics.printf("HP: " .. left_hp, 0, hh * 0.44, ww * 0.45, "center")
    love.graphics.printf(right, ww * 0.55, hh * 0.36, ww * 0.45, "center")
    love.graphics.printf("HP: " .. right_hp, ww * 0.55, hh * 0.44, ww * 0.45, "center")

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
                local name = tostring(p.name or "Unknown")
                local lvl = tostring(p.level or "?")
                local hp = tostring(p.hp or 0)
                local max = tostring(p.maxHp or p.hp or "?")
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
        if opts and #opts > 0 then
            local leftX = 0
            local leftW = ww * 0.45
            local cols = 2
            local cellW = leftW / cols
            local cellH = hh * 0.06
            local menuY = hh * 0.50
            for i, opt in ipairs(opts) do
                local r = math.floor((i - 1) / cols)
                local c = (i - 1) % cols
                local x = leftX + c * cellW
                local y = menuY + r * cellH
                local label = opt
                if M.mode == "moves" then
                    if not label or label == "" then label = "---" end
                end
                if i == M.selectedOption then
                    love.graphics.setColor(1, 1, 0, 1)
                else
                    love.graphics.setColor(1, 1, 1, 1)
                end
                love.graphics.printf(label, x, y, cellW, "center")
            end
            love.graphics.setColor(1,1,1,1)
        end
    end
    -- Draw battle log at bottom
    local logX = 0
    local logW = ww
    local logY = hh * 0.72
    local lineH = hh * 0.04
    love.graphics.setColor(0,0,0,0.6)
    love.graphics.rectangle("fill", logX, logY - lineH * 0.25, logW, lineH * (M.maxLogLines + 0.5))
    love.graphics.setColor(1,1,1,1)
    for i = 1, math.min(#M.battleLog, M.maxLogLines) do
        local idx = #M.battleLog - math.min(#M.battleLog, M.maxLogLines) + i
        local text = M.battleLog[idx]
        love.graphics.printf(text, logX + 8, logY + (i-1) * lineH, logW - 16, "left")
    end
    -- If a pokemon fainted, show a message and prompt for Z to close
    if M.awaitingClose and M.faintedName then
        local msg = (M.faintedName or "Pokémon") .. " fainted. Press Z to exit"
        love.graphics.printf(msg, 0, hh * 0.92, ww, "center")
    else
        love.graphics.printf("Press SPACE/B to exit", 0, hh * 0.92, ww, "center")
    end
    love.graphics.pop()
end

return M
