-- input.lua
-- Input handling for keyboard, mouse, and touch

local M = {}

-------------------------------------------------
-- INPUT STATE
-------------------------------------------------

M.uiInput = {up = false, down = false, left = false, right = false, a = false, b = false, start = false}
M.activeTouches = {}  -- map touch id / "mouse" -> dir
M.uiButtons = {}      -- populated in init() (screen pixels)

-- Control mode: "touchscreen" or "handheld"
M.controlMode = "touchscreen"

-- Game screen dimensions (set by main.lua)
M.gameScreenWidth = 480
M.gameScreenHeight = 432
M.controlPanelHeight = 180  -- Height of the control panel area below game

-- Input blocking for turn-before-move behavior
M.blockDir = nil
M.blockTimer = 0
M.blockDelay = 0.1  -- seconds to wait while holding after a turn

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function pointInRect(px, py, rx, ry, rw, rh)
    return px >= rx and py >= ry and px <= rx + rw and py <= ry + rh
end

local function screenToPixels(x, y)
    local ww, wh = love.graphics.getWidth(), love.graphics.getHeight()
    if x <= 1 and y <= 1 then
        return x * ww, y * wh
    end
    return x, y
end

-------------------------------------------------
-- INITIALIZATION
-------------------------------------------------

function M.init()
    M.uiButtons = {}
    
    -- Calculate the control panel layout (Game Boy Color style)
    -- Controls are positioned below the game screen
    local panelY = M.gameScreenHeight  -- Start of control panel
    local panelH = M.controlPanelHeight
    local ww = M.gameScreenWidth
    
    -- D-pad on the left side
    local dpadCenterX = ww * 0.22
    local dpadCenterY = panelY + panelH * 0.5
    local dpadBtnSize = 42
    local dpadSpacing = dpadBtnSize * 0.85
    
    local function addButton(dir, cx, cy, size)
        size = size or dpadBtnSize
        M.uiButtons[dir] = { x = cx - size/2, y = cy - size/2, w = size, h = size }
    end
    
    -- D-pad buttons
    addButton("up",    dpadCenterX, dpadCenterY - dpadSpacing, dpadBtnSize)
    addButton("down",  dpadCenterX, dpadCenterY + dpadSpacing, dpadBtnSize)
    addButton("left",  dpadCenterX - dpadSpacing, dpadCenterY, dpadBtnSize)
    addButton("right", dpadCenterX + dpadSpacing, dpadCenterY, dpadBtnSize)
    
    -- A and B buttons on the right side (diagonal layout like Game Boy)
    local abCenterX = ww * 0.78
    local abCenterY = panelY + panelH * 0.5
    local abBtnSize = 48
    local abSpacing = 32
    
    -- B button (left, slightly higher) - acts as back
    addButton("b", abCenterX - abSpacing, abCenterY + 8, abBtnSize)
    -- A button (right, slightly lower) - acts as confirm/action
    addButton("a", abCenterX + abSpacing, abCenterY - 8, abBtnSize)
    
    -- Start button in the center-bottom area
    local startW, startH = 60, 24
    M.uiButtons["start"] = { 
        x = ww/2 - startW/2, 
        y = panelY + panelH - 35, 
        w = startW, 
        h = startH 
    }
end

function M.setControlMode(mode)
    if mode == "touchscreen" or mode == "handheld" then
        M.controlMode = mode
    end
end

function M.getControlMode()
    return M.controlMode
end

function M.isHandheldMode()
    return M.controlMode == "handheld"
end

function M.isTouchscreenMode()
    return M.controlMode == "touchscreen"
end

-------------------------------------------------
-- GET CURRENT DIRECTION INPUT
-------------------------------------------------

function M.getDirection()
    local dx, dy = 0, 0
    if love.keyboard.isDown("up")    or M.uiInput.up    then dy = -1 end
    if love.keyboard.isDown("down")  or M.uiInput.down  then dy =  1 end
    if love.keyboard.isDown("left")  or M.uiInput.left  then dx = -1 end
    if love.keyboard.isDown("right") or M.uiInput.right then dx =  1 end
    
    -- Prioritize vertical over horizontal if both pressed
    if dx ~= 0 and dy ~= 0 then dx = 0 end

    if dy < 0 then return "up", dx, dy end
    if dy > 0 then return "down", dx, dy end
    if dx < 0 then return "left", dx, dy end
    if dx > 0 then return "right", dx, dy end
    return nil, 0, 0
end

-------------------------------------------------
-- INPUT BLOCKING FOR TURN-BEFORE-MOVE
-------------------------------------------------

