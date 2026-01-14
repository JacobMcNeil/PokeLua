-- moves.lua
-- Move base class and example moves

local M = {}
local log = require('log')

-- Type effectiveness chart: attacking_type -> { defending_type -> multiplier }
local TypeChart = {
    normal = { rock = 0.5, steel = 0.5, ghost = 0 },
    fire = { fire = 0.5, water = 0.5, grass = 2, ice = 2, bug = 2, steel = 2, fairy = 1 },
    water = { fire = 2, water = 0.5, grass = 0.5, ground = 2, rock = 2, steel = 1 },
    grass = { fire = 0.5, water = 2, grass = 0.5, poison = 0.5, ground = 2, flying = 0.5, bug = 0.5, rock = 2, steel = 0.5 },
    electric = { water = 2, grass = 0.5, electric = 0.5, flying = 2, ground = 0 },
    ice = { fire = 0.5, water = 0.5, grass = 2, ice = 0.5, dragon = 2, steel = 0.5 },
    fighting = { normal = 2, flying = 0.5, poison = 0.5, rock = 2, bug = 0.5, ghost = 0, steel = 2, psychic = 0.5, fairy = 0.5 },
    poison = { grass = 2, poison = 0.5, ground = 0.5, rock = 0.5, ghost = 0.5, steel = 0, fairy = 2 },
    ground = { fire = 2, grass = 0.5, electric = 2, poison = 2, rock = 2, flying = 0 },
    flying = { normal = 1, fighting = 2, flying = 1, ground = 1, rock = 0.5, bug = 2, grass = 2, electric = 0.5, steel = 0.5 },
    psychic = { fighting = 2, poison = 2, psychic = 0.5, dark = 0, steel = 0.5 },
    bug = { fire = 0.5, grass = 2, fighting = 0.5, poison = 0.5, flying = 0.5, psychic = 2, ghost = 0.5, dark = 2, steel = 0.5, fairy = 0.5 },
    rock = { fire = 2, ice = 2, flying = 2, bug = 2, steel = 0.5, normal = 0.5, poison = 0.5, ground = 0.5 },
    ghost = { normal = 0, flying = 1, poison = 1, bug = 1, rock = 1, ghost = 2, steel = 1, fairy = 1, psychic = 2, dark = 0.5 },
    dragon = { dragon = 2, steel = 0.5, fairy = 0 },
    dark = { fighting = 0.5, dark = 0.5, fairy = 0.5, psychic = 2, ghost = 2 },
    steel = { fire = 0.5, water = 0.5, electric = 0.5, ice = 2, normal = 2, flying = 1, poison = 0, ground = 1, rock = 2, bug = 1, grass = 0.5, psychic = 2, ice = 2, dragon = 1, steel = 0.5, fairy = 2 },
    fairy = { fighting = 2, poison = 0.5, flying = 1, dark = 2, steel = 0.5, dragon = 2 },
}

-- Helper function to calculate type effectiveness
local function getTypeMultiplier(attackType, defenderTypes)
    attackType = string.lower(attackType or "normal")
    if not TypeChart[attackType] then return 1 end
    
    local multiplier = 1
    if type(defenderTypes) == 'string' then
        multiplier = TypeChart[attackType][string.lower(defenderTypes)] or 1
    elseif type(defenderTypes) == 'table' then
        -- For dual types, multiply effectiveness against each type
        for _, defType in ipairs(defenderTypes) do
            local typeMultiplier = TypeChart[attackType][string.lower(defType)] or 1
            multiplier = multiplier * typeMultiplier
        end
    end
    return multiplier
end

local Move = {}
Move.__index = Move

M.getTypeMultiplier = getTypeMultiplier

function Move.new(tbl)
    tbl = tbl or {}
    local self = setmetatable({}, Move)
    self.name = tbl.name or tbl.n or "Unknown Move"
    self.type = tbl.type or tbl.t or "Normal"
    self.category = tbl.category or tbl.cat or "Physical" -- "Physical", "Special", "Status"
    self.power = tbl.power or tbl.p or 0
    self.accuracy = tbl.accuracy or tbl.acc or 100
    local given_pp = tbl.pp
    local given_max = tbl.maxPP
    self.maxPP = given_max or given_pp or 10
    self.pp = given_pp or self.maxPP
    self.priority = tbl.priority or 0
    self.effect = tbl.effect -- optional function(user, target, battle)
    return self
