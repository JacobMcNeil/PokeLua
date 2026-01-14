-- menu.lua
local M = {}

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
M.options = {"Pokemon", "Bag", "Heal", "Save", "Exit"}
M.selected = 1
M.showPokemon = false
M.pokemonSelected = 1
M.showPokemonDetails = false
M.pokemonDetailsIndex = 1

local log = require("log")

function M.toggle()
    M.open = not M.open
    if M.open then
        M.showPokemon = false
        M.selected = 1
        M.pokemonSelected = 1
    else
        M.showPokemon = false
    end
end

function M.close()
    M.open = false
    M.showPokemon = false
    M.selected = 1
    M.pokemonSelected = 1
end

function M.isOpen()
    return M.open
end

function M.update(dt)
    -- reserved for future menu animation/logic
end

function M.keypressed(key)
    if not M.open then return end
    if M.showPokemon then
        if M.showPokemonDetails then
            -- In details view: any confirm/back key returns to the party list
            if key == "space" or key == "return" or key == "z" or key == "Z" then
                M.showPokemonDetails = false
                return
            end
            return
        end
        if key == "up" then
            M.pokemonSelected = M.pokemonSelected - 1
            if M.pokemonSelected < 1 then
                -- wrap to back option
                local count = (M.player and M.player.party) and #M.player.party or 0
                M.pokemonSelected = count + 1
            end
        elseif key == "down" then
            local count = (M.player and M.player.party) and #M.player.party or 0
            M.pokemonSelected = M.pokemonSelected + 1
            if M.pokemonSelected > count + 1 then M.pokemonSelected = 1 end
        elseif key == "space" then
            -- close menu from any submenu
            M.close()
            return
        elseif key == "return" or key == "z" or key == "Z" then
            local count = (M.player and M.player.party) and #M.player.party or 0
            if M.pokemonSelected == count + 1 then
                -- Back selected
                M.showPokemon = false
                M.pokemonSelected = 1
                return
            else
                -- show details for selected Pokemon and log base/IV/EV
                M.showPokemonDetails = true
                M.pokemonDetailsIndex = M.pokemonSelected
                -- log base stats, IVs and EVs for the selected Pokemon
                local idx = M.pokemonDetailsIndex
                local p = (M.player and M.player.party and M.player.party[idx]) and M.player.party[idx] or nil
                if p then
                    log.log("Selected Pokémon: " .. tostring(p.name or "Unknown"))
                    local statNames = {"hp","attack","defense","spAttack","spDefense","speed"}
                    for _, sname in ipairs(statNames) do
                        local base = (p.stats and p.stats.base and p.stats.base[sname]) or p[sname] or p[sname:sub(1,1):upper() .. sname:sub(2)] or "?"
                        local iv = (p.stats and p.stats.ivs and p.stats.ivs[sname]) or (p.ivs and p.ivs[sname]) or 15
                        local ev = (p.stats and p.stats.evs and p.stats.evs[sname]) or (p.evs and p.evs[sname]) or 0
                        log.log(string.format(" %s: base=%s iv=%s ev=%s", sname, tostring(base), tostring(iv), tostring(ev)))
                    end
                end
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