function M.updateBlocking(dt, requestedDir, playerDir, isMoving)
    if not isMoving then
        -- Started pressing a new direction - initiate turn block
        if requestedDir and requestedDir ~= playerDir then
            M.blockDir = requestedDir
            M.blockTimer = 0
        end
        
        -- Released direction - clear block
        if not requestedDir and M.blockDir then
            M.blockDir = nil
            M.blockTimer = 0
        end
        
        -- Still holding same direction - increment timer
        if M.blockDir and requestedDir == M.blockDir then
            M.blockTimer = M.blockTimer + dt
        end
    end
end

function M.shouldBlockMovement(requestedDir)
    return M.blockDir and requestedDir == M.blockDir and M.blockTimer < M.blockDelay
end

function M.clearBlock()
    M.blockDir = nil
    M.blockTimer = 0
end

-------------------------------------------------
-- MOUSE INPUT
-------------------------------------------------

function M.mousepressed(x, y, button, callbacks)
    if button ~= 1 then return end
    if M.controlMode == "handheld" then return end  -- No touch controls in handheld mode
    
    for dir, b in pairs(M.uiButtons) do
        if pointInRect(x, y, b.x, b.y, b.w, b.h) then
            M.uiInput[dir] = true
            M.activeTouches["mouse"] = dir
            if callbacks and callbacks[dir] then
                callbacks[dir]()
            end
        end
    end
end

function M.mousereleased(x, y, button)
    if button ~= 1 then return end
    local dir = M.activeTouches["mouse"]
    if dir then
        M.uiInput[dir] = false
        M.activeTouches["mouse"] = nil
    end
end

-------------------------------------------------
-- TOUCH INPUT
-------------------------------------------------

function M.touchpressed(id, x, y, callbacks)
    if M.controlMode == "handheld" then return end  -- No touch controls in handheld mode
    
    local sx, sy = screenToPixels(x, y)
    for dir, b in pairs(M.uiButtons) do
        if pointInRect(sx, sy, b.x, b.y, b.w, b.h) then
            M.uiInput[dir] = true
            M.activeTouches[id] = dir
            if callbacks and callbacks[dir] then
                callbacks[dir]()
            end
        end
    end
end

function M.touchreleased(id, x, y)
    local dir = M.activeTouches[id]
    if dir then
        M.uiInput[dir] = false
        M.activeTouches[id] = nil
    end
end

-------------------------------------------------
-- DRAW ON-SCREEN BUTTONS (Game Boy Color Style)
-------------------------------------------------