end

function Move:__tostring()
    return tostring(self.name)
end

-- Use a move: consumes PP, checks accuracy, applies simple damage formula, runs effect
function Move:use(user, target, battle)
    if self.pp and self.pp > 0 then self.pp = self.pp - 1 end

    local hitRoll = math.random(1,100)
    if self.accuracy < 100 and hitRoll > self.accuracy then
        return { hit = false, message = (user and (user.nickname or user.name) or tostring(user)) .. "'s " .. self.name .. " missed!" }
    end

    if self.power and self.power > 0 then
        log.log("moves.Move:use: calculating damage")
        local Level = (user and user.level) or 50
        local Power = self.power
        local category = self.category or self.cat or "Physical"

        -- Choose attack/defense stats based on category
        local A, D
        if category == "Physical" then
            A = (user and (user.stats and user.stats.attack or user.attack or user.atk)) or 5
            D = (target and (target.stats and target.stats.defense or target.defense or target.def)) or 5
        else
            A = (user and (user.stats and user.stats.spAttack or user.spAttack or user.spAtk or user.spatk)) or 5
            D = (target and (target.stats and target.stats.spDefense or target.spDefense or target.spDef or target.spdef)) or 5
        end
        D = math.max(1, D)

        -- Optional modifiers (default to 1)
        local Targets = self.targets or 1
        local PB = self.pb or 1
        local Weather = (battle and battle.weather) or 1
        local GlaiveRush = self.glaiveRush or 1
        local Critical = self.critical or 1
        local rand = math.random(85, 100) / 100
        
        -- Calculate STAB (Same Type Attack Bonus)
        local STAB = 1
        if user then
            local userTypes = user.types or user.type or (user.species and user.species.types)
            if type(userTypes) == 'string' then
                if string.lower(userTypes) == string.lower(self.type or "") then STAB = 1.5 end
            elseif type(userTypes) == 'table' then
                for _, t in ipairs(userTypes) do
                    if string.lower(t) == string.lower(self.type or "") then STAB = 1.5; break end
                end
            end
        end

        -- Calculate type effectiveness (support Pokemon instances that store types under .species)
        local targetTypes = target and (target.types or target.type or (target.species and target.species.types)) or "normal"
        log.log("  target object: ", target)
        log.log("  target.name: ", target and (target.nickname or target.name or target.speciesId) or "nil")
        log.log("  target.type: ", target and target.type or "nil")
        log.log("  target.types: ", target and target.types or (target and target.species and target.species.types) or "nil")
        log.log("  calling getTypeMultiplier: attackType=", self.type, " targetTypes=", targetTypes)
        local Type = getTypeMultiplier(self.type, targetTypes)
        log.log("  getTypeMultiplier returned: ", Type)
        
        local Burn = 1
        if user and user.status == 'burned' and category == "Physical" then Burn = 0.5 end
        local other = self.other or 1
        local ZMove = self.zmove or 1
        local TeraShield = self.teraShield or 1

        local base = math.floor(((((2 * Level) / 5) + 2) * Power * A / D) / 50) + 2
        local modifier = Targets * PB * Weather * GlaiveRush * Critical * rand * STAB * Type * Burn * other * ZMove * TeraShield
        local damage = math.max(1, math.floor(base * modifier))
        target.currentHP = math.max(0, (target.currentHP or 0) - damage)
        if self.effect then self.effect(user, target, battle) end
        local uname = (user and (user.nickname or user.name)) or tostring(user)
        
        -- Add type effectiveness to message
        local effectText = ""
        if Type >= 2 then
            effectText = " It was super effective!"
        elseif Type > 1 and Type < 2 then
            effectText = " It was super effective!"
        elseif Type <= 0.5 and Type > 0 then
            effectText = " It's not very effective..."
        elseif Type == 0 then
            effectText = " It had no effect!"
        end
        
        local msg = string.format("%s's %s dealt %d damage!%s", uname, self.name, damage, effectText)
        return { hit = true, damage = damage, message = msg }
    else
        if self.effect then self.effect(user, target, battle) end
        local uname2 = (user and (user.nickname or user.name)) or tostring(user)
        local msg = uname2 .. " used " .. self.name .. "!"
        return { hit = true, damage = 0, message = msg }
    end
end

