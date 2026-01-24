---@diagnostic disable
-- skills.lua
-- Pokemon-style skills and passives for the battle system

local M = {}

--------------------------------------------------
-- SKILL TABLES
--------------------------------------------------
local Skills = {}
local Passives = {}

--------------------------------------------------
-- STAT STAGE SYSTEM (Pokemon Standard)
--------------------------------------------------
local StatStageMultipliers = {
    [1] = 2/8,   -- -6: 25%
    [2] = 2/7,   -- -5: ~29%
    [3] = 2/6,   -- -4: ~33%
    [4] = 2/5,   -- -3: 40%
    [5] = 2/4,   -- -2: 50%
    [6] = 2/3,   -- -1: ~67%
    [7] = 2/2,   --  0: 100% (neutral)
    [8] = 3/2,   -- +1: 150%
    [9] = 4/2,   -- +2: 200%
    [10] = 5/2,  -- +3: 250%
    [11] = 6/2,  -- +4: 300%
    [12] = 7/2,  -- +5: 350%
    [13] = 8/2,  -- +6: 400%
}

local function stageToIndex(stage)
    return math.max(1, math.min(13, stage + 7))
end

local function getStatMultiplier(stage)
    return StatStageMultipliers[stageToIndex(stage)] or 1
end

-- Initialize stat stages for a Pokemon
function M.initStatStages(pokemon)
    if not pokemon then return end
    pokemon.statStages = {
        attack = 0,
        defense = 0,
        special_attack = 0,
        special_defense = 0,
        speed = 0,
        accuracy = 0,
        evasion = 0,
    }
end

-- Modify a stat stage, returns actual change and message
function M.modifyStatStage(pokemon, stat, stages)
    if not pokemon then return 0, "" end
    if not pokemon.statStages then
        M.initStatStages(pokemon)
    end
    
    local currentStage = pokemon.statStages[stat] or 0
    local newStage = math.max(-6, math.min(6, currentStage + stages))
    local actualChange = newStage - currentStage
    
    pokemon.statStages[stat] = newStage
    
    local pokeName = pokemon.nickname or pokemon.name or "Pokemon"
    local statNames = {
        attack = "Attack", defense = "Defense",
        special_attack = "Sp. Atk", special_defense = "Sp. Def",
        speed = "Speed", accuracy = "Accuracy", evasion = "Evasion"
    }
    local statName = statNames[stat] or stat
    
    local message = ""
    if actualChange == 0 then
        if stages > 0 then
            message = pokeName .. "'s " .. statName .. " won't go any higher!"
        else
            message = pokeName .. "'s " .. statName .. " won't go any lower!"
        end
    elseif actualChange >= 3 then
        message = pokeName .. "'s " .. statName .. " rose drastically!"
    elseif actualChange == 2 then
        message = pokeName .. "'s " .. statName .. " rose sharply!"
    elseif actualChange == 1 then
        message = pokeName .. "'s " .. statName .. " rose!"
    elseif actualChange == -1 then
        message = pokeName .. "'s " .. statName .. " fell!"
    elseif actualChange == -2 then
        message = pokeName .. "'s " .. statName .. " harshly fell!"
    elseif actualChange <= -3 then
        message = pokeName .. "'s " .. statName .. " severely fell!"
    end
    
    return actualChange, message
end

-- Get effective stat value considering base stat and stage
function M.getEffectiveStat(pokemon, stat)
    if not pokemon then return 1 end
    
    local baseStat = 1
    if pokemon.stats and pokemon.stats[stat] then
        baseStat = pokemon.stats[stat]
    elseif pokemon[stat] then
        baseStat = pokemon[stat]
    end
    
    local stage = 0
    if pokemon.statStages and pokemon.statStages[stat] then
        stage = pokemon.statStages[stat]
    end
    
    return math.floor(baseStat * getStatMultiplier(stage))
end