function M.drawButtons()
    -- Don't draw controls in handheld mode
    if M.controlMode == "handheld" then return end
    
    local panelY = M.gameScreenHeight
    local panelH = M.controlPanelHeight
    local ww = M.gameScreenWidth
    
    -- Draw the control panel background (Game Boy Color style - purple/indigo)
    love.graphics.setColor(0.35, 0.25, 0.55, 1)  -- Deep purple
    love.graphics.rectangle("fill", 0, panelY, ww, panelH)
    
    -- Add a slight gradient effect with darker bottom
    love.graphics.setColor(0.25, 0.18, 0.40, 0.5)
    love.graphics.rectangle("fill", 0, panelY + panelH * 0.7, ww, panelH * 0.3)
    
    -- Draw separator line at top of control panel
    love.graphics.setColor(0.2, 0.15, 0.35, 1)
    love.graphics.rectangle("fill", 0, panelY, ww, 3)
    
    -- Draw D-pad base (cross shape background)
    local dpadCenterX = ww * 0.22
    local dpadCenterY = panelY + panelH * 0.5
    local dpadSize = 110
    
    -- D-pad shadow
    love.graphics.setColor(0.15, 0.1, 0.25, 1)
    love.graphics.rectangle("fill", dpadCenterX - dpadSize/6 + 3, dpadCenterY - dpadSize/2 + 3, dpadSize/3, dpadSize, 4, 4)
    love.graphics.rectangle("fill", dpadCenterX - dpadSize/2 + 3, dpadCenterY - dpadSize/6 + 3, dpadSize, dpadSize/3, 4, 4)
    
    -- D-pad main body
    love.graphics.setColor(0.15, 0.15, 0.2, 1)
    love.graphics.rectangle("fill", dpadCenterX - dpadSize/6, dpadCenterY - dpadSize/2, dpadSize/3, dpadSize, 4, 4)
    love.graphics.rectangle("fill", dpadCenterX - dpadSize/2, dpadCenterY - dpadSize/6, dpadSize, dpadSize/3, 4, 4)
    
    -- Draw individual D-pad buttons with press highlighting
    for _, dir in ipairs({"up", "down", "left", "right"}) do
        local b = M.uiButtons[dir]
        if b then
            local cx = b.x + b.w/2
            local cy = b.y + b.h/2
            local pressed = M.uiInput[dir]
            
            -- Highlight when pressed
            if pressed then
                love.graphics.setColor(0.4, 0.4, 0.5, 0.8)
                love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 4, 4)
            end
            
            -- Draw direction arrow
            love.graphics.setColor(0.6, 0.6, 0.7, pressed and 1 or 0.7)
            local s = math.min(b.w, b.h) * 0.25
            if dir == "up" then
                love.graphics.polygon("fill", cx, cy - s, cx - s, cy + s*0.5, cx + s, cy + s*0.5)
            elseif dir == "down" then
                love.graphics.polygon("fill", cx, cy + s, cx - s, cy - s*0.5, cx + s, cy - s*0.5)
            elseif dir == "left" then
                love.graphics.polygon("fill", cx - s, cy, cx + s*0.5, cy - s, cx + s*0.5, cy + s)
            elseif dir == "right" then
                love.graphics.polygon("fill", cx + s, cy, cx - s*0.5, cy - s, cx - s*0.5, cy + s)
            end
        end
    end
    
    -- Draw A and B buttons (circular, Game Boy style)
    local abCenterX = ww * 0.78
    
    -- B Button (red, left)
    local bBtn = M.uiButtons["b"]
    if bBtn then
        local cx = bBtn.x + bBtn.w/2
        local cy = bBtn.y + bBtn.h/2
        local radius = bBtn.w * 0.45
        local pressed = M.uiInput["b"]
        
        -- Button shadow
        love.graphics.setColor(0.3, 0.1, 0.15, 1)
        love.graphics.circle("fill", cx + 2, cy + 2, radius)
        
        -- Button body
        love.graphics.setColor(pressed and 0.7 or 0.85, 0.2, 0.3, 1)
        love.graphics.circle("fill", cx, cy, radius)
        
        -- Button highlight
        love.graphics.setColor(1, 0.4, 0.5, pressed and 0.3 or 0.5)
        love.graphics.arc("fill", cx, cy, radius * 0.8, -math.pi, -math.pi/4)
        
        -- Button label
        love.graphics.setColor(1, 1, 1, 1)
        local font = love.graphics.getFont()
        local text = "B"
        local fw = font and font:getWidth(text) or 8
        local fh = font and font:getHeight() or 12
        love.graphics.print(text, cx - fw/2, cy - fh/2)
    end
    
    -- A Button (red, right)
    local aBtn = M.uiButtons["a"]
    if aBtn then
        local cx = aBtn.x + aBtn.w/2
        local cy = aBtn.y + aBtn.h/2
        local radius = aBtn.w * 0.45
        local pressed = M.uiInput["a"]
        
        -- Button shadow
        love.graphics.setColor(0.3, 0.1, 0.15, 1)
        love.graphics.circle("fill", cx + 2, cy + 2, radius)
        
        -- Button body
        love.graphics.setColor(pressed and 0.7 or 0.85, 0.2, 0.3, 1)
        love.graphics.circle("fill", cx, cy, radius)
        
        -- Button highlight
        love.graphics.setColor(1, 0.4, 0.5, pressed and 0.3 or 0.5)
        love.graphics.arc("fill", cx, cy, radius * 0.8, -math.pi, -math.pi/4)
        
        -- Button label
        love.graphics.setColor(1, 1, 1, 1)
        local font = love.graphics.getFont()
        local text = "A"
        local fw = font and font:getWidth(text) or 8
        local fh = font and font:getHeight() or 12
        love.graphics.print(text, cx - fw/2, cy - fh/2)
    end
    
    -- A/B labels below buttons
    love.graphics.setColor(0.7, 0.6, 0.8, 0.8)
    local font = love.graphics.getFont()
    local fh = font and font:getHeight() or 12
    
    -- Start button (pill shaped)
    local startBtn = M.uiButtons["start"]
    if startBtn then
        local pressed = M.uiInput["start"]
        
        -- Button shadow
        love.graphics.setColor(0.15, 0.1, 0.25, 1)
        love.graphics.rectangle("fill", startBtn.x + 2, startBtn.y + 2, startBtn.w, startBtn.h, 8, 8)
        
        -- Button body
        love.graphics.setColor(pressed and 0.3 or 0.4, pressed and 0.25 or 0.35, pressed and 0.4 or 0.5, 1)
        love.graphics.rectangle("fill", startBtn.x, startBtn.y, startBtn.w, startBtn.h, 8, 8)
        
        -- Button label
        love.graphics.setColor(0.8, 0.8, 0.9, 1)
        local text = "START"
        local fw = font and font:getWidth(text) or 32
        love.graphics.print(text, startBtn.x + startBtn.w/2 - fw/2, startBtn.y + startBtn.h/2 - fh/2)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

return M