-- Subclassing support (like Pokemon:extend)
function Move:extend(spec)
    spec = spec or {}
    local cls = {}
    for k,v in pairs(spec) do
        if k ~= 'defaults' then cls[k] = v end
    end
    cls.defaults = spec.defaults or {}
    cls.__index = cls
    setmetatable(cls, { __index = Move })

    function cls.new(tbl)
        tbl = tbl or {}
        local inst = setmetatable({}, cls)
        for k,v in pairs(cls.defaults) do inst[k] = v end
        -- If defaults provided a maxPP, ensure pp follows it before merging base
        inst.maxPP = inst.maxPP or inst.pp
        inst.pp = inst.pp or inst.maxPP
        local base = Move.new(tbl)
        for k,v in pairs(base) do
            if inst[k] == nil then inst[k] = v end
        end
        for k,v in pairs(tbl) do inst[k] = v end
        -- Final ensure: maxPP exists and pp follows it
        inst.maxPP = inst.maxPP or inst.pp
        inst.pp = inst.pp or inst.maxPP
        return inst
    end

    return cls
end

M.Move = Move
M.TypeChart = TypeChart
M.getTypeMultiplier = getTypeMultiplier

-- Example moves
local Tackle = Move:extend{
    defaults = {
        name = "Tackle",
        type = "Normal",
        category = "Physical",
        power = 40,
        accuracy = 100,
        maxPP = 35,
    }
}
M.Tackle = Tackle

local Growl = Move:extend{
    defaults = {
        name = "Growl",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 100,
        maxPP = 40,
        effect = function(user, target, battle)
            if target.stats then
                target.stats.attack = math.max(1, (target.stats.attack or 5) - 1)
            end
        end,
    }
}
M.Growl = Growl

local ThunderShock = Move:extend{
    defaults = {
        name = "Thunder Shock",
        type = "Electric",
        category = "Special",
        power = 40,
        accuracy = 100,
        maxPP = 30,
        effect = function(user, target, battle)
            if math.random() < 0.1 then target.status = "paralyzed" end
        end,
    }
}
M.ThunderShock = ThunderShock

local TailWhip = Move:extend{
    defaults = {
        name = "Tail Whip",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 100,
        maxPP = 30,
        effect = function(user, target, battle)
            if target.stats then
                target.stats.defense = math.max(1, (target.stats.defense or 5) - 1)
            end
        end,
    }
}
M.TailWhip = TailWhip

local Scratch = Move:extend{
    defaults = {
        name = "Scratch",
        type = "Normal",
        category = "Physical",
        power = 40,
        accuracy = 100,
        maxPP = 35,
    }
}
M.Scratch = Scratch

local QuickAttack = Move:extend{
    defaults = {
        name = "Quick Attack",
        type = "Normal",
        category = "Physical",
        power = 40,
        accuracy = 100,
        maxPP = 30,
        priority = 1,
    }
}
M.QuickAttack = QuickAttack

local VineWhip = Move:extend{
    defaults = {
        name = "Vine Whip",
        type = "Grass",
        category = "Physical",
        power = 45,
        accuracy = 100,
        maxPP = 25,
    }
}
M.VineWhip = VineWhip

local WaterGun = Move:extend{
    defaults = {
        name = "Water Gun",
        type = "Water",
        category = "Special",
        power = 40,
        accuracy = 100,
        maxPP = 25,
    }
}
M.WaterGun = WaterGun

local Ember = Move:extend{
    defaults = {
        name = "Ember",
        type = "Fire",
        category = "Special",
        power = 40,
        accuracy = 100,
        maxPP = 25,
        effect = function(user, target, battle)
            if math.random() < 0.1 then target.status = "burned" end
        end,
    }
}
M.Ember = Ember

-- Create aliases for efficient move lookup (lowercase and underscore variants)
local function createAliases(name, moveClass)
    M[name] = moveClass
    M[string.lower(name)] = moveClass
    local underscored = name:gsub("%u", function(c) return "_" .. string.lower(c) end):sub(2)
    if underscored ~= string.lower(name) then
        M[underscored] = moveClass
    end
end

createAliases("Tackle", Tackle)
createAliases("Growl", Growl)
createAliases("ThunderShock", ThunderShock)
createAliases("TailWhip", TailWhip)
createAliases("Scratch", Scratch)
createAliases("QuickAttack", QuickAttack)
createAliases("VineWhip", VineWhip)
createAliases("WaterGun", WaterGun)
createAliases("Ember", Ember)

return M