--------------------------------------------------
-- TYPE EFFECTIVENESS CHART
--------------------------------------------------
local TypeChart = {
    normal = { rock = 0.5, steel = 0.5, ghost = 0 },
    fire = { fire = 0.5, water = 0.5, grass = 2, ice = 2, bug = 2, steel = 2, rock = 0.5, dragon = 0.5 },
    water = { fire = 2, water = 0.5, grass = 0.5, ground = 2, rock = 2, dragon = 0.5 },
    grass = { fire = 0.5, water = 2, grass = 0.5, poison = 0.5, ground = 2, flying = 0.5, bug = 0.5, rock = 2, dragon = 0.5, steel = 0.5 },
    electric = { water = 2, grass = 0.5, electric = 0.5, flying = 2, ground = 0, dragon = 0.5 },
    ice = { fire = 0.5, water = 0.5, grass = 2, ice = 0.5, ground = 2, flying = 2, dragon = 2, steel = 0.5 },
    fighting = { normal = 2, ice = 2, rock = 2, dark = 2, steel = 2, flying = 0.5, poison = 0.5, bug = 0.5, psychic = 0.5, ghost = 0, fairy = 0.5 },
    poison = { grass = 2, poison = 0.5, ground = 0.5, rock = 0.5, ghost = 0.5, steel = 0, fairy = 2 },
    ground = { fire = 2, electric = 2, grass = 0.5, poison = 2, rock = 2, bug = 0.5, steel = 2, flying = 0 },
    flying = { grass = 2, fighting = 2, bug = 2, rock = 0.5, steel = 0.5, electric = 0.5 },
    psychic = { fighting = 2, poison = 2, psychic = 0.5, dark = 0, steel = 0.5 },
    bug = { grass = 2, psychic = 2, dark = 2, fire = 0.5, fighting = 0.5, poison = 0.5, flying = 0.5, ghost = 0.5, steel = 0.5, fairy = 0.5 },
    rock = { fire = 2, ice = 2, flying = 2, bug = 2, fighting = 0.5, ground = 0.5, steel = 0.5 },
    ghost = { psychic = 2, ghost = 2, normal = 0, dark = 0.5 },
    dragon = { dragon = 2, steel = 0.5, fairy = 0 },
    dark = { psychic = 2, ghost = 2, fighting = 0.5, dark = 0.5, fairy = 0.5 },
    steel = { ice = 2, rock = 2, fairy = 2, fire = 0.5, water = 0.5, electric = 0.5, steel = 0.5 },
    fairy = { fighting = 2, dragon = 2, dark = 2, fire = 0.5, poison = 0.5, steel = 0.5 },
}

function M.getTypeMultiplier(attackType, defenderTypes)
    attackType = string.lower(attackType or "normal")
    if not TypeChart[attackType] then return 1 end
    
    local multiplier = 1
    if type(defenderTypes) == 'string' then
        multiplier = TypeChart[attackType][string.lower(defenderTypes)] or 1
    elseif type(defenderTypes) == 'table' then
        for _, defType in ipairs(defenderTypes) do
            local m = TypeChart[attackType][string.lower(defType)]
            if m then multiplier = multiplier * m end
        end
    end
    return multiplier
end

-- Check if user has STAB
local function hasSTAB(user, moveType)
    moveType = string.lower(moveType or "normal")
    local userTypes = {}
    
    if user.species and user.species.types then
        userTypes = user.species.types
    elseif user.types then
        userTypes = user.types
    end
    
    for _, t in ipairs(userTypes) do
        if string.lower(t) == moveType then
            return true
        end
    end
    return false
end

-- Get defender types
local function getDefenderTypes(target)
    if target.species and target.species.types then
        return target.species.types
    elseif target.types then
        return target.types
    end
    return {"normal"}
end

M.getDefenderTypes = getDefenderTypes

--------------------------------------------------
-- DAMAGE HELPERS
--------------------------------------------------

