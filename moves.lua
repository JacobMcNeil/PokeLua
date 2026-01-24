-- moves.lua
-- Unicorn Overlord-style Skills System
-- Skills are either Active (executed during turn) or Passive (triggered by conditions)
--
-- This is a minimal placeholder - skills are currently defined in battle.lua
-- Future versions will move skill definitions here with a proper skill framework

local M = {}

--------------------------------------------------
-- SKILL TYPES
--------------------------------------------------
-- Active Skills: Executed when the unit acts
--   - targetType: "enemy_front", "enemy_all", "ally_front", "ally_lowest_hp", "self"
--   - priority: Higher priority executes first (0 is normal)
--
-- Passive Skills: Triggered by conditions
--   - triggerType: "on_hit", "on_attack", "turn_start", "turn_end", "hp_low"
--   - condition: Function that returns true if passive should trigger

--------------------------------------------------
-- DAMAGE CALCULATION (Pokemon formula)
--------------------------------------------------
-- This uses the standard Pokemon damage formula for compatibility

function M.calculateDamage(attacker, defender, power, isSpecial)
    local level = attacker.level or 5
    local attack, defense
    
    if isSpecial then
        attack = (attacker.stats and attacker.stats.spAttack) or 10
        defense = (defender.stats and defender.stats.spDefense) or 10
    else
        attack = (attacker.stats and attacker.stats.attack) or 10
        defense = (defender.stats and defender.stats.defense) or 10
    end
    
    -- Pokemon damage formula
    -- Damage = ((2*Level/5 + 2) * Power * Atk/Def) / 50 + 2
    local damage = math.floor(((2 * level / 5 + 2) * power * attack / defense) / 50 + 2)
    
    -- Random modifier (85-100%)
    damage = math.floor(damage * (math.random(85, 100) / 100))
    
    -- Minimum 1 damage
    return math.max(1, damage)
end

--------------------------------------------------
-- TYPE EFFECTIVENESS (for future use)
--------------------------------------------------
-- Keep type chart for when we add typed skills

local TypeChart = {
    normal   = { rock = 0.5, ghost = 0, steel = 0.5 },
    fire     = { fire = 0.5, water = 0.5, grass = 2, ice = 2, bug = 2, rock = 0.5, dragon = 0.5, steel = 2 },
    water    = { fire = 2, water = 0.5, grass = 0.5, ground = 2, rock = 2, dragon = 0.5 },
    electric = { water = 2, electric = 0.5, grass = 0.5, ground = 0, flying = 2, dragon = 0.5 },
    grass    = { fire = 0.5, water = 2, grass = 0.5, poison = 0.5, ground = 2, flying = 0.5, bug = 0.5, rock = 2, dragon = 0.5, steel = 0.5 },
    ice      = { fire = 0.5, water = 0.5, grass = 2, ice = 0.5, ground = 2, flying = 2, dragon = 2, steel = 0.5 },
    fighting = { normal = 2, ice = 2, poison = 0.5, flying = 0.5, psychic = 0.5, bug = 0.5, rock = 2, ghost = 0, dark = 2, steel = 2, fairy = 0.5 },
    poison   = { grass = 2, poison = 0.5, ground = 0.5, rock = 0.5, ghost = 0.5, steel = 0, fairy = 2 },
    ground   = { fire = 2, electric = 2, grass = 0.5, poison = 2, flying = 0, bug = 0.5, rock = 2, steel = 2 },
    flying   = { electric = 0.5, grass = 2, fighting = 2, bug = 2, rock = 0.5, steel = 0.5 },
    psychic  = { fighting = 2, poison = 2, psychic = 0.5, dark = 0, steel = 0.5 },
    bug      = { fire = 0.5, grass = 2, fighting = 0.5, poison = 0.5, flying = 0.5, psychic = 2, ghost = 0.5, dark = 2, steel = 0.5, fairy = 0.5 },
    rock     = { fire = 2, ice = 2, fighting = 0.5, ground = 0.5, flying = 2, bug = 2, steel = 0.5 },
    ghost    = { normal = 0, psychic = 2, ghost = 2, dark = 0.5 },
    dragon   = { dragon = 2, steel = 0.5, fairy = 0 },
    dark     = { fighting = 0.5, psychic = 2, ghost = 2, dark = 0.5, fairy = 0.5 },
    steel    = { fire = 0.5, water = 0.5, electric = 0.5, ice = 2, rock = 2, steel = 0.5, fairy = 2 },
    fairy    = { fire = 0.5, fighting = 2, poison = 0.5, dragon = 2, dark = 2, steel = 0.5 },
}

function M.getTypeMultiplier(attackType, defenderTypes)
    if not attackType or not defenderTypes then return 1 end
    
    local chart = TypeChart[string.lower(attackType)]
    if not chart then return 1 end
    
    local multiplier = 1
    if type(defenderTypes) == "string" then
        defenderTypes = {defenderTypes}
    end
    
    for _, defType in ipairs(defenderTypes) do
        local factor = chart[string.lower(defType)]
        if factor then
            multiplier = multiplier * factor
        end
    end
    
    return multiplier
end

M.TypeChart = TypeChart

--------------------------------------------------
-- SKILL REGISTRY (placeholder for future skills)
--------------------------------------------------
-- Skills will be registered here and looked up by ID

M.ActiveSkills = {}
M.PassiveSkills = {}

-- Register a new active skill
function M.registerActiveSkill(id, skill)
    M.ActiveSkills[id] = skill
end

-- Register a new passive skill  
function M.registerPassiveSkill(id, skill)
    M.PassiveSkills[id] = skill
end

-- Get an active skill by ID
function M.getActiveSkill(id)
    return M.ActiveSkills[id]
end

-- Get a passive skill by ID
function M.getPassiveSkill(id)
    return M.PassiveSkills[id]
end

return M
