-- animation.lua
-- Character animation definitions and sprite management

local M = {}

-------------------------------------------------
-- ANIMATION FRAME DEFINITIONS
-------------------------------------------------

M.frames = {
    down  = {1, 2, 3},
    up    = {4, 5, 6},
    left  = {7, 8},
    right = {9, 10}
}

-------------------------------------------------
-- SPRITE DATA (populated in load())
-------------------------------------------------

M.charSheet = nil
M.charQuads = {}
M.charWaterQuads = {}
M.shadowQuad = nil

-------------------------------------------------
-- LOAD CHARACTER SPRITES
-------------------------------------------------

function M.load()
    -- character sheet (single row, 1px border + spacing)
    M.charSheet = love.graphics.newImage("tiled/sprites/Characters (Overworld).png")
    local cw, ch = 16, 16
    local margin, spacing = 1, 1
    local imgw, imgh = M.charSheet:getWidth(), M.charSheet:getHeight()

    local count = math.floor((imgw - margin * 2 + spacing) / (cw + spacing))
    for i = 1, count do
        local sx = margin + (i - 1) * (cw + spacing)
        local sy = margin
        M.charQuads[i] = love.graphics.newQuad(sx, sy, cw, ch, imgw, imgh)
    end

    -- shadow is located at row 3, column 5 (1-based)
    do
        local row, col = 3, 5
        local sx = margin + (col - 1) * (cw + spacing)
        local sy = margin + (row - 1) * (ch + spacing)
        M.shadowQuad = love.graphics.newQuad(sx, sy, cw, ch, imgw, imgh)
    end

    -- build water-row quads (fourth row matches ordering of the first row)
    do
        local waterRow = 4
        local waterRowSy = margin + (waterRow - 1) * (ch + spacing)
        for i = 1, count do
            local sx = margin + (i - 1) * (cw + spacing)
            M.charWaterQuads[i] = love.graphics.newQuad(sx, waterRowSy, cw, ch, imgw, imgh)
        end
    end
end

-------------------------------------------------
-- ANIMATION HELPERS
-------------------------------------------------

-- Get the standing (idle) frame index for a direction
function M.getStandingFrame(dir)
    local frames = M.frames[dir]
    if not frames then return 1 end
    return (#frames == 3) and frames[2] or frames[1]
end

-- Get frame index based on movement progress (0-1)
function M.getWalkingFrame(dir, progress, stepLeft)
    local frames = M.frames[dir]
    if not frames then return 1 end
    
    if #frames == 3 then
        -- 3-frame animation (down/up): idle -> left/right step -> idle
        if progress < 0.25 or progress >= 0.75 then
            return frames[2] -- idle
        else
            return stepLeft and frames[1] or frames[3]
        end
    else
        -- 2-frame animation (left/right): alternate between frames
        return (progress < 0.5) and frames[1] or frames[2]
    end
end

-- Get frame index for jumping animation
function M.getJumpingFrame(dir)
    local frames = M.frames[dir]
    if not frames then return 1 end
    
    if dir == "left" or dir == "right" then
        return frames[1]
    elseif dir == "down" and #frames == 3 then
        return frames[2]
    end
    return (#frames == 3) and frames[2] or frames[1]
end

-- Calculate vertical offset for jump arc
function M.getJumpOffset(progress, jumpHeight)
    jumpHeight = jumpHeight or 6
    return -math.sin((progress or 0) * math.pi) * jumpHeight
end

-------------------------------------------------
-- DRAW CHARACTER
-------------------------------------------------

function M.drawCharacter(player, isOnWater)
    if not M.charSheet then return end
    
    local drawX = math.floor(player.x + 0.5)
    local drawY = math.floor(player.y + 0.5)
    
    -- Apply jump offset if jumping
    if player.jumping and player.moveProgress then
        local off = M.getJumpOffset(player.moveProgress)
        drawY = math.floor(player.y + off + 0.5)
    end

    -- Draw shadow under character while jumping
    if M.shadowQuad and player.jumping then
        local shadowCx = math.floor(player.x + player.size * 0.5 + 0.5)
        local shadowCy = math.floor(player.y + player.size - 2 + 0.5)
        local prog = player.moveProgress or 0
        local scale = 1 - 0.25 * math.sin(prog * math.pi)
        local alpha = 0.85 - 0.4 * math.sin(prog * math.pi)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(M.charSheet, M.shadowQuad, shadowCx, shadowCy, 0, scale, scale, player.size * 0.5, player.size * 0.5)
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Select appropriate quad (normal or water version)
    local drawQuad = M.charQuads[player.animIndex] or M.charQuads[1]
    if isOnWater and M.charWaterQuads[player.animIndex] then
        drawQuad = M.charWaterQuads[player.animIndex]
    end
    
    love.graphics.draw(M.charSheet, drawQuad, drawX, drawY)
end

-------------------------------------------------
-- UPDATE PLAYER ANIMATION
-------------------------------------------------

-- Update animation frame based on player state
function M.updateAnimation(player)
    if player.moving then
        if player.jumping then
            player.animIndex = M.getJumpingFrame(player.dir)
        else
            player.animIndex = M.getWalkingFrame(player.dir, player.moveProgress, player.stepLeft)
        end
    else
        player.animIndex = M.getStandingFrame(player.dir)
    end
end

-- Called when player finishes a step - toggle step direction
function M.onStepComplete(player)
    local frames = M.frames[player.dir]
    if frames and #frames == 3 then
        player.stepLeft = not player.stepLeft
    end
end

return M