function M.calculateDamage(user, target, basePower, useSpecial, moveType)
    local level = user.level or 5
    local attack, defense
    
    if useSpecial then
        attack = M.getEffectiveStat(user, "special_attack")
        defense = M.getEffectiveStat(target, "special_defense")
        if attack < 1 then attack = (user.stats and user.stats.special_attack) or 10 end
        if defense < 1 then defense = (target.stats and target.stats.special_defense) or 10 end
    else
        attack = M.getEffectiveStat(user, "attack")
        defense = M.getEffectiveStat(target, "defense")
        if attack < 1 then attack = (user.stats and user.stats.attack) or 10 end
        if defense < 1 then defense = (target.stats and target.stats.defense) or 10 end
    end
    
    -- Base damage formula
    local damage = math.floor(((2 * level / 5 + 2) * basePower * attack / defense) / 50 + 2)
    
    -- Random factor (85-100%)
    damage = math.floor(damage * (math.random(85, 100) / 100))
    
    -- STAB (1.5x)
    if moveType and hasSTAB(user, moveType) then
        damage = math.floor(damage * 1.5)
    end
    
    -- Type effectiveness
    if moveType then
        local defenderTypes = getDefenderTypes(target)
        local typeMultiplier = M.getTypeMultiplier(moveType, defenderTypes)
        damage = math.floor(damage * typeMultiplier)
    end
    
    return math.max(1, damage)
end

function M.applyDamage(target, damage, battle)
    local wasAlive = target.currentHP > 0
    target.currentHP = math.max(0, target.currentHP - damage)
    if target.currentHP <= 0 then
        -- Track defeated enemy for EXP distribution
        if wasAlive and battle and battle.trackDefeatedEnemy then
            -- Check if target is an enemy (not a player Pokemon)
            local isEnemy = battle.getFormationSide and battle.getFormationSide(target) == "enemy"
            if isEnemy then
                battle.trackDefeatedEnemy(target)
            end
        end
        return "\n" .. target.name .. " fainted!"
    end
    return ""
end

function M.applyHeal(target, amount)
    local maxHP = (target.stats and target.stats.hp) or 100
    local oldHP = target.currentHP
    target.currentHP = math.min(maxHP, target.currentHP + amount)
    return target.currentHP - oldHP
end

-- Helper: Generate type effectiveness message
local function getTypeEffectivenessMessage(moveType, target)
    if not moveType then return "" end
    local defenderTypes = getDefenderTypes(target)
    local mult = M.getTypeMultiplier(moveType, defenderTypes)
    if mult >= 2 then
        return " It's super effective!"
    elseif mult > 0 and mult < 1 then
        return " It's not very effective..."
    elseif mult == 0 then
        return " It doesn't affect " .. target.name .. "..."
    end
    return ""
end

--------------------------------------------------
-- ACTIVE SKILLS
--------------------------------------------------

Skills.Tackle = {
    name = "Tackle",
    description = "A basic tackle attack. (Power: 40)",
    skillType = "active",
    targetType = "enemy",
    moveType = "normal",
    category = "physical",
    priority = 0,
    basePower = 40,
    accuracy = 100,
    ranged = false,
    execute = function(self, user, target, battle)
        if not target or target.currentHP <= 0 then
            return nil, user.name .. " has no target!"
        end
        
        local damage = M.calculateDamage(user, target, self.basePower, false, self.moveType)
        local message = user.name .. " used Tackle!"
        message = message .. getTypeEffectivenessMessage(self.moveType, target)
        message = message .. M.applyDamage(target, damage, battle)
        
        return damage, message
    end
}

Skills.Ember = {
    name = "Ember",
    description = "A Fire-type attack. May cause burn. (Power: 40)",
    skillType = "active",
    targetType = "enemy",
    moveType = "fire",
    category = "special",
    priority = 0,
    basePower = 40,
    accuracy = 100,
    ranged = true,
    execute = function(self, user, target, battle)
        if not target or target.currentHP <= 0 then
            return nil, user.name .. " has no target!"
        end
        
        local damage = M.calculateDamage(user, target, self.basePower, true, self.moveType)
        local message = user.name .. " used Ember!"
        message = message .. getTypeEffectivenessMessage(self.moveType, target)
        message = message .. M.applyDamage(target, damage, battle)
        
        -- 10% burn chance
        if target.currentHP > 0 and math.random() < 0.1 then
            M.modifyStatStage(target, "attack", -1)
            message = message .. "\n" .. target.name .. " was burned!"
        end
        
        return damage, message
    end
}

