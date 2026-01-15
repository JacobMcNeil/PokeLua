-- ui.lua
-- Shared UI drawing utilities for Pokemon-style menus
local UI = {}

-- Color palette (Pokemon-style)
UI.colors = {
    -- Menu box colors
    borderDark = {0.15, 0.15, 0.2, 1},
    borderLight = {0.4, 0.4, 0.5, 1},
    bgWhite = {1, 1, 1, 1},
    bgLight = {0.95, 0.95, 0.97, 1},
    
    -- Text colors (for white backgrounds)
    textDark = {0.1, 0.1, 0.15, 1},
    textGray = {0.4, 0.4, 0.45, 1},
    textSelected = {0.85, 0.2, 0.2, 1},  -- Red for selected
    textHighlight = {0.9, 0.6, 0.1, 1},  -- Orange/gold highlight
    
    -- HP bar colors
    hpGreen = {0.2, 0.8, 0.3, 1},
    hpYellow = {0.9, 0.8, 0.2, 1},
    hpRed = {0.9, 0.2, 0.2, 1},
    hpBg = {0.3, 0.3, 0.3, 1},
    
    -- Overlay
    overlayDark = {0, 0, 0, 0.5},
    
    -- Battle specific
    battleBg = {0.85, 0.9, 0.85, 1},  -- Light green tint for battle
}

-- Get the game screen dimensions (excluding touchscreen control panel)
-- This should be used instead of love.graphics.getWidth/getHeight for UI positioning
function UI.getGameScreenDimensions()
    local ok, input = pcall(require, "input")
    if ok and input then
        return input.gameScreenWidth, input.gameScreenHeight
    end
    -- Fallback to window size if input module not available
    return love.graphics.getWidth(), love.graphics.getHeight()
end

-- Draw a Pokemon-style menu box with rounded corners and border
function UI.drawBox(x, y, w, h, borderWidth)
    borderWidth = borderWidth or 3
    local radius = 8
    
    -- Outer dark border
    love.graphics.setColor(unpack(UI.colors.borderDark))
    love.graphics.rectangle("fill", x, y, w, h, radius, radius)
    
    -- Inner white background
    love.graphics.setColor(unpack(UI.colors.bgWhite))
    love.graphics.rectangle("fill", x + borderWidth, y + borderWidth, 
                           w - borderWidth * 2, h - borderWidth * 2, 
                           radius - 1, radius - 1)
end

-- Draw a box with a shadow effect
function UI.drawBoxWithShadow(x, y, w, h, borderWidth)
    borderWidth = borderWidth or 3
    local shadowOffset = 4
    
    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle("fill", x + shadowOffset, y + shadowOffset, w, h, 8, 8)
    
    -- Main box
    UI.drawBox(x, y, w, h, borderWidth)
end

-- Draw text with menu styling
function UI.drawText(text, x, y, selected, width, align)
    if selected then
        love.graphics.setColor(unpack(UI.colors.textSelected))
    else
        love.graphics.setColor(unpack(UI.colors.textDark))
    end
    
    if width and align then
        love.graphics.printf(text, x, y, width, align)
    else
        love.graphics.print(text, x, y)
    end
end

-- Draw a menu option with cursor
function UI.drawOption(text, x, y, selected, cursorOffset)
    cursorOffset = cursorOffset or 15
    if selected then
        love.graphics.setColor(unpack(UI.colors.textSelected))
        love.graphics.print(">", x - cursorOffset, y)
    else
        love.graphics.setColor(unpack(UI.colors.textDark))
    end
    love.graphics.print(text, x, y)
end

-- Draw a title bar at the top of a menu box
function UI.drawTitle(text, boxX, boxY, boxW)
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.printf(text, boxX, boxY + 12, boxW, "center")
end

-- Draw an HP bar
function UI.drawHPBar(currentHP, maxHP, x, y, w, h)
    local ratio = maxHP > 0 and (currentHP / maxHP) or 0
    ratio = math.max(0, math.min(1, ratio))
    
    -- "HP" label
    love.graphics.setColor(unpack(UI.colors.textGray))
    love.graphics.print("HP", x, y - 2)
    local labelW = 25
    
    -- Background bar
    love.graphics.setColor(unpack(UI.colors.hpBg))
    love.graphics.rectangle("fill", x + labelW, y, w - labelW, h, 3, 3)
    
    -- HP fill color based on percentage
    if ratio > 0.5 then
        love.graphics.setColor(unpack(UI.colors.hpGreen))
    elseif ratio > 0.2 then
        love.graphics.setColor(unpack(UI.colors.hpYellow))
    else
        love.graphics.setColor(unpack(UI.colors.hpRed))
    end
    
    -- HP fill
    local barInner = w - labelW - 4
    if ratio > 0 then
        love.graphics.rectangle("fill", x + labelW + 2, y + 2, barInner * ratio, h - 4, 2, 2)
    end
end

