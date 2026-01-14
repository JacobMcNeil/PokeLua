-- player.lua
-- Player object and animation definitions

local Player = {}
Player.__index = Player

-- Animation frame definitions for each direction
Player.ANIM_FRAMES = {
    down  = {1, 2, 3},
    up    = {4, 5, 6},
    left  = {7, 8},
    right = {9, 10}
}

-- Create a new player instance
function Player.new()
    local self = setmetatable({}, Player)
    
    -- Position and movement
    self.tx = 1           -- tile X
    self.ty = 1           -- tile Y
    self.x = 0            -- pixel X
    self.y = 0            -- pixel Y
    self.startX = 0       -- animation start X
    self.startY = 0       -- animation start Y
    self.targetX = 0      -- animation target X
    self.targetY = 0      -- animation target Y
    
    -- Animation and display
    self.size = 16
    self.speed = 40       -- pixels per second
    self.dir = "down"
    self.animIndex = 2    -- current animation frame
    self.stepLeft = true  -- alternating step animation
    self.moveProgress = 0 -- 0-1 progress through current move
    
    -- State
    self.moving = false
    self.jumping = false
    self.currentMap = ""
    
    -- Pokemon party
    self.party = {}
    do
        local ok, pmod = pcall(require, "pokemon")
        if ok and pmod and pmod.Pokemon then
            table.insert(self.party, pmod.Pokemon:new("pikachu", 5))
            table.insert(self.party, pmod.Pokemon:new("squirtle", 5))
        end
    end
    
    return self
end

return Player