Skills.WaterGun = {
    name = "Water Gun",
    description = "A Water-type attack. (Power: 40)",
    skillType = "active",
    targetType = "enemy",
    moveType = "water",
    category = "special",
    priority = 0,
    basePower = 40,
    accuracy = 100,
    ranged = true,
    execute = function(self, user, target, battle)
        if not target or target.currentHP <= 0 then
            return nil, user.name .. " has no target!"
        end
        
        local damage = M.calculateDamage(user, target, self.basePower, true, self.moveType)
        local message = user.name .. " used Water Gun!"
        message = message .. getTypeEffectivenessMessage(self.moveType, target)
        message = message .. M.applyDamage(target, damage, battle)
        
        return damage, message
    end
}

Skills.Absorb = {
    name = "Absorb",
    description = "A Grass-type attack that drains HP. (Power: 20)",
    skillType = "active",
    targetType = "enemy",
    moveType = "grass",
    category = "special",
    priority = 0,
    basePower = 20,
    accuracy = 100,
    ranged = true,
    execute = function(self, user, target, battle)
        if not target or target.currentHP <= 0 then
            return nil, user.name .. " has no target!"
        end
        
        local damage = M.calculateDamage(user, target, self.basePower, true, self.moveType)
        local message = user.name .. " used Absorb!"
        message = message .. getTypeEffectivenessMessage(self.moveType, target)
        message = message .. M.applyDamage(target, damage, battle)
        
        -- Drain 50% of damage dealt
        if damage > 0 then
            local healAmount = math.max(1, math.floor(damage / 2))
            local actualHeal = M.applyHeal(user, healAmount)
            if actualHeal > 0 then
                message = message .. "\n" .. user.name .. " absorbed " .. actualHeal .. " HP!"
            end
        end
        
        return damage, message
    end
}

Skills.Recover = {
    name = "Recover",
    description = "Restores up to 50% of max HP to self or ally.",
    skillType = "active",
    targetType = "ally_or_self",
    moveType = "normal",
    category = "status",
    priority = 0,
    basePower = 0,
    accuracy = 100,
    ranged = true,
    execute = function(self, user, target, battle)
        local actualTarget = target or user
        local maxHP = (actualTarget.stats and actualTarget.stats.hp) or 100
        local healAmount = math.floor(maxHP * 0.5)
        local actualHeal = M.applyHeal(actualTarget, healAmount)
        
        if actualHeal > 0 then
            if actualTarget == user then
                return actualHeal, user.name .. " used Recover and restored " .. actualHeal .. " HP!"
            else
                return actualHeal, user.name .. " used Recover on " .. actualTarget.name .. " and restored " .. actualHeal .. " HP!"
            end
        else
            if actualTarget == user then
                return 0, user.name .. " used Recover but HP is already full!"
            else
                return 0, user.name .. " tried to heal " .. actualTarget.name .. " but HP is already full!"
            end
        end
    end
}

Skills.Growl = {
    name = "Growl",
    description = "Lowers the target's Attack stat.",
    skillType = "active",
    targetType = "enemy",
    moveType = "normal",
    category = "status",
    priority = 0,
    basePower = 0,
    accuracy = 100,
    ranged = true,
    execute = function(self, user, target, battle)
        if not target or target.currentHP <= 0 then
            return nil, user.name .. " has no target!"
        end
        
        local _, statMsg = M.modifyStatStage(target, "attack", -1)
        return 0, user.name .. " used Growl!\n" .. statMsg
    end
}

