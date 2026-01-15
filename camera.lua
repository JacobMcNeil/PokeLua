-- camera.lua
-- Camera management for following the player

local M = {}

-------------------------------------------------
-- CAMERA STATE
-------------------------------------------------

M.x = 0
M.y = 0
M.viewportW = 160  -- camera viewport width in game pixels
M.viewportH = 144  -- camera viewport height in game pixels

-------------------------------------------------
-- CAMERA FUNCTIONS
-------------------------------------------------

-- Initialize camera to follow a position
function M.init(targetX, targetY, mapWidth, mapHeight, tileSize)
    local centerX = targetX
    local centerY = targetY
    local maxCamX = math.max(0, mapWidth * tileSize - M.viewportW)
    local maxCamY = math.max(0, mapHeight * tileSize - M.viewportH)
    M.x = math.floor(math.max(0, math.min(maxCamX, centerX - M.viewportW / 2)) + 0.5)
    M.y = math.floor(math.max(0, math.min(maxCamY, centerY - M.viewportH / 2)) + 0.5)
end

-- Update camera to follow target position
function M.update(targetX, targetY, mapWidth, mapHeight, tileSize)
    local centerX = targetX
    local centerY = targetY
    local maxCamX = math.max(0, mapWidth * tileSize - M.viewportW)
    local maxCamY = math.max(0, mapHeight * tileSize - M.viewportH)
    M.x = math.floor(math.max(0, math.min(maxCamX, centerX - M.viewportW / 2)) + 0.5)
    M.y = math.floor(math.max(0, math.min(maxCamY, centerY - M.viewportH / 2)) + 0.5)
end

-- Apply camera transformation for drawing
function M.attach(scale)
    scale = scale or 1
    love.graphics.push()
    love.graphics.scale(scale, scale)
    love.graphics.translate(-M.x, -M.y)
end

-- Remove camera transformation
function M.detach()
    love.graphics.pop()
end

return M
