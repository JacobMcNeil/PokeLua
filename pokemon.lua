-- pokemon.lua
-- pokemon.lua
-- Simple Pokemon class (JSON loader removed)

local M = {}

-- Pokemon class
-- Base Pokemon class with simple subclassing support
local Pokemon = {}
Pokemon.__index = Pokemon

function Pokemon.new(tbl)
    tbl = tbl or {}
    local self = setmetatable({}, Pokemon)
    self.name = tbl.name or tbl.n or "Unknown"
    self.level = tbl.level or tbl.l or 1
    local base_hp = tbl.hp or 10
    -- store max HP separately so healing can restore to full
    self.maxHp = tbl.maxHp or base_hp
    -- current HP defaults to provided hp or full
    self.hp = tbl.hp or self.maxHp
    self.attack = tbl.attack or 5
    self.defense = tbl.defense or 5
    self.spAttack = tbl.sp_attack or tbl.sp_atk or tbl.spatk or tbl.special_attack or tbl.sa or 5
    self.spDefense = tbl.sp_defense or tbl.sp_def or tbl.spdef or tbl.special_defense or tbl.sd or 5
    self.speed = tbl.speed or tbl.spd or tbl.s or 10
    self.moves = tbl.moves or tbl.m or {}
    -- Pokédex / National number (accept several common keys)
    self.dex = tbl.dex or tbl.pokedex or tbl.pokedex_number or tbl.number or nil
    return self
end

function Pokemon:__tostring()
    return tostring(self.name)
end

-- Create a subclass (species) that inherits from Pokemon.
-- Usage: local Bulbasaur = Pokemon:extend{ defaults = { name = "Bulbasaur", hp = 45, ... }, customMethod = function(self) ... end }
function Pokemon:extend(spec)
    spec = spec or {}
    local cls = {}
    -- copy non-default keys (methods/constants) onto class
    for k,v in pairs(spec) do
        if k ~= 'defaults' then cls[k] = v end
    end
    cls.defaults = spec.defaults or {}
    cls.__index = cls
    setmetatable(cls, { __index = self })

    function cls.new(tbl)
        tbl = tbl or {}
        tbl = tbl or {}
        -- create instance with class metatable
        local inst = setmetatable({}, cls)
        -- apply class defaults first
        for k,v in pairs(cls.defaults) do inst[k] = v end
        -- then copy base fields (only if not already set by class defaults)
        local base = Pokemon.new(tbl)
        for k,v in pairs(base) do
            if inst[k] == nil then inst[k] = v end
        end
        -- apply explicit constructor table overrides
        for k,v in pairs(tbl) do inst[k] = v end
        return inst
    end

    return cls
end

M.Pokemon = Pokemon

-- Example species (can be required or constructed elsewhere)
local Bulbasaur = Pokemon:extend{
    defaults = {
        name = "Bulbasaur",
        level = 5,
        hp = 45,
        maxHp = 45,
        dex = 1,
        attack = 49,
        defense = 49,
        spAttack = 65,
        spDefense = 65,
        speed = 45,
        moves = { "Tackle", "Growl" },
    }
}
M.Bulbasaur = Bulbasaur
-- More example species
local Charmander = Pokemon:extend{
    defaults = {
        name = "Charmander",
        level = 5,
        hp = 39,
        maxHp = 39,
        dex = 4,
        attack = 52,
        defense = 43,
        spAttack = 60,
        spDefense = 50,
        speed = 65,
        moves = { "Scratch", "Growl" },
    }
}
M.Charmander = Charmander

local Squirtle = Pokemon:extend{
    defaults = {
        name = "Squirtle",
        level = 5,
        hp = 44,
        maxHp = 44,
        dex = 7,
        attack = 48,
        defense = 65,
        spAttack = 50,
        spDefense = 64,
        speed = 43,
        moves = { "Tackle", "Tail Whip" },
    }
}
M.Squirtle = Squirtle

local Pikachu = Pokemon:extend{
    defaults = {
        name = "Pikachu",
        level = 5,
        hp = 35,
        maxHp = 35,
        dex = 25,
        attack = 55,
        defense = 40,
        spAttack = 50,
        spDefense = 50,
        speed = 90,
        moves = { "Thunder Shock", "Growl" },
    }
}
M.Pikachu = Pikachu

local Eevee = Pokemon:extend{
    defaults = {
        name = "Eevee",
        level = 5,
        hp = 55,
        maxHp = 55,
        dex = 133,
        attack = 55,
        defense = 50,
        spAttack = 45,
        spDefense = 65,
        speed = 55,
        moves = { "Tackle", "Tail Whip" },
    }
}
M.Eevee = Eevee

return M