Skills.TailWhip = {
    name = "Tail Whip",
    description = "Lowers the target's Defense stat.",
    skillType = "active",
    targetType = "enemy",
    moveType = "normal",
    category = "status",
    priority = 0,
    basePower = 0,
    accuracy = 100,
    ranged = false,
    execute = function(self, user, target, battle)
        if not target or target.currentHP <= 0 then
            return nil, user.name .. " has no target!"
        end
        
        local _, statMsg = M.modifyStatStage(target, "defense", -1)
        return 0, user.name .. " used Tail Whip!\n" .. statMsg
    end
}

--------------------------------------------------
-- PASSIVE SKILLS
-- Trigger Types:
--   on_round_start       - Start of Round
--   before_ally_attack   - Before Ally Attacks
--   after_ally_attack    - After Ally Attacks
--   before_ally_attacked - Before Ally is Attacked
--   after_ally_hit       - After Ally is Hit
--   on_round_end         - End of Round
--------------------------------------------------

Passives.Protect = {
    name = "Protect",
    description = "Completely blocks an attack on self or an ally.",
    skillType = "passive",
    targetType = "ally_or_self",
    triggerType = "before_ally_attacked",
    animationType = "guard",
    ranged = true,
    limited = true,
    passivePriority = 10,
    execute = function(self, owner, ally, damage, battle)
        if owner.currentHP <= 0 then return nil end
        if not ally or ally.currentHP <= 0 then return nil end
        
        -- Ensure owner and ally are on the same team
        if battle and battle.getFormationSide then
            local ownerSide = battle.getFormationSide(owner)
            local allySide = battle.getFormationSide(ally)
            if ownerSide ~= allySide then
                return nil  -- Can't protect enemies
            end
        end
        
        ally.isProtected = true
        ally.protectedBy = owner
        return nil, owner.name .. " protected " .. ally.name .. "!"
    end
}

Passives.QuickAttack = {
    name = "Quick Attack",
    description = "Attacks an enemy at the start of the round. (Power: 40)",
    skillType = "passive",
    targetType = "enemy",
    triggerType = "on_round_start",
    animationType = "attack",
    ranged = false,
    limited = false,
    passivePriority = 8,
    basePower = 40,
    execute = function(self, owner, target, damage, battle)
        if owner.currentHP <= 0 then return nil end
        
        local actualTarget = target
        if not actualTarget then
            local enemyFormation = battle.getEnemyFormation(owner)
            if enemyFormation then
                for _, enemy in ipairs(enemyFormation) do
                    if enemy and enemy.currentHP and enemy.currentHP > 0 then
                        actualTarget = enemy
                        break
                    end
                end
            end
        end
        
        if not actualTarget or actualTarget.currentHP <= 0 then return nil end
        
        local attackDamage = M.calculateDamage(owner, actualTarget, self.basePower, false, "normal")
        local message = owner.name .. " used Quick Attack on " .. actualTarget.name .. "!"
        message = message .. getTypeEffectivenessMessage("normal", actualTarget)
        message = message .. M.applyDamage(actualTarget, attackDamage, battle)
        
        return attackDamage, message
    end
}

Passives.Intimidate = {
    name = "Intimidate",
    description = "Lowers one enemy's Attack at start of round.",
    skillType = "passive",
    targetType = "enemy",
    triggerType = "on_round_start",
    animationType = "debuff",
    ranged = false,
    limited = false,
    passivePriority = 5,
    execute = function(self, owner, target, damage, battle)
        if owner.currentHP <= 0 then return nil end
        
        local actualTarget = target
        if not actualTarget then
            local enemyFormation = battle.getEnemyFormation(owner)
            if not enemyFormation then return nil end
            
            for i, enemy in ipairs(enemyFormation) do
                if enemy and enemy.currentHP and enemy.currentHP > 0 then
                    local enemyRow = (i <= 3) and 0 or 1
                    local ownerRow = owner.row or 0
                    if ownerRow == 0 and enemyRow == 0 then
                        actualTarget = enemy
                        break
                    end
                end
            end
        end
        
        if not actualTarget or actualTarget.currentHP <= 0 then return nil end
        
        local _, statMsg = M.modifyStatStage(actualTarget, "attack", -1)
        return nil, owner.name .. "'s Intimidate!\n" .. statMsg
    end
}