-- Draw an EXP bar
function UI.drawEXPBar(currentExp, expForThisLevel, expForNextLevel, x, y, w, h)
    local expIntoLevel = currentExp - expForThisLevel
    local expNeeded = expForNextLevel - expForThisLevel
    local ratio = expNeeded > 0 and (expIntoLevel / expNeeded) or 1
    ratio = math.max(0, math.min(1, ratio))
    
    -- "EXP" label
    love.graphics.setColor(unpack(UI.colors.textGray))
    love.graphics.print("EXP", x, y - 2)
    local labelW = 30
    
    -- Background bar
    love.graphics.setColor(0.2, 0.2, 0.25, 1)
    love.graphics.rectangle("fill", x + labelW, y, w - labelW, h, 3, 3)
    
    -- EXP fill (blue color)
    love.graphics.setColor(0.3, 0.5, 0.9, 1)
    local barInner = w - labelW - 4
    if ratio > 0 then
        love.graphics.rectangle("fill", x + labelW + 2, y + 2, barInner * ratio, h - 4, 2, 2)
    end
end

-- Draw screen overlay
function UI.drawOverlay(alpha)
    alpha = alpha or 0.5
    local ww, hh = UI.getGameScreenDimensions()
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.rectangle("fill", 0, 0, ww, hh)
end

-- Draw a message dialog box
function UI.drawMessageBox(message, x, y, w, h, prompt)
    UI.drawBoxWithShadow(x, y, w, h)
    
    local font = love.graphics.getFont()
    local lh = font and font:getHeight() or 12
    
    -- Message text
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.printf(message, x + 15, y + h/2 - lh/2, w - 30, "center")
    
    -- Prompt if provided
    if prompt then
        love.graphics.setColor(unpack(UI.colors.textGray))
        love.graphics.printf(prompt, x + 15, y + h - lh - 10, w - 30, "center")
    end
end

-- Draw a small action menu (like Use/Give/Toss)
function UI.drawActionMenu(options, selected, x, y, w, h)
    UI.drawBoxWithShadow(x, y, w, h)
    
    local font = love.graphics.getFont()
    local lh = (font and font:getHeight() or 12) + 6
    local startY = y + 10
    local textX = x + 20
    
    for i, opt in ipairs(options) do
        local optY = startY + (i - 1) * lh
        UI.drawOption(opt, textX, optY, i == selected)
    end
end

-- Draw Pokemon info panel (name, level, HP bar)
function UI.drawPokemonPanel(pokemon, x, y, w, h, isPlayer)
    UI.drawBox(x, y, w, h)
    
    if not pokemon then return end
    
    local font = love.graphics.getFont()
    local lh = font and font:getHeight() or 12
    local padding = 10
    local innerX = x + padding
    local innerW = w - padding * 2
    
    -- Name and level
    local name = pokemon.nickname or pokemon.name or "???"
    local level = "Lv" .. tostring(pokemon.level or "?")
    
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.print(name, innerX, y + padding)
    love.graphics.printf(level, x, y + padding, w - padding, "right")
    
    -- HP bar
    local hpBarY = y + padding + lh + 5
    local hpBarH = 8
    local currentHP = pokemon.currentHP or 0
    local maxHP = (pokemon.stats and pokemon.stats.hp) or pokemon.maxHp or 1
    
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.print("HP", innerX, hpBarY - 2)
    UI.drawHPBar(innerX + 25, hpBarY, innerW - 25, hpBarH, currentHP, maxHP)
    
    -- HP numbers (only for player's Pokemon typically)
    if isPlayer then
        local hpText = string.format("%d/%d", currentHP, maxHP)
        love.graphics.setColor(unpack(UI.colors.textDark))
        love.graphics.printf(hpText, x, hpBarY + hpBarH + 3, w - padding, "right")
    end
end

-- Reset color to white (for sprites, etc.)
function UI.resetColor()
    love.graphics.setColor(1, 1, 1, 1)
end

-- Status condition colors and abbreviations
UI.statusColors = {
    paralyzed = {0.95, 0.85, 0.2, 1},      -- Yellow
    burned = {0.95, 0.4, 0.2, 1},          -- Orange/Red
    poisoned = {0.7, 0.3, 0.7, 1},         -- Purple
    badly_poisoned = {0.6, 0.2, 0.6, 1},   -- Dark Purple
    asleep = {0.5, 0.5, 0.55, 1},          -- Gray
    frozen = {0.4, 0.8, 0.95, 1},          -- Light Blue
}

UI.statusAbbrev = {
    paralyzed = "PAR",
    burned = "BRN",
    poisoned = "PSN",
    badly_poisoned = "PSN",
    asleep = "SLP",
    frozen = "FRZ",
}

-- Draw a status condition badge
function UI.drawStatusBadge(status, x, y, scale)
    if not status then return end
    scale = scale or 1
    
    local abbrev = UI.statusAbbrev[status]
    local color = UI.statusColors[status]
    
    if not abbrev or not color then return end
    
    local font = love.graphics.getFont()
    local textW = font:getWidth(abbrev)
    local textH = font:getHeight()
    local padX = 4 * scale
    local padY = 2 * scale
    local badgeW = textW + padX * 2
    local badgeH = textH + padY * 2
    
    -- Badge background
    love.graphics.setColor(unpack(color))
    love.graphics.rectangle("fill", x, y, badgeW, badgeH, 3 * scale, 3 * scale)
    
    -- Dark border
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("line", x, y, badgeW, badgeH, 3 * scale, 3 * scale)
    
    -- Text
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(abbrev, x + padX, y + padY)
    
    return badgeW  -- Return width so caller knows how much space was used
end

-- Get status display string for Pokemon list (compact version)
function UI.getStatusString(pokemon)
    if not pokemon or not pokemon.status then return nil end
    return UI.statusAbbrev[pokemon.status]
end

return UI
