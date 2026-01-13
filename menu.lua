-- menu.lua
local M = {}

M.open = false
M.options = {"Pokemon", "Bag", "Heal", "Save", "Exit"}
M.selected = 1
M.showPokemon = false
M.pokemonSelected = 1

-- Simple JSON encoder for saving tables (skips functions/threads/userdata and avoids cycles)
local function escape_str(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('\"', '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    s = s:gsub('\t', '\\t')
    return s
end

local function is_array(t)
    if type(t) ~= "table" then return false end
    local n = 0
    local max = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" then return false end
        if k > max then max = k end
        n = n + 1
    end
    return max == n
end

local function encode_json(val, visited)
    visited = visited or {}
    local t = type(val)
    if t == "nil" then return "null" end
    if t == "number" then return tostring(val) end
    if t == "boolean" then return val and "true" or "false" end
    if t == "string" then return '"' .. escape_str(val) .. '"' end
    if t == "table" then
        if visited[val] then return "null" end
        visited[val] = true
        if is_array(val) then
            local parts = {}
            for i = 1, #val do parts[#parts+1] = encode_json(val[i], visited) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                local kt = type(k)
                local keystr = (kt == "string") and ('"' .. escape_str(k) .. '"') or ('"' .. tostring(k) .. '"')
                local vt = type(v)
                if vt ~= "function" and vt ~= "thread" and vt ~= "userdata" then
                    parts[#parts+1] = keystr .. ":" .. encode_json(v, visited)
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

function M.toggle()
    if M.open then
        M.open = false
        M.showPokemon = false
    else
        M.open = true
        M.showPokemon = false
        M.selected = 1
        M.pokemonSelected = 1
    end
end

function M.openMenu()
    M.open = true
    M.showPokemon = false
    M.selected = 1
    M.pokemonSelected = 1
end

function M.close()
    M.open = false
    M.showPokemon = false
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
                -- future: show details for selected Pokemon
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
                    if p and p.maxHp then p.hp = p.maxHp end
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
                local name = tostring(p.name or "Unknown")
                local lvl = tostring(p.level or "?")
                local hp = tostring(p.hp or 0)
                local max = tostring(p.maxHp or p.hp or "?")
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