Passives.RoughSkin = {
    name = "Rough Skin",
    description = "Damages attacker when hit by a physical move.",
    skillType = "passive",
    targetType = "self",
    triggerType = "after_ally_hit",
    animationType = "recoil",
    ranged = true,
    limited = false,
    passivePriority = 5,
    isSelfTrigger = true,
    execute = function(self, owner, attacker, damage, battle)
        if owner.currentHP <= 0 then return nil end
        if not attacker or attacker.currentHP <= 0 then return nil end
        
        if battle and battle.currentAction and battle.currentAction.skill then
            local skillCategory = battle.currentAction.skill.category
            if skillCategory ~= "physical" then
                return nil
            end
        else
            return nil
        end
        
        local maxHP = (attacker.stats and attacker.stats.hp) or 100
        local recoilDamage = math.max(1, math.floor(maxHP / 8))
        local damageMsg = M.applyDamage(attacker, recoilDamage, battle)
        
        return recoilDamage, owner.name .. "'s Rough Skin!" .. damageMsg
    end
}

Passives.Rage = {
    name = "Rage",
    description = "Attack increases when hit by a physical move.",
    skillType = "passive",
    targetType = "self",
    triggerType = "after_ally_hit",
    animationType = "buff",
    ranged = true,
    limited = false,
    passivePriority = 5,
    isSelfTrigger = true,
    execute = function(self, owner, attacker, damage, battle)
        if owner.currentHP <= 0 then return nil end
        
        if battle and battle.currentAction and battle.currentAction.skill then
            local skillCategory = battle.currentAction.skill.category
            if skillCategory ~= "physical" then
                return nil
            end
        else
            return nil
        end
        
        local _, statMsg = M.modifyStatStage(owner, "attack", 1)
        return nil, owner.name .. "'s Rage!\n" .. statMsg
    end
}

Passives.KeenEye = {
    name = "Keen Eye",
    description = "First attack is guaranteed to hit.",
    skillType = "passive",
    targetType = "self",
    triggerType = "before_ally_attack",
    animationType = "focus",
    ranged = true,
    limited = false,
    passivePriority = 5,
    execute = function(self, owner, target, damage, battle)
        if owner.currentHP <= 0 then return nil end
        
        if not owner.keenEyeUsedThisRound then
            owner.keenEyeUsedThisRound = true
            owner.guaranteedHit = true
            return nil, owner.name .. "'s Keen Eye ensures the attack hits!"
        end
        return nil
    end
}

Passives.PartingShot = {
    name = "Parting Shot",
    description = "Attacks an enemy at end of round. Deals damage and lowers Attack/Sp.Atk.",
    skillType = "passive",
    targetType = "enemy",
    triggerType = "on_round_end",
    animationType = "attack",
    ranged = true,
    limited = false,
    passivePriority = 5,
    basePower = 40,
    execute = function(self, owner, target, damage, battle)
        if owner.currentHP <= 0 then return nil end
        
        local actualTarget = target
        if not actualTarget then
            local enemyFormation = battle.getEnemyFormation(owner)
            if enemyFormation then
                for _, enemy in ipairs(enemyFormation) do
                    if enemy and enemy.currentHP and enemy.currentHP > 0 then
                        actualTarget = enemy
                        break
                    end
                end
            end
        end
        
        if not actualTarget or actualTarget.currentHP <= 0 then return nil end
        
        local attackDamage = M.calculateDamage(owner, actualTarget, self.basePower, false, "dark")
        local damageMsg = M.applyDamage(actualTarget, attackDamage, battle)
        
        local _, atkMsg = M.modifyStatStage(actualTarget, "attack", -1)
        local _, spatkMsg = M.modifyStatStage(actualTarget, "special_attack", -1)
        
        return attackDamage, owner.name .. " used Parting Shot on " .. actualTarget.name .. "!" .. damageMsg .. "\n" .. atkMsg .. "\n" .. spatkMsg
    end
}