function M.draw()
    if not M.open then return end
    love.graphics.push()
    love.graphics.origin()
    local ww, hh = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, ww, hh)

    love.graphics.setColor(1,1,1,1)
    local font = love.graphics.getFont()
    local title = "MENU"
    local titleY = hh * 0.18
    love.graphics.printf(title, 0, titleY, ww, "center")
    -- either show menu list or Pokemon party
    local startY = hh * 0.32
    local lh = (font and font:getHeight() or 12) + 8
    if M.showPokemon then
        love.graphics.printf("POKEMON", 0, startY - lh, ww, "center")
        local count = (M.player and M.player.party) and #M.player.party or 0
        
        if M.showPokemonDetails then
            local idx = M.pokemonDetailsIndex or 1
            local p = (M.player and M.player.party and M.player.party[idx]) and M.player.party[idx] or nil
            local infoY = startY
            if not p then
                love.graphics.print("No data", ww * 0.4, infoY)
            else
                local name = tostring(p.nickname or p.name or "Unknown")
                local lvl = tostring(p.level or "?")
                love.graphics.print(string.format("%s  L:%s", name, lvl), ww * 0.36, infoY)
                infoY = infoY + lh

                -- HP: show current / max
                local curHp = p.currentHP or 0
                local maxHp = p.stats and p.stats.hp or "?"
                love.graphics.print(string.format("HP: %s / %s", tostring(curHp), tostring(maxHp)), ww * 0.36, infoY)
                infoY = infoY + lh

                -- Other stats
                local function eff(stat)
                    if p.stats then
                        return p.stats[stat] or "?"
                    else
                        return "?"
                    end
                end

                love.graphics.print("Attack: " .. tostring(eff("attack")), ww * 0.36, infoY)
                infoY = infoY + lh
                love.graphics.print("Defense: " .. tostring(eff("defense")), ww * 0.36, infoY)
                infoY = infoY + lh
                love.graphics.print("Sp. Atk: " .. tostring(eff("spAttack")), ww * 0.36, infoY)
                infoY = infoY + lh
                love.graphics.print("Sp. Def: " .. tostring(eff("spDefense")), ww * 0.36, infoY)
                infoY = infoY + lh
                love.graphics.print("Speed: " .. tostring(eff("speed")), ww * 0.36, infoY)
                infoY = infoY + lh

                -- Experience info
                local currentExp = p.exp or 0
                local currentLevelExp = 0
                local nextLevelExp = 0
                if p.getExpForLevel and type(p.getExpForLevel) == "function" then
                    currentLevelExp = p:getExpForLevel(p.level)
                    nextLevelExp = p:getExpForLevel(p.level + 1)
                end
                local expStillNeeded = nextLevelExp - currentExp
                
                love.graphics.print(string.format("%s to next level", tostring(expStillNeeded)), ww * 0.36, infoY)
                love.graphics.print(string.format("%s / %s", tostring(currentExp), tostring(nextLevelExp)), ww * 0.65, infoY)
                infoY = infoY + lh

                love.graphics.print("(Press Z/Enter/Space to go back)", ww * 0.36, infoY)
            end
            love.graphics.pop()
            return
        end
        if count == 0 then
            love.graphics.print("No Pokemon", ww * 0.4, startY)
            -- draw Back option below
            local backY = startY + lh
            if M.pokemonSelected == 1 then
                love.graphics.setColor(1, 0.9, 0, 1)
                love.graphics.print(">", ww * 0.35, backY)
                love.graphics.setColor(1,1,1,1)
            end
            love.graphics.print("Back", ww * 0.4, backY)
        else
            for i, p in ipairs(M.player.party) do
                local y = startY + (i-1) * lh
                if i == M.pokemonSelected then
                    love.graphics.setColor(1, 0.9, 0, 1)
                    love.graphics.print(">", ww * 0.35, y)
                    love.graphics.setColor(1,1,1,1)
                end
                local name = tostring(p.nickname or p.name or "Unknown")
                local lvl = tostring(p.level or "?")
                local hp = tostring(p.currentHP or 0)
                local max = tostring(p.stats and p.stats.hp or "?")
                local line = string.format("%s  L:%s  HP:%s/%s", name, lvl, hp, max)
                love.graphics.print(line, ww * 0.4, y)
            end
            -- Back option
            local by = startY + count * lh
            if M.pokemonSelected == count + 1 then
                love.graphics.setColor(1, 0.9, 0, 1)
                love.graphics.print(">", ww * 0.35, by)
                love.graphics.setColor(1,1,1,1)
            end
            love.graphics.print("Back", ww * 0.4, by)
        end
    else
        for i, opt in ipairs(M.options) do
            local y = startY + (i-1) * lh
            if i == M.selected then
                love.graphics.setColor(1, 0.9, 0, 1)
                love.graphics.print(">", ww * 0.35, y)
                love.graphics.setColor(1,1,1,1)
            end
            love.graphics.print(opt, ww * 0.4, y)
        end
    end

    love.graphics.pop()
end

return M