Passives.HealPowder = {
    name = "Heal Powder",
    description = "Heals an ally (or self) for 25% of their max HP when they take damage.",
    skillType = "passive",
    targetType = "ally_or_self",
    triggerType = "after_ally_hit",
    animationType = "heal",
    ranged = true,
    limited = false,
    passivePriority = 3,
    execute = function(self, owner, target, damage, battle)
        if owner.currentHP <= 0 then return nil end
        
        -- Target is the ally that was hit (could be self if isSelfTrigger-like behavior)
        -- Heal the target that took damage
        local actualTarget = target
        if not actualTarget or actualTarget.currentHP <= 0 then
            return nil  -- Can't heal a fainted Pokemon
        end
        
        -- Check if target is on same team as owner
        if battle and battle.getFormationSide then
            local ownerSide = battle.getFormationSide(owner)
            local targetSide = battle.getFormationSide(actualTarget)
            if ownerSide ~= targetSide then
                return nil  -- Can't heal enemies
            end
        end
        
        local maxHP = (actualTarget.stats and actualTarget.stats.hp) or 100
        local healAmount = math.floor(maxHP * 0.25)
        local actualHeal = M.applyHeal(actualTarget, healAmount)
        
        if actualHeal > 0 then
            if actualTarget == owner then
                return actualHeal, owner.name .. "'s Heal Powder restored " .. actualHeal .. " HP!"
            else
                return actualHeal, owner.name .. "'s Heal Powder healed " .. actualTarget.name .. " for " .. actualHeal .. " HP!"
            end
        end
        return nil
    end
}

--------------------------------------------------
-- EXPORTS
--------------------------------------------------

M.Skills = Skills
M.Passives = Passives

-- Build AllSkills list
M.AllSkills = {}
for name, skill in pairs(Skills) do
    skill.id = name
    table.insert(M.AllSkills, skill)
end
for name, passive in pairs(Passives) do
    passive.id = name
    table.insert(M.AllSkills, passive)
end

-- Default loadouts by type
M.TypeDefaultLoadouts = {
    normal = {
        {skill = "Tackle", condition1 = "target_hp_below_50", condition2 = "none"},
        {skill = "Growl", condition1 = "none", condition2 = "target_hp_highest"},
        {skill = "QuickAttack", condition1 = "none", condition2 = "target_hp_lowest"},
        {skill = "Protect", condition1 = "none", condition2 = "none"},
    },
    fire = {
        {skill = "Ember", condition1 = "target_hp_below_50", condition2 = "none"},
        {skill = "Growl", condition1 = "none", condition2 = "target_hp_highest"},
        {skill = "Tackle", condition1 = "none", condition2 = "target_hp_lowest"},
        {skill = "Protect", condition1 = "none", condition2 = "none"},
    },
    water = {
        {skill = "WaterGun", condition1 = "target_hp_below_50", condition2 = "none"},
        {skill = "TailWhip", condition1 = "none", condition2 = "target_hp_highest"},
        {skill = "Tackle", condition1 = "none", condition2 = "target_hp_lowest"},
        {skill = "Protect", condition1 = "none", condition2 = "none"},
    },
    grass = {
        {skill = "Absorb", condition1 = "target_hp_below_50", condition2 = "none"},
        {skill = "Growl", condition1 = "none", condition2 = "target_hp_highest"},
        {skill = "Tackle", condition1 = "none", condition2 = "none"},
        {skill = "Protect", condition1 = "none", condition2 = "none"},
    },
    electric = {
        {skill = "Tackle", condition1 = "target_hp_below_50", condition2 = "none"},
        {skill = "TailWhip", condition1 = "none", condition2 = "target_hp_highest"},
        {skill = "QuickAttack", condition1 = "none", condition2 = "target_hp_lowest"},
        {skill = "Protect", condition1 = "none", condition2 = "none"},
    },
}

M.DefaultLoadout = {
    {skill = "Tackle", condition1 = "target_hp_below_50", condition2 = "none"},
    {skill = "Growl", condition1 = "none", condition2 = "target_hp_highest"},
    {skill = "Tackle", condition1 = "none", condition2 = "none"},
    {skill = "Protect", condition1 = "none", condition2 = "none"},
}

--------------------------------------------------
-- SKILL LEARNSETS
-- Format: SpeciesId = { {level = #, skill = "SkillId"}, ... }
-- Pokemon learn skills when they reach the specified level
--------------------------------------------------

M.SkillLearnsets = {
    -------------------------------------------------
    -- Gen 1 Starters (First Evolution)
    -------------------------------------------------
    bulbasaur = {
        {level = 1, skill = "Tackle"},
        {level = 1, skill = "Growl"},
        {level = 5, skill = "Absorb"},
        {level = 7, skill = "HealPowder"},
        {level = 9, skill = "Recover"},
    },
    charmander = {
        {level = 1, skill = "Tackle"},
        {level = 1, skill = "Growl"},
        {level = 5, skill = "Ember"},
        {level = 9, skill = "PartingShot"},
    },
    squirtle = {
        {level = 1, skill = "Tackle"},
        {level = 1, skill = "TailWhip"},
        {level = 5, skill = "WaterGun"},
        {level = 9, skill = "Protect"},
    },
    
    -------------------------------------------------
    -- Route 29 Pokemon (Gen 2)
    -------------------------------------------------
    pidgey = {
        {level = 3, skill = "Growl", condition1 = "round_1", condition2 = "target_hp_highest"},
        {level = 1, skill = "Tackle", condition1 = "none", condition2 = "none"},
        {level = 5, skill = "QuickAttack"},
    },
    sentret = {
        {level = 1, skill = "Tackle", condition1 = "none", condition2 = "none"},
        {level = 1, skill = "Protect"},
        {level = 7, skill = "Growl"},
    },
    rattata = {
        {level = 1, skill = "TailWhip", condition1 = "round_1", condition2 = "target_hp_highest"},
        {level = 1, skill = "Tackle"},
        {level = 4, skill = "QuickAttack"},
    },
    hoothoot = {
        {level = 1, skill = "Tackle", condition1 = "none", condition2 = "none"},
        {level = 1, skill = "Growl"},
        {level = 5, skill = "PartingShot"},
        -- {level = 9, skill = "QuickAttack"},
    },
    hoppip = {
        {level = 1, skill = "Absorb", condition1 = "none", condition2 = "none"},
        {level = 5, skill = "Growl"},
        {level = 6, skill = "HealPowder"},
    },
}

-- Get the skills a Pokemon knows based on its species and level
-- Returns a list of skill IDs
function M.getKnownSkills(speciesId, level)
    local learnset = M.SkillLearnsets[speciesId:lower()]
    local knownSkills = {}
    
    if learnset then
        for _, entry in ipairs(learnset) do
            if entry.level <= level then
                -- Check if skill already known (avoid duplicates)
                local alreadyKnown = false
                for _, skillId in ipairs(knownSkills) do
                    if skillId == entry.skill then
                        alreadyKnown = true
                        break
                    end
                end
                if not alreadyKnown then
                    table.insert(knownSkills, entry.skill)
                end
            end
        end
    else
        -- Fallback: if no learnset defined, give default skills based on level
        table.insert(knownSkills, "Tackle")
        if level >= 3 then
            table.insert(knownSkills, "Growl")
        end
        if level >= 6 then
            table.insert(knownSkills, "Protect")
        end
    end
    
    return knownSkills
end

-- Check if a Pokemon knows a specific skill
function M.knowsSkill(speciesId, level, skillId)
    local knownSkills = M.getKnownSkills(speciesId, level)
    for _, known in ipairs(knownSkills) do
        if known == skillId then
            return true
        end
    end
    return false
end

-- Get skill by ID (works for both active and passive)
function M.getSkillById(skillId)
    if Skills[skillId] then return Skills[skillId] end
    if Passives[skillId] then return Passives[skillId] end
    return nil
end

return M
