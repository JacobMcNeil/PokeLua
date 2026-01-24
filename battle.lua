---@diagnostic disable
-- battle.lua
-- Unicorn Overlord-style battle system
-- Pokemon are placed in a 3x2 formation (3 front, 3 back)
-- Combat is semi-automated based on skills

local M = {}
local log = require("log")
local UI = require("ui")
local SkillsModule = require("skills")

--------------------------------------------------
-- BATTLE STATE
--------------------------------------------------
M.active = false
M.mode = "idle" -- "idle", "executing", "result"

-- Player and enemy formations
-- Each formation is an array of 6 slots: [1-3] = front row, [4-6] = back row
-- nil = empty slot, otherwise Pokemon object
M.playerFormation = {nil, nil, nil, nil, nil, nil}
M.enemyFormation = {nil, nil, nil, nil, nil, nil}

-- Battle log for displaying messages
M.battleLog = {}
M.maxLogLines = 3
M.logQueue = {}
M.waitingForZ = false
M.awaitingClose = false

-- Player reference
M.player = nil

-- Trainer battle state
M.isTrainerBattle = false
M.trainer = nil
M.trainerDefeated = false

-- EXP tracking
M.defeatedEnemies = {}  -- Track defeated enemies for EXP calculation

-- Animation state
M.actionQueue = {} -- Queue of actions to execute
M.currentAction = nil
M.actionTimer = 0
M.actionDelay = 0.8 -- Seconds between actions

-- Attack animation state
M.animating = false
M.animAction = nil  -- Current action being animated
M.animPhase = "none"  -- "move_to", "attack", "move_back", "heal_bounce", "guard_move", "guard_flash"
M.animTimer = 0
M.animDuration = 0.15  -- Time for each animation phase
M.animStartX = 0
M.animStartY = 0
M.animTargetX = 0
M.animTargetY = 0
M.animCurrentX = 0
M.animCurrentY = 0

-- Passive animation state
M.passiveAnimating = false
M.passiveAnimType = "none"  -- "heal", "guard", "attack"
M.passiveAnimTimer = 0
M.passiveAnimDuration = 0.3
M.passiveAnimUser = nil  -- Pokemon using the passive
M.passiveAnimTarget = nil  -- Pokemon receiving the effect
M.passiveAnimPhase = "none"  -- Phase of the passive animation
M.passiveAnimUserStartX = 0
M.passiveAnimUserStartY = 0
M.passiveAnimUserCurrentX = 0
M.passiveAnimUserCurrentY = 0
M.passiveFlashTimer = 0  -- For flash effects
M.passiveFlashColor = {0, 1, 0}  -- Green for heal, blue for guard
M.passiveAnimTargetStartX = 0  -- Target position for attack animations
M.passiveAnimTargetStartY = 0

-- Message-synchronized animation system
-- Messages are queued with associated animations and HP changes
-- Animation plays when message is shown, HP updates with message
M.pendingAnimations = {}  -- Queue: {message, animation, hpChanges}
M.currentMessageAnim = nil  -- Currently playing animation for shown message
M.hpSnapshots = {}  -- Snapshot of HP before actions for smooth updates

-- Turn state
M.turnNumber = 0
M.roundNumber = 1
M.battlePhase = "tactics" -- "tactics", "start", "round_end", "end"

-- AP/PP defaults (Action Points / Passive Points per Pokemon per battle)
M.defaultAP = 1  -- Each Pokemon can act once per round
M.defaultPP = 1  -- Each Pokemon can trigger passive once per battle

-- Whiteout callback
M.whiteoutCallback = nil
M.playerWhitedOut = false

-- Tactics mode state
M.tacticsMode = false
M.tacticsCursor = 1  -- Current slot being hovered (1-6)
M.tacticsSelected = nil  -- Slot of Pokemon being moved (nil if none selected)
M.tacticsShowHelp = true  -- Show control hints
M.tacticsFromRoundEnd = false  -- True if entering tactics from round_end phase

-- Skill editing mode (submode of tactics)
M.skillEditMode = false  -- True when editing skills for a Pokemon
M.skillEditPokemon = nil  -- The Pokemon being edited
M.skillEditSlot = 1  -- Current skill slot being edited (1-8)
M.skillEditField = 1  -- Current field: 1=skill, 2=condition1, 3=condition2
M.skillPickerOpen = false  -- True when picking a skill/condition
M.skillPickerCursor = 1  -- Cursor in the picker list
M.skillPickerMode = "list"  -- "category" for category selection, "list" for item selection
M.skillPickerCategory = nil  -- Selected category ID when picking conditions

-- Sprite cache
local spriteCache = {}

--------------------------------------------------
-- PASSIVE ANIMATION HELPERS
--------------------------------------------------

-- Queue a passive animation to be played when its message is shown
-- hpChanges is an optional array of {pokemon, newHP} for synced HP display
function M.queuePassiveAnimation(animType, user, target, message, hpChanges)
    -- Queue the message with animation info attached
    -- Animation will start when this message is processed
    table.insert(M.logQueue, {
        text = message,
        hpChanges = hpChanges or {},
        animation = {
            type = animType,
            user = user,
            target = target
        }
    })
end

-- Start playing a passive animation (called when message with animation is shown)
function M.startPassiveAnimation(anim)
    if not anim then return false end
    
    M.passiveAnimating = true
    M.passiveAnimType = anim.type
    M.passiveAnimUser = anim.user
    M.passiveAnimTarget = anim.target
    M.passiveAnimTimer = 0
    M.passiveFlashTimer = 0
    
    -- Get user position - try both formations if side detection fails
    local userSide = M.getFormationSide(anim.user)
    local userX, userY
    if userSide then
        userX, userY = M.getSlotPosition(anim.user, userSide == "player")
    end
    -- If not found, try the other formation
    if not userX then
        userX, userY = M.getSlotPosition(anim.user, true)  -- Try player
        if not userX then
            userX, userY = M.getSlotPosition(anim.user, false)  -- Try enemy
        end
    end
    -- Default to center of screen if still not found
    local UI = require("ui")
    local screenW, screenH = UI.getGameScreenDimensions()
    M.passiveAnimUserStartX = userX or (screenW / 2)
    M.passiveAnimUserStartY = userY or (screenH / 2)
    M.passiveAnimUserCurrentX = M.passiveAnimUserStartX
    M.passiveAnimUserCurrentY = M.passiveAnimUserStartY
    
    -- Get target position for attack animations
    if anim.target then
        local targetSide = M.getFormationSide(anim.target)
        local targetX, targetY
        if targetSide then
            targetX, targetY = M.getSlotPosition(anim.target, targetSide == "player")
        end
        -- If not found, try both formations
        if not targetX then
            targetX, targetY = M.getSlotPosition(anim.target, true)
            if not targetX then
                targetX, targetY = M.getSlotPosition(anim.target, false)
            end
        end
        M.passiveAnimTargetStartX = targetX or (screenW / 2)
        M.passiveAnimTargetStartY = targetY or (screenH / 2)
    end
    
    if anim.type == "heal" then
        M.passiveAnimPhase = "bounce_up"
        M.passiveFlashColor = {0, 1, 0}  -- Green
        M.passiveAnimDuration = 0.15
    elseif anim.type == "guard" then
        M.passiveAnimPhase = "move_to_ally"
        M.passiveFlashColor = {0, 0.5, 1}  -- Blue
        M.passiveAnimDuration = 0.2
    elseif anim.type == "attack" then
        -- Attack animation similar to active skills (move to target, flash, move back)
        M.passiveAnimPhase = "attack_move_to"
        M.passiveFlashColor = {1, 0.5, 0}  -- Orange for pursuit/attack
        M.passiveAnimDuration = 0.15
    elseif anim.type == "buff" then
        -- Buff animation (stat increase) - simple flash effect on self
        M.passiveAnimPhase = "buff_flash"
        M.passiveFlashColor = {1, 0.8, 0.2}  -- Yellow/gold for buffs
        M.passiveAnimDuration = 0.25
    elseif anim.type == "debuff" then
        -- Debuff animation (stat decrease) - flash effect on target
        M.passiveAnimPhase = "debuff_flash"
        M.passiveFlashColor = {0.7, 0.2, 0.8}  -- Purple for debuffs
        M.passiveAnimDuration = 0.25
    elseif anim.type == "recoil" then
        -- Recoil damage animation
        M.passiveAnimPhase = "recoil_flash"
        M.passiveFlashColor = {1, 0.3, 0.3}  -- Red for damage
        M.passiveAnimDuration = 0.2
    else
        -- Default: just show message, no animation
        M.passiveAnimPhase = "done"
        M.passiveAnimDuration = 0.1
    end
    
    return true
end

--------------------------------------------------
-- COMPATIBILITY API (for main.lua integration)
--------------------------------------------------

-- Check if battle is active
function M.isActive()
    return M.active
end

-- Start battle (legacy API - routes to startBattle)
function M.start(enemyPokemonArray, player)
    local enemies = enemyPokemonArray
    if type(enemyPokemonArray) == "table" and #enemyPokemonArray > 0 then
        enemies = enemyPokemonArray
    end
    M.startBattle(player, enemies, false, nil)
end

-- Set whiteout callback
function M.setWhiteoutCallback(callback)
    M.whiteoutCallback = callback
end

--------------------------------------------------
-- STAT STAGE SYSTEM (Pokemon Standard)
--------------------------------------------------
-- Stat stages range from -6 to +6
-- Each stage applies a multiplier to the stat

-- Multipliers for regular stats (Attack, Defense, Sp.Atk, Sp.Def, Speed)
-- Stage -6 to +6 corresponds to index 1 to 13
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

-- Multipliers for Accuracy and Evasion
local AccuracyEvasionMultipliers = {
    [1] = 3/9,   -- -6: ~33%
    [2] = 3/8,   -- -5: ~38%
    [3] = 3/7,   -- -4: ~43%
    [4] = 3/6,   -- -3: 50%
    [5] = 3/5,   -- -2: 60%
    [6] = 3/4,   -- -1: 75%
    [7] = 3/3,   --  0: 100% (neutral)
    [8] = 4/3,   -- +1: ~133%
    [9] = 5/3,   -- +2: ~167%
    [10] = 6/3,  -- +3: 200%
    [11] = 7/3,  -- +4: ~233%
    [12] = 8/3,  -- +5: ~267%
    [13] = 9/3,  -- +6: 300%
}

-- Convert stage (-6 to +6) to array index (1 to 13)
local function stageToIndex(stage)
    return math.max(1, math.min(13, stage + 7))
end

-- Get stat multiplier for a given stage
local function getStatMultiplier(stage)
    local index = stageToIndex(stage)
    return StatStageMultipliers[index] or 1
end

-- Get accuracy/evasion multiplier for a given stage
local function getAccuracyEvasionMultiplier(stage)
    local index = stageToIndex(stage)
    return AccuracyEvasionMultipliers[index] or 1
end

-- Initialize stat stages for a Pokemon (called at battle start)
local function initStatStages(pokemon)
    if not pokemon then return end
    pokemon.statStages = {
        attack = 0,
        defense = 0,
        spAttack = 0,
        spDefense = 0,
        speed = 0,
        accuracy = 0,
        evasion = 0,
    }
end

-- Reset stat stages (called when Pokemon switches out or battle ends)
local function resetStatStages(pokemon)
    initStatStages(pokemon)
end

-- Modify a stat stage by a number of stages, returns actual change and message
local function modifyStatStage(pokemon, stat, stages)
    if not pokemon then return 0, "" end
    if not pokemon.statStages then
        initStatStages(pokemon)
    end
    
    local currentStage = pokemon.statStages[stat] or 0
    local newStage = math.max(-6, math.min(6, currentStage + stages))
    local actualChange = newStage - currentStage
    
    pokemon.statStages[stat] = newStage
    
    -- Generate message based on change
    local pokeName = pokemon.nickname or pokemon.name or "Pokemon"
    local statNames = {
        attack = "Attack",
        defense = "Defense",
        spAttack = "Sp. Atk",
        spDefense = "Sp. Def",
        speed = "Speed",
        accuracy = "accuracy",
        evasion = "evasiveness"
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
local function getEffectiveStat(pokemon, stat)
    if not pokemon then return 1 end
    
    -- Get base calculated stat
    local baseStat = 1
    if pokemon.stats and pokemon.stats[stat] then
        baseStat = pokemon.stats[stat]
    elseif pokemon[stat] then
        baseStat = pokemon[stat]
    end
    
    -- Apply stat stage multiplier
    local stage = 0
    if pokemon.statStages and pokemon.statStages[stat] then
        stage = pokemon.statStages[stat]
    end
    
    local multiplier = getStatMultiplier(stage)
    return math.floor(baseStat * multiplier)
end

M.initStatStages = initStatStages
M.resetStatStages = resetStatStages
M.modifyStatStage = modifyStatStage
M.getEffectiveStat = getEffectiveStat
M.getStatMultiplier = getStatMultiplier

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

-- Get type effectiveness multiplier
local function getTypeMultiplier(attackType, defenderTypes)
    attackType = string.lower(attackType or "normal")
    if not TypeChart[attackType] then return 1 end
    
    local multiplier = 1
    if type(defenderTypes) == 'string' then
        multiplier = TypeChart[attackType][string.lower(defenderTypes)] or 1
    elseif type(defenderTypes) == 'table' then
        for _, defType in ipairs(defenderTypes) do
            local typeMultiplier = TypeChart[attackType][string.lower(defType)] or 1
            multiplier = multiplier * typeMultiplier
        end
    end
    return multiplier
end

-- Check if user has STAB (Same Type Attack Bonus)
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

M.getTypeMultiplier = getTypeMultiplier

--------------------------------------------------
-- SKILLS SYSTEM (Pokemon Style)
--------------------------------------------------
-- Skills are now defined in skills.lua
-- Each Pokemon has a loadout of up to 8 skill slots
-- Each slot contains: skill, condition, target priority
-- Skills are either Active (use AP) or Passive (use PP on trigger)

local Skills = SkillsModule.Skills
local Passives = SkillsModule.Passives

-- Skill slot count per Pokemon
M.maxSkillSlots = 8

-- Use helpers from skills module
local calculateDamage = SkillsModule.calculateDamage
local applyDamage = SkillsModule.applyDamage
local applyHeal = SkillsModule.applyHeal

--------------------------------------------------
-- CONDITION SYSTEM (Reorganized by Category)
-- Conditions filter and sort the available targets
-- Categories: Target HP, Self HP, Target Position, Target Type, Skill Effectiveness, Attacked By
--------------------------------------------------

-- Condition Categories for UI organization
local ConditionCategories = {
    { id = "none", name = "No Filter" },
    { id = "target_hp", name = "Target HP" },
    { id = "self_hp", name = "Self HP" },
    { id = "target_ap_pp", name = "Target AP/PP" },
    { id = "self_ap_pp", name = "Self AP/PP" },
    { id = "target_position", name = "Target Position" },
    { id = "target_type", name = "Target Type" },
    { id = "skill_effectiveness", name = "Skill Effectiveness" },
    { id = "attacked_by_type", name = "Attacked By Type" },
    { id = "attacked_by_effectiveness", name = "Attacked By Effectiveness" },
    { id = "attacked_by_category", name = "Attacked By Category" },
    { id = "round", name = "Round Number" },
}
M.ConditionCategories = ConditionCategories

-- Helper: Get target's types
local function getTargetTypes(target)
    if not target then return {} end
    if target.species and target.species.types then
        return target.species.types
    elseif target.types then
        return target.types
    end
    return {"normal"}
end

-- Helper: Check if target has a specific type
local function targetHasType(target, checkType)
    local types = getTargetTypes(target)
    checkType = string.lower(checkType)
    for _, t in ipairs(types) do
        if string.lower(t) == checkType then
            return true
        end
    end
    return false
end

-- Helper: Get skill's move type (for effectiveness checks)
local function getSkillMoveType(user, battle)
    -- This gets the move type of the skill being used
    -- For condition checking, we use the current action's skill if available
    if battle and battle.currentAction and battle.currentAction.skill then
        return battle.currentAction.skill.moveType
    end
    -- Fallback: check user's first active skill
    if user and user.skillLoadout then
        for _, slot in ipairs(user.skillLoadout) do
            if slot.skill and Skills and Skills[slot.skill] then
                local skill = Skills[slot.skill]
                if skill.moveType then
                    return skill.moveType
                end
            end
        end
    end
    return "normal"
end

-- All conditions organized by category
local Conditions = {
    -- No filter (always passes)
    { id = "none", name = "Any", category = "none", 
      filter = function(user, target, battle) return true end,
      sort = function(a, b) return false end -- No sorting
    },
    
    --------------------------------------------------
    -- TARGET HP CONDITIONS
    --------------------------------------------------
    { id = "target_hp_highest", name = "Highest HP", category = "target_hp",
      filter = function(user, target, battle) return true end,
      sort = function(a, b) return a.currentHP > b.currentHP end
    },
    { id = "target_hp_lowest", name = "Lowest HP", category = "target_hp",
      filter = function(user, target, battle) return true end,
      sort = function(a, b) return a.currentHP < b.currentHP end
    },
    { id = "target_hp_highest_pct", name = "Highest HP %", category = "target_hp",
      filter = function(user, target, battle) return true end,
      sort = function(a, b) 
        local aMax = (a.stats and a.stats.hp) or 100
        local bMax = (b.stats and b.stats.hp) or 100
        return (a.currentHP / aMax) > (b.currentHP / bMax)
      end
    },
    { id = "target_hp_lowest_pct", name = "Lowest HP %", category = "target_hp",
      filter = function(user, target, battle) return true end,
      sort = function(a, b) 
        local aMax = (a.stats and a.stats.hp) or 100
        local bMax = (b.stats and b.stats.hp) or 100
        return (a.currentHP / aMax) < (b.currentHP / bMax)
      end
    },
    { id = "target_hp_full", name = "HP = 100%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return target.currentHP >= maxHP
      end,
      sort = function(a, b) return false end
    },
    { id = "target_hp_not_full", name = "HP < 100%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return target.currentHP < maxHP
      end,
      sort = function(a, b) return a.currentHP < b.currentHP end
    },
    { id = "target_hp_above_90", name = "HP > 90%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) > 0.90
      end,
      sort = function(a, b) return a.currentHP > b.currentHP end
    },
    { id = "target_hp_below_90", name = "HP < 90%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) < 0.90
      end,
      sort = function(a, b) return a.currentHP < b.currentHP end
    },
    { id = "target_hp_above_75", name = "HP > 75%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) > 0.75
      end,
      sort = function(a, b) return a.currentHP > b.currentHP end
    },
    { id = "target_hp_below_75", name = "HP < 75%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) < 0.75
      end,
      sort = function(a, b) return a.currentHP < b.currentHP end
    },
    { id = "target_hp_above_66", name = "HP > 66%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) > 0.66
      end,
      sort = function(a, b) return a.currentHP > b.currentHP end
    },
    { id = "target_hp_below_66", name = "HP < 66%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) < 0.66
      end,
      sort = function(a, b) return a.currentHP < b.currentHP end
    },
    { id = "target_hp_above_50", name = "HP > 50%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) > 0.5
      end,
      sort = function(a, b) return a.currentHP > b.currentHP end
    },
    { id = "target_hp_below_50", name = "HP < 50%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) < 0.5
      end,
      sort = function(a, b) return a.currentHP < b.currentHP end
    },
    { id = "target_hp_above_33", name = "HP > 33%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) > 0.33
      end,
      sort = function(a, b) return a.currentHP > b.currentHP end
    },
    { id = "target_hp_below_33", name = "HP < 33%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) < 0.33
      end,
      sort = function(a, b) return a.currentHP < b.currentHP end
    },
    { id = "target_hp_below_25", name = "HP < 25%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) < 0.25
      end,
      sort = function(a, b) return a.currentHP < b.currentHP end
    },
    { id = "target_hp_below_10", name = "HP < 10%", category = "target_hp",
      filter = function(user, target, battle)
        if not target then return false end
        local maxHP = (target.stats and target.stats.hp) or 100
        return (target.currentHP / maxHP) < 0.10
      end,
      sort = function(a, b) return a.currentHP < b.currentHP end
    },
    
    --------------------------------------------------
    -- SELF HP CONDITIONS
    --------------------------------------------------
    { id = "self_hp_full", name = "Self HP = 100%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return user.currentHP >= maxHP
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_not_full", name = "Self HP < 100%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return user.currentHP < maxHP
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_above_90", name = "Self HP > 90%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) > 0.90
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_below_90", name = "Self HP < 90%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) < 0.90
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_above_75", name = "Self HP > 75%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) > 0.75
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_below_75", name = "Self HP < 75%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) < 0.75
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_above_66", name = "Self HP > 66%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) > 0.66
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_below_66", name = "Self HP < 66%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) < 0.66
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_above_50", name = "Self HP > 50%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) > 0.5
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_below_50", name = "Self HP < 50%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) < 0.5
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_above_33", name = "Self HP > 33%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) > 0.33
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_below_33", name = "Self HP < 33%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) < 0.33
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_below_25", name = "Self HP < 25%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) < 0.25
      end,
      sort = function(a, b) return false end
    },
    { id = "self_hp_below_10", name = "Self HP < 10%", category = "self_hp",
      filter = function(user, target, battle)
        local maxHP = (user.stats and user.stats.hp) or 100
        return (user.currentHP / maxHP) < 0.10
      end,
      sort = function(a, b) return false end
    },
    
    --------------------------------------------------
    -- TARGET AP/PP CONDITIONS
    --------------------------------------------------
    { id = "target_has_ap", name = "Has AP", category = "target_ap_pp",
      filter = function(user, target, battle)
        if not target then return false end
        return (target.battleAP or 0) > 0
      end,
      sort = function(a, b) return (a.battleAP or 0) > (b.battleAP or 0) end
    },
    { id = "target_no_ap", name = "No AP", category = "target_ap_pp",
      filter = function(user, target, battle)
        if not target then return false end
        return (target.battleAP or 0) <= 0
      end,
      sort = function(a, b) return false end
    },
    { id = "target_has_pp", name = "Has PP", category = "target_ap_pp",
      filter = function(user, target, battle)
        if not target then return false end
        return (target.battlePP or 0) > 0
      end,
      sort = function(a, b) return (a.battlePP or 0) > (b.battlePP or 0) end
    },
    { id = "target_no_pp", name = "No PP", category = "target_ap_pp",
      filter = function(user, target, battle)
        if not target then return false end
        return (target.battlePP or 0) <= 0
      end,
      sort = function(a, b) return false end
    },
    { id = "target_most_ap", name = "Most AP", category = "target_ap_pp",
      filter = function(user, target, battle) return true end,
      sort = function(a, b) return (a.battleAP or 0) > (b.battleAP or 0) end
    },
    { id = "target_most_pp", name = "Most PP", category = "target_ap_pp",
      filter = function(user, target, battle) return true end,
      sort = function(a, b) return (a.battlePP or 0) > (b.battlePP or 0) end
    },
    
    --------------------------------------------------
    -- SELF AP/PP CONDITIONS
    --------------------------------------------------
    { id = "self_has_ap", name = "Self Has AP", category = "self_ap_pp",
      filter = function(user, target, battle)
        return (user.battleAP or 0) > 0
      end,
      sort = function(a, b) return false end
    },
    { id = "self_no_ap", name = "Self No AP", category = "self_ap_pp",
      filter = function(user, target, battle)
        return (user.battleAP or 0) <= 0
      end,
      sort = function(a, b) return false end
    },
    { id = "self_has_pp", name = "Self Has PP", category = "self_ap_pp",
      filter = function(user, target, battle)
        return (user.battlePP or 0) > 0
      end,
      sort = function(a, b) return false end
    },
    { id = "self_no_pp", name = "Self No PP", category = "self_ap_pp",
      filter = function(user, target, battle)
        return (user.battlePP or 0) <= 0
      end,
      sort = function(a, b) return false end
    },
    
    --------------------------------------------------
    -- TARGET POSITION CONDITIONS
    --------------------------------------------------
    { id = "target_front_row", name = "Front Row Only", category = "target_position",
      filter = function(user, target, battle)
        if not target then return false end
        local formation = battle.getAllyFormation(target)
        for i = 1, 3 do
            if formation[i] == target then return true end
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "target_back_row", name = "Back Row Only", category = "target_position",
      filter = function(user, target, battle)
        if not target then return false end
        local formation = battle.getAllyFormation(target)
        for i = 4, 6 do
            if formation[i] == target then return true end
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "target_across", name = "Across First", category = "target_position",
      filter = function(user, target, battle) return true end,
      sort = function(a, b) return false end -- Sorting handled specially in getActiveSkillForAction
    },
    
    --------------------------------------------------
    -- TARGET TYPE CONDITIONS (all 18 types)
    --------------------------------------------------
    { id = "target_type_normal", name = "Normal Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "normal") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_fire", name = "Fire Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "fire") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_water", name = "Water Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "water") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_grass", name = "Grass Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "grass") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_electric", name = "Electric Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "electric") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_ice", name = "Ice Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "ice") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_fighting", name = "Fighting Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "fighting") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_poison", name = "Poison Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "poison") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_ground", name = "Ground Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "ground") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_flying", name = "Flying Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "flying") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_psychic", name = "Psychic Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "psychic") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_bug", name = "Bug Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "bug") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_rock", name = "Rock Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "rock") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_ghost", name = "Ghost Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "ghost") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_dragon", name = "Dragon Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "dragon") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_dark", name = "Dark Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "dark") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_steel", name = "Steel Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "steel") end,
      sort = function(a, b) return false end
    },
    { id = "target_type_fairy", name = "Fairy Type", category = "target_type",
      filter = function(user, target, battle) return targetHasType(target, "fairy") end,
      sort = function(a, b) return false end
    },
    
    --------------------------------------------------
    -- SKILL EFFECTIVENESS CONDITIONS
    -- Based on the skill's type vs target's type
    --------------------------------------------------
    { id = "skill_super_effective", name = "Super Effective (2x)", category = "skill_effectiveness",
      filter = function(user, target, battle)
        if not target then return false end
        local moveType = getSkillMoveType(user, battle)
        local defenderTypes = getTargetTypes(target)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult >= 2 and mult < 4
      end,
      sort = function(a, b) return false end
    },
    { id = "skill_double_effective", name = "Double Effective (4x)", category = "skill_effectiveness",
      filter = function(user, target, battle)
        if not target then return false end
        local moveType = getSkillMoveType(user, battle)
        local defenderTypes = getTargetTypes(target)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult >= 4
      end,
      sort = function(a, b) return false end
    },
    { id = "skill_not_very_effective", name = "Not Very Effective (0.5x)", category = "skill_effectiveness",
      filter = function(user, target, battle)
        if not target then return false end
        local moveType = getSkillMoveType(user, battle)
        local defenderTypes = getTargetTypes(target)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult > 0 and mult <= 0.5 and mult > 0.25
      end,
      sort = function(a, b) return false end
    },
    { id = "skill_doubly_resisted", name = "Doubly Resisted (0.25x)", category = "skill_effectiveness",
      filter = function(user, target, battle)
        if not target then return false end
        local moveType = getSkillMoveType(user, battle)
        local defenderTypes = getTargetTypes(target)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult > 0 and mult <= 0.25
      end,
      sort = function(a, b) return false end
    },
    { id = "skill_immune", name = "Immune (0x)", category = "skill_effectiveness",
      filter = function(user, target, battle)
        if not target then return false end
        local moveType = getSkillMoveType(user, battle)
        local defenderTypes = getTargetTypes(target)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult == 0
      end,
      sort = function(a, b) return false end
    },
    { id = "skill_neutral", name = "Neutral (1x)", category = "skill_effectiveness",
      filter = function(user, target, battle)
        if not target then return false end
        local moveType = getSkillMoveType(user, battle)
        local defenderTypes = getTargetTypes(target)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult == 1
      end,
      sort = function(a, b) return false end
    },
    { id = "skill_effective_or_better", name = "Effective+ (>=2x)", category = "skill_effectiveness",
      filter = function(user, target, battle)
        if not target then return false end
        local moveType = getSkillMoveType(user, battle)
        local defenderTypes = getTargetTypes(target)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult >= 2
      end,
      sort = function(a, b) 
        local moveType = getSkillMoveType(user, battle)
        local aMult = getTypeMultiplier(moveType, getTargetTypes(a))
        local bMult = getTypeMultiplier(moveType, getTargetTypes(b))
        return aMult > bMult
      end
    },
    { id = "skill_not_resisted", name = "Not Resisted (>=1x)", category = "skill_effectiveness",
      filter = function(user, target, battle)
        if not target then return false end
        local moveType = getSkillMoveType(user, battle)
        local defenderTypes = getTargetTypes(target)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult >= 1
      end,
      sort = function(a, b) return false end
    },
    { id = "skill_not_super_effective", name = "NOT Super Effective (<2x)", category = "skill_effectiveness",
      filter = function(user, target, battle)
        if not target then return false end
        local moveType = getSkillMoveType(user, battle)
        local defenderTypes = getTargetTypes(target)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult < 2
      end,
      sort = function(a, b) return false end
    },
    { id = "skill_not_immune", name = "NOT Immune (>0x)", category = "skill_effectiveness",
      filter = function(user, target, battle)
        if not target then return false end
        local moveType = getSkillMoveType(user, battle)
        local defenderTypes = getTargetTypes(target)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult > 0
      end,
      sort = function(a, b) return false end
    },
    { id = "skill_resisted", name = "Resisted (<1x)", category = "skill_effectiveness",
      filter = function(user, target, battle)
        if not target then return false end
        local moveType = getSkillMoveType(user, battle)
        local defenderTypes = getTargetTypes(target)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult < 1
      end,
      sort = function(a, b) return false end
    },
    
    --------------------------------------------------
    -- ATTACKED BY TYPE CONDITIONS
    -- For passives: check if the incoming attack is of a specific type
    --------------------------------------------------
    { id = "attacked_by_normal", name = "Attacked by Normal", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "normal"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_fire", name = "Attacked by Fire", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "fire"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_water", name = "Attacked by Water", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "water"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_grass", name = "Attacked by Grass", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "grass"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_electric", name = "Attacked by Electric", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "electric"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_ice", name = "Attacked by Ice", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "ice"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_fighting", name = "Attacked by Fighting", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "fighting"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_poison", name = "Attacked by Poison", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "poison"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_ground", name = "Attacked by Ground", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "ground"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_flying", name = "Attacked by Flying", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "flying"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_psychic", name = "Attacked by Psychic", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "psychic"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_bug", name = "Attacked by Bug", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "bug"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_rock", name = "Attacked by Rock", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "rock"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_ghost", name = "Attacked by Ghost", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "ghost"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_dragon", name = "Attacked by Dragon", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "dragon"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_dark", name = "Attacked by Dark", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "dark"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_steel", name = "Attacked by Steel", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "steel"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_fairy", name = "Attacked by Fairy", category = "attacked_by_type",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.moveType or ""):lower() == "fairy"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    
    --------------------------------------------------
    -- ATTACKED BY EFFECTIVENESS CONDITIONS
    -- For passives: check the effectiveness of incoming attack on self/ally
    --------------------------------------------------
    { id = "attacked_super_effective", name = "Attack is Super Effective", category = "attacked_by_effectiveness",
      filter = function(user, target, battle)
        if not battle or not battle.currentAction or not battle.currentAction.skill then return false end
        local moveType = battle.currentAction.skill.moveType
        if not moveType then return false end
        -- target here is the ally being protected, so we check effectiveness against them
        local defenderTypes = getTargetTypes(target or user)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult >= 2 and mult < 4
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_double_effective", name = "Attack is 4x Effective", category = "attacked_by_effectiveness",
      filter = function(user, target, battle)
        if not battle or not battle.currentAction or not battle.currentAction.skill then return false end
        local moveType = battle.currentAction.skill.moveType
        if not moveType then return false end
        local defenderTypes = getTargetTypes(target or user)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult >= 4
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_not_very_effective", name = "Attack is Not Very Effective", category = "attacked_by_effectiveness",
      filter = function(user, target, battle)
        if not battle or not battle.currentAction or not battle.currentAction.skill then return false end
        local moveType = battle.currentAction.skill.moveType
        if not moveType then return false end
        local defenderTypes = getTargetTypes(target or user)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult > 0 and mult <= 0.5
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_immune", name = "Attack is Immune", category = "attacked_by_effectiveness",
      filter = function(user, target, battle)
        if not battle or not battle.currentAction or not battle.currentAction.skill then return false end
        local moveType = battle.currentAction.skill.moveType
        if not moveType then return false end
        local defenderTypes = getTargetTypes(target or user)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult == 0
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_neutral", name = "Attack is Neutral", category = "attacked_by_effectiveness",
      filter = function(user, target, battle)
        if not battle or not battle.currentAction or not battle.currentAction.skill then return false end
        local moveType = battle.currentAction.skill.moveType
        if not moveType then return false end
        local defenderTypes = getTargetTypes(target or user)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult == 1
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_effective_or_better", name = "Attack is 2x+ Effective", category = "attacked_by_effectiveness",
      filter = function(user, target, battle)
        if not battle or not battle.currentAction or not battle.currentAction.skill then return false end
        local moveType = battle.currentAction.skill.moveType
        if not moveType then return false end
        local defenderTypes = getTargetTypes(target or user)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult >= 2
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_not_super_effective", name = "Attack is NOT Super Effective (<2x)", category = "attacked_by_effectiveness",
      filter = function(user, target, battle)
        if not battle or not battle.currentAction or not battle.currentAction.skill then return false end
        local moveType = battle.currentAction.skill.moveType
        if not moveType then return false end
        local defenderTypes = getTargetTypes(target or user)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult < 2
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_not_immune", name = "Attack is NOT Immune (>0x)", category = "attacked_by_effectiveness",
      filter = function(user, target, battle)
        if not battle or not battle.currentAction or not battle.currentAction.skill then return false end
        local moveType = battle.currentAction.skill.moveType
        if not moveType then return false end
        local defenderTypes = getTargetTypes(target or user)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult > 0
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_resisted", name = "Attack is Resisted (<1x)", category = "attacked_by_effectiveness",
      filter = function(user, target, battle)
        if not battle or not battle.currentAction or not battle.currentAction.skill then return false end
        local moveType = battle.currentAction.skill.moveType
        if not moveType then return false end
        local defenderTypes = getTargetTypes(target or user)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult < 1
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_not_resisted", name = "Attack is NOT Resisted (>=1x)", category = "attacked_by_effectiveness",
      filter = function(user, target, battle)
        if not battle or not battle.currentAction or not battle.currentAction.skill then return false end
        local moveType = battle.currentAction.skill.moveType
        if not moveType then return false end
        local defenderTypes = getTargetTypes(target or user)
        local mult = getTypeMultiplier(moveType, defenderTypes)
        return mult >= 1
      end,
      sort = function(a, b) return false end
    },
    
    --------------------------------------------------
    -- ATTACKED BY CATEGORY CONDITIONS
    -- For passives: check if the incoming attack is physical/special/status
    --------------------------------------------------
    { id = "attacked_by_physical", name = "Attacked by Physical", category = "attacked_by_category",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.category or ""):lower() == "physical"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_special", name = "Attacked by Special", category = "attacked_by_category",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.category or ""):lower() == "special"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    { id = "attacked_by_status", name = "Attacked by Status", category = "attacked_by_category",
      filter = function(user, target, battle)
        if battle and battle.currentAction and battle.currentAction.skill then
            return (battle.currentAction.skill.category or ""):lower() == "status"
        end
        return false
      end,
      sort = function(a, b) return false end
    },
    
    --------------------------------------------------
    -- ROUND NUMBER CONDITIONS
    --------------------------------------------------
    { id = "round_1", name = "Round 1", category = "round",
      filter = function(user, target, battle)
        return battle and battle.roundNumber == 1
      end,
      sort = function(a, b) return false end
    },
    { id = "round_2", name = "Round 2", category = "round",
      filter = function(user, target, battle)
        return battle and battle.roundNumber == 2
      end,
      sort = function(a, b) return false end
    },
    { id = "round_3", name = "Round 3", category = "round",
      filter = function(user, target, battle)
        return battle and battle.roundNumber == 3
      end,
      sort = function(a, b) return false end
    },
    { id = "round_4", name = "Round 4", category = "round",
      filter = function(user, target, battle)
        return battle and battle.roundNumber == 4
      end,
      sort = function(a, b) return false end
    },
    { id = "round_5", name = "Round 5", category = "round",
      filter = function(user, target, battle)
        return battle and battle.roundNumber == 5
      end,
      sort = function(a, b) return false end
    },
    { id = "round_1_or_2", name = "Round 1-2", category = "round",
      filter = function(user, target, battle)
        return battle and battle.roundNumber and battle.roundNumber <= 2
      end,
      sort = function(a, b) return false end
    },
    { id = "round_3_plus", name = "Round 3+", category = "round",
      filter = function(user, target, battle)
        return battle and battle.roundNumber and battle.roundNumber >= 3
      end,
      sort = function(a, b) return false end
    },
}
M.Conditions = Conditions

-- Get condition by ID
local function getConditionById(conditionId)
    if not conditionId or conditionId == "" then
        return Conditions[1] -- Default to "none"
    end
    for _, cond in ipairs(Conditions) do
        if cond.id == conditionId then return cond end
    end
    return Conditions[1] -- Default to "none"
end

-- Get conditions by category
local function getConditionsByCategory(categoryId)
    local result = {}
    for _, cond in ipairs(Conditions) do
        if cond.category == categoryId then
            table.insert(result, cond)
        end
    end
    return result
end

M.getConditionsByCategory = getConditionsByCategory

--------------------------------------------------
-- SKILL EXPORTS (from skills.lua)
--------------------------------------------------
-- Skills and Passives are defined in skills.lua module

M.Skills = Skills
M.Passives = Passives
M.AllSkills = SkillsModule.AllSkills

-- Use loadouts from skills module
local TypeDefaultLoadouts = SkillsModule.TypeDefaultLoadouts
local DefaultLoadout = SkillsModule.DefaultLoadout

-- Helper: Generate type effectiveness message
local function getTypeEffectivenessMessage(moveType, target)
    if not moveType then return "" end
    local defenderTypes = SkillsModule.getDefenderTypes(target)
    local mult = SkillsModule.getTypeMultiplier(moveType, defenderTypes)
    if mult >= 2 then
        return " It's super effective!"
    elseif mult > 0 and mult < 1 then
        return " It's not very effective..."
    elseif mult == 0 then
        return " It doesn't affect " .. target.name .. "..."
    end
    return ""
end

-- Initialize or get a Pokemon's skill loadout
local function getOrCreateLoadout(pokemon)
    if pokemon.skillLoadout then return pokemon.skillLoadout end
    
    -- Get the species ID for skill lookups
    local speciesId = pokemon.speciesId or (pokemon.species and pokemon.species.name and pokemon.species.name:lower():gsub(" ", "_"))
    local level = pokemon.level or 5
    
    -- Get the skills this Pokemon knows based on its learnset
    local knownSkills = SkillsModule.getKnownSkills(speciesId or "unknown", level)
    
    -- Create loadout from known skills
    pokemon.skillLoadout = {}
    
    -- Build a default loadout using known skills with sensible conditions
    -- Priority: Find damaging moves first, then status moves, then passives
    local activeDamage = {}
    local activeStatus = {}
    local passives = {}
    
    for _, skillId in ipairs(knownSkills) do
        local skill = SkillsModule.getSkillById(skillId)
        if skill then
            if skill.skillType == "active" then
                if skill.category == "status" then
                    table.insert(activeStatus, skillId)
                else
                    table.insert(activeDamage, skillId)
                end
            elseif skill.skillType == "passive" then
                table.insert(passives, skillId)
            end
        end
    end
    
    local slotIndex = 1
    
    -- Slot 1: First damaging move with condition "target_hp_below_50"
    if #activeDamage > 0 then
        pokemon.skillLoadout[slotIndex] = {
            skill = activeDamage[1],
            condition1 = "target_hp_below_50",
            condition2 = "none",
        }
        slotIndex = slotIndex + 1
    end
    
    -- Slot 2: First status move with "target_hp_highest"
    if #activeStatus > 0 then
        pokemon.skillLoadout[slotIndex] = {
            skill = activeStatus[1],
            condition1 = "none",
            condition2 = "target_hp_highest",
        }
        slotIndex = slotIndex + 1
    end
    
    -- Slot 3: Damaging move with no conditions (fallback)
    if #activeDamage > 0 then
        pokemon.skillLoadout[slotIndex] = {
            skill = activeDamage[1],
            condition1 = "none",
            condition2 = "none",
        }
        slotIndex = slotIndex + 1
    end
    
    -- Slot 4: First passive (like Protect, QuickAttack)
    if #passives > 0 then
        pokemon.skillLoadout[slotIndex] = {
            skill = passives[1],
            condition1 = "none",
            condition2 = "none",
        }
        slotIndex = slotIndex + 1
    end
    
    -- Fill remaining slots up to 4 with additional skills
    -- Try to add a second passive if available
    if slotIndex <= 4 and #passives > 1 then
        pokemon.skillLoadout[slotIndex] = {
            skill = passives[2],
            condition1 = "none",
            condition2 = "none",
        }
        slotIndex = slotIndex + 1
    end
    
    -- If still less than 4 slots, try additional damaging moves
    local damageIndex = 2
    while slotIndex <= 4 and damageIndex <= #activeDamage do
        pokemon.skillLoadout[slotIndex] = {
            skill = activeDamage[damageIndex],
            condition1 = "none",
            condition2 = "none",
        }
        slotIndex = slotIndex + 1
        damageIndex = damageIndex + 1
    end
    
    -- Fallback: If loadout is empty, give Tackle
    if #pokemon.skillLoadout == 0 then
        pokemon.skillLoadout[1] = {
            skill = "Tackle",
            condition1 = "none",
            condition2 = "none",
        }
    end
    
    return pokemon.skillLoadout
end

-- Helper: Check if a formation has any living Pokemon in front row (slots 1-3)
local function hasFrontRowAlive(formation)
    for i = 1, 3 do
        if formation[i] and formation[i].currentHP and formation[i].currentHP > 0 then
            return true
        end
    end
    return false
end

-- Get target pool based on skill's targetType and ranged property
-- Returns targets with slot info for across-targeting
-- Non-ranged skills can only target front row if front row has living targets
local function getTargetPool(skill, user, battle)
    local targetType = skill.targetType or "enemy"
    local isRanged = skill.ranged or false
    
    if targetType == "self" then
        return { {pokemon = user, slot = 0} }
    elseif targetType == "ally_or_self" then
        -- Include self and all allies
        local allies = battle.getAllyFormation(user)
        local pool = {}
        local frontRowHasTargets = hasFrontRowAlive(allies)
        
        -- Add self first
        table.insert(pool, {pokemon = user, slot = 0})
        
        for i = 1, 6 do
            local ally = allies[i]
            if ally and ally ~= user and ally.currentHP and ally.currentHP > 0 then
                -- For non-ranged ally skills, only allow front row if front row has targets
                local isBackRow = (i >= 4)
                if isRanged or not frontRowHasTargets or not isBackRow then
                    table.insert(pool, {pokemon = ally, slot = i})
                end
            end
        end
        return pool
    elseif targetType == "ally" then
        local allies = battle.getAllyFormation(user)
        local pool = {}
        local frontRowHasTargets = hasFrontRowAlive(allies)
        
        for i = 1, 6 do
            local ally = allies[i]
            if ally and ally.currentHP and ally.currentHP > 0 then
                -- For non-ranged ally skills, only allow front row if front row has targets
                -- (or back row if front row is empty)
                local isBackRow = (i >= 4)
                if isRanged or not frontRowHasTargets or not isBackRow then
                    table.insert(pool, {pokemon = ally, slot = i})
                end
            end
        end
        return pool
    else -- "enemy"
        local enemies = battle.getEnemyFormation(user)
        local pool = {}
        local frontRowHasTargets = hasFrontRowAlive(enemies)
        
        for i = 1, 6 do
            local enemy = enemies[i]
            if enemy and enemy.currentHP and enemy.currentHP > 0 then
                -- For non-ranged enemy skills, only allow front row if front row has targets
                -- (or back row if front row is empty)
                local isBackRow = (i >= 4)
                if isRanged or not frontRowHasTargets or not isBackRow then
                    table.insert(pool, {pokemon = enemy, slot = i})
                end
            end
        end
        return pool
    end
end

-- Get user's slot in their formation
local function getUserSlot(user, battle)
    local formation = battle.getAllyFormation(user)
    for i = 1, 6 do
        if formation[i] == user then return i end
    end
    return 1
end

-- Get the first active skill that meets conditions
local function getActiveSkillForAction(pokemon, battle)
    local loadout = getOrCreateLoadout(pokemon)
    local enemyFormation = battle.getEnemyFormation(pokemon)
    local defaultTarget = battle.getFrontMost(enemyFormation)
    local userSlot = getUserSlot(pokemon, battle)
    
    for _, slot in ipairs(loadout) do
        if slot.skill then
            local skill = Skills[slot.skill]
            if skill and skill.skillType == "active" then
                -- Get target pool based on skill's targetType
                local targetPoolWithSlots = getTargetPool(skill, pokemon, battle)
                
                -- Get conditions
                local cond1 = getConditionById(slot.condition1 or "none")
                local cond2 = getConditionById(slot.condition2 or "none")
                
                -- Apply condition1 filter
                local filtered = {}
                for _, targetInfo in ipairs(targetPoolWithSlots) do
                    if cond1.filter(pokemon, targetInfo.pokemon, battle) then
                        table.insert(filtered, targetInfo)
                    end
                end
                
                -- If no targets pass filter, skill doesn't activate
                if #filtered == 0 then
                    goto continue
                end
                
                -- Default sort: prefer across (same slot), then front row first
                -- This is the base ordering before condition sorts are applied
                table.sort(filtered, function(a, b)
                    -- Same slot (across) has highest priority
                    local aAcross = (a.slot == userSlot) and 0 or 1
                    local bAcross = (b.slot == userSlot) and 0 or 1
                    if aAcross ~= bAcross then
                        return aAcross < bAcross
                    end
                    -- Then front row (1-3) before back row (4-6)
                    local aFront = (a.slot <= 3) and 0 or 1
                    local bFront = (b.slot <= 3) and 0 or 1
                    return aFront < bFront
                end)
                
                -- Apply condition1 sort if it has one (overrides default)
                if cond1.sort and cond1.id ~= "none" then
                    table.sort(filtered, function(a, b)
                        return cond1.sort(a.pokemon, b.pokemon)
                    end)
                end
                
                -- Apply condition2 filter (further filtering)
                local filtered2 = {}
                for _, targetInfo in ipairs(filtered) do
                    if cond2.filter(pokemon, targetInfo.pokemon, battle) then
                        table.insert(filtered2, targetInfo)
                    end
                end
                
                -- If condition2 has a filter (not "none") and no targets pass, skill doesn't activate
                if cond2.id ~= "none" and #filtered2 == 0 then
                    goto continue
                end
                
                -- Use filtered2 if condition2 was applied, otherwise use filtered
                local finalPool = #filtered2 > 0 and filtered2 or filtered
                
                -- Apply condition2 sort if it has one
                if cond2.sort and cond2.id ~= "none" then
                    table.sort(finalPool, function(a, b)
                        return cond2.sort(a.pokemon, b.pokemon)
                    end)
                end
                
                -- Return first valid target
                if #finalPool > 0 then
                    return skill, finalPool[1].pokemon
                end
                
                ::continue::
            end
        end
    end
    
    -- Fallback to Tackle targeting front
    return Skills.Tackle, defaultTarget
end

-- Get passive skill for a trigger type from loadout
local function getPassiveForTrigger(pokemon, triggerType)
    local loadout = getOrCreateLoadout(pokemon)
    
    for _, slot in ipairs(loadout) do
        if slot.skill then
            local passive = Passives[slot.skill]
            if passive and passive.skillType == "passive" and passive.triggerType == triggerType then
                return passive
            end
        end
    end
    
    return nil
end

-- Get all passives for a trigger type from loadout (returns array with slot info)
local function getAllPassivesForTrigger(pokemon, triggerType)
    local loadout = getOrCreateLoadout(pokemon)
    local passives = {}
    
    for _, slot in ipairs(loadout) do
        if slot.skill then
            local passive = Passives[slot.skill]
            if passive and passive.skillType == "passive" and passive.triggerType == triggerType then
                table.insert(passives, {passive = passive, slot = slot})
            end
        end
    end
    
    return passives
end

-- Legacy compatibility function
local function getSkillsForPokemon(pokemon)
    local loadout = getOrCreateLoadout(pokemon)
    local activeSkill = Skills.Tackle
    local passiveSkill = Passives.Evade
    
    for _, slot in ipairs(loadout) do
        if slot.skill then
            if Skills[slot.skill] then
                activeSkill = Skills[slot.skill]
                break
            end
        end
    end
    
    for _, slot in ipairs(loadout) do
        if slot.skill then
            if Passives[slot.skill] then
                passiveSkill = Passives[slot.skill]
                break
            end
        end
    end
    
    return activeSkill, passiveSkill
end

M.getSkillsForPokemon = getSkillsForPokemon
M.getOrCreateLoadout = getOrCreateLoadout
M.getActiveSkillForAction = getActiveSkillForAction
M.getPassiveForTrigger = getPassiveForTrigger
M.getConditionById = getConditionById
M.getTargetPriorityById = getTargetPriorityById

--------------------------------------------------
-- PASSIVE TRIGGER SYSTEM (Unicorn Overlord Style)
-- Trigger Types:
--   on_round_start       - Start of Round
--   before_ally_attack   - Before Ally Attacks (Active)
--   after_ally_attack    - After Ally Attacks (Active)
--   before_ally_attacked - Before Ally is Attacked
--   after_ally_hit       - After Ally is Hit
--   before_self_hit      - Before Being Hit (Self)
--   before_enemy_attack  - Before Enemy Uses Attack Skill
--   after_enemy_attack   - After Enemy Attacks (Active)
--   on_round_end         - End of Round
--------------------------------------------------

-- Track last target for pursuit-style skills
M.lastTarget = nil
M.lastAttacker = nil

-- Get which formation the Pokemon belongs to (returns "player" or "enemy")
function M.getFormationSide(pokemon)
    for i = 1, 6 do
        if M.playerFormation[i] == pokemon then return "player" end
    end
    for i = 1, 6 do
        if M.enemyFormation[i] == pokemon then return "enemy" end
    end
    return nil
end

-- Get the enemy formation for a given Pokemon
function M.getEnemyFormation(pokemon)
    local side = M.getFormationSide(pokemon)
    if side == "player" then
        return M.enemyFormation
    else
        return M.playerFormation
    end
end

-- Get the ally formation for a given Pokemon
function M.getAllyFormation(pokemon)
    local side = M.getFormationSide(pokemon)
    if side == "player" then
        return M.playerFormation
    else
        return M.enemyFormation
    end
end

-- Trigger passives of a specific type on a single Pokemon
function M.triggerPassives(triggerType, target, source, damage)
    if not target then return end
    
    -- Get all passives for this trigger type from target's loadout
    local passiveInfos = getAllPassivesForTrigger(target, triggerType)
    if #passiveInfos == 0 then return end
    
    for _, info in ipairs(passiveInfos) do
        local passive = info.passive
        local slot = info.slot
        
        -- Check conditions (self = target, condition target = source)
        local cond1 = getConditionById(slot.condition1 or "none")
        local cond2 = getConditionById(slot.condition2 or "none")
        
        if not cond1.filter(target, source, M) then goto continue end
        if not cond2.filter(target, source, M) then goto continue end
        
        -- Check if target has PP remaining
        if (target.battlePP or 0) > 0 then
            -- Consume PP
            target.battlePP = target.battlePP - 1
            
            -- Execute passive
            local result, message = passive:execute(target, source, damage, M)
            if message then
                -- Collect HP changes for synced display
                local hpChanges = {}
                if target then
                    table.insert(hpChanges, {pokemon = target, newHP = target.currentHP})
                end
                if source then
                    table.insert(hpChanges, {pokemon = source, newHP = source.currentHP})
                end
                M.queueMessage(message, hpChanges)
            end
        end
        
        ::continue::
    end
end

-- Trigger passives for all allies of the triggerPokemon
-- For after_ally_hit: triggerPokemon is the ally that was hit
-- For after_ally_attack: triggerPokemon is the ally that attacked
-- Implements limited passive logic: only one limited skill can activate per trigger
function M.triggerAllyPassives(triggerType, triggerPokemon, otherPokemon, damage)
    if not triggerPokemon then return end
    
    local formation = M.getAllyFormation(triggerPokemon)
    if not formation then return end
    
    -- Store last target for pursuit-style skills
    M.lastTarget = otherPokemon
    M.lastAttacker = triggerPokemon
    
    -- Collect all potential passives with their owners
    local candidates = {}
    
    -- First, check the triggerPokemon itself for isSelfTrigger or ally_or_self passives
    -- This handles passives like Rough Skin and Rage that trigger when the owner is hit
    -- Also handles passives like HealPowder that can heal self when owner is hit
    if triggerPokemon.currentHP and triggerPokemon.currentHP > 0 then
        local selfPassiveInfos = getAllPassivesForTrigger(triggerPokemon, triggerType)
        for _, info in ipairs(selfPassiveInfos) do
            local passive = info.passive
            local slot = info.slot
            
            -- Process isSelfTrigger passives OR ally_or_self passives for the triggerPokemon
            local canTriggerOnSelf = passive.isSelfTrigger or passive.targetType == "ally_or_self"
            if canTriggerOnSelf then
                -- Check conditions (self = triggerPokemon, target = otherPokemon/attacker for isSelfTrigger)
                -- For ally_or_self, the target to heal is triggerPokemon itself
                local cond1 = getConditionById(slot.condition1 or "none")
                local cond2 = getConditionById(slot.condition2 or "none")
                
                local condTarget = passive.isSelfTrigger and otherPokemon or triggerPokemon
                if cond1.filter(triggerPokemon, condTarget, M) and cond2.filter(triggerPokemon, condTarget, M) then
                    if (triggerPokemon.battlePP or 0) > 0 then
                        table.insert(candidates, {
                            ally = triggerPokemon,
                            passive = passive,
                            slot = slot,
                            priority = passive.passivePriority or 0,
                            limited = passive.limited or false,
                            targetOverride = (passive.targetType == "ally_or_self" and not passive.isSelfTrigger) and triggerPokemon or nil
                        })
                    end
                end
            end
        end
    end
    
    -- Then check allies (excluding triggerPokemon)
    for i = 1, 6 do
        local ally = formation[i]
        if ally and ally ~= triggerPokemon and ally.currentHP and ally.currentHP > 0 then
            local passiveInfos = getAllPassivesForTrigger(ally, triggerType)
            for _, info in ipairs(passiveInfos) do
                local passive = info.passive
                local slot = info.slot
                
                -- Skip isSelfTrigger passives for allies (they only trigger on the owner)
                if passive.isSelfTrigger then
                    goto continue
                end
                
                -- Check conditions (self = ally/passive owner, target = triggerPokemon)
                local cond1 = getConditionById(slot.condition1 or "none")
                local cond2 = getConditionById(slot.condition2 or "none")
                
                if cond1.filter(ally, triggerPokemon, M) and cond2.filter(ally, triggerPokemon, M) then
                    if (ally.battlePP or 0) > 0 then
                        -- Check ranged targeting for enemy-targeting passives
                        local validTarget = true
                        if passive.targetType == "enemy" and not passive.ranged then
                            local enemyFormation = M.getEnemyFormation(ally)
                            if hasFrontRowAlive(enemyFormation) then
                                local target = otherPokemon or M.lastTarget
                                if target then
                                    local targetSlot = nil
                                    for j = 1, 6 do
                                        if enemyFormation[j] == target then targetSlot = j break end
                                    end
                                    if targetSlot and targetSlot >= 4 then
                                        validTarget = false  -- Can't reach back row with non-ranged
                                    end
                                end
                            end
                        end
                        
                        if validTarget then
                            table.insert(candidates, {
                                ally = ally,
                                passive = passive,
                                slot = slot,
                                priority = passive.passivePriority or 0,
                                limited = passive.limited or false
                            })
                        end
                    end
                end
                
                ::continue::
            end
        end
    end
    
    -- Sort by priority (higher first)
    table.sort(candidates, function(a, b)
        return a.priority > b.priority
    end)
    
    -- Track if a limited passive has already triggered
    local limitedTriggered = false
    
    -- Execute passives respecting limited constraint
    for _, cand in ipairs(candidates) do
        -- Skip limited passives if one already triggered
        if cand.limited and limitedTriggered then
            goto continue
        end
        
        -- Consume PP and execute
        cand.ally.battlePP = cand.ally.battlePP - 1
        -- For isSelfTrigger passives, pass otherPokemon (the attacker) as second param
        -- For canTriggerOnSelf passives, use targetOverride if present
        -- For other passives, pass triggerPokemon (the ally that was hit/attacked)
        local executeTarget
        if cand.targetOverride then
            executeTarget = cand.targetOverride
        elseif cand.passive.isSelfTrigger then
            executeTarget = otherPokemon
        else
            executeTarget = triggerPokemon
        end
        local result, message = cand.passive:execute(cand.ally, executeTarget, damage, M)
        
        -- Mark limited as triggered
        if cand.limited then
            limitedTriggered = true
        end
        
        -- Collect HP changes for synced display
        local hpChanges = {}
        if cand.ally then
            table.insert(hpChanges, {pokemon = cand.ally, newHP = cand.ally.currentHP})
        end
        if triggerPokemon then
            table.insert(hpChanges, {pokemon = triggerPokemon, newHP = triggerPokemon.currentHP})
        end
        if otherPokemon and otherPokemon ~= triggerPokemon then
            table.insert(hpChanges, {pokemon = otherPokemon, newHP = otherPokemon.currentHP})
        end
        
        -- Queue animation if passive has one
        if message and cand.passive.animationType then
            M.queuePassiveAnimation(cand.passive.animationType, cand.ally, executeTarget or triggerPokemon, message, hpChanges)
        elseif message then
            M.queueMessage(message, hpChanges)
        end
        
        ::continue::
    end
end

-- Trigger passives for enemies when attacker attacks (before/after enemy attacks)
function M.triggerEnemyPassives(triggerType, attacker, target, damage)
    if not attacker or not target then return end
    
    -- Get the target's allies (defender's side)
    local defenderFormation = M.getAllyFormation(target)
    if not defenderFormation then return end
    
    for i = 1, 6 do
        local defender = defenderFormation[i]
        if defender and defender.currentHP and defender.currentHP > 0 then
            local passiveInfos = getAllPassivesForTrigger(defender, triggerType)
            for _, info in ipairs(passiveInfos) do
                local passive = info.passive
                local slot = info.slot
                
                -- Check conditions (self = defender, target = attacker)
                local cond1 = getConditionById(slot.condition1 or "none")
                local cond2 = getConditionById(slot.condition2 or "none")
                
                if not cond1.filter(defender, attacker, M) then goto continue end
                if not cond2.filter(defender, attacker, M) then goto continue end
                
                if (defender.battlePP or 0) > 0 then
                    defender.battlePP = defender.battlePP - 1
                    local _, message = passive:execute(defender, attacker, damage, M)
                    if message then
                        local hpChanges = {}
                        table.insert(hpChanges, {pokemon = defender, newHP = defender.currentHP})
                        table.insert(hpChanges, {pokemon = attacker, newHP = attacker.currentHP})
                        M.queueMessage(message, hpChanges)
                    end
                end
                
                ::continue::
            end
        end
    end
end

-- Trigger before_ally_attacked for allies of the target
-- Implements limited passive logic: only one limited skill can activate per trigger
function M.triggerBeforeAllyAttacked(target, attacker)
    if not target then return end
    
    -- Only trigger for damaging moves (physical or special), not status moves
    if M.currentAction and M.currentAction.skill then
        local category = M.currentAction.skill.category
        if category == "status" then
            return  -- Status moves don't trigger Protect
        end
    end
    
    local formation = M.getAllyFormation(target)
    if not formation then return end
    
    -- Collect all potential passives with their owners
    local candidates = {}
    for i = 1, 6 do
        local ally = formation[i]
        -- For ally_or_self passives (like Protect), also check the target itself
        -- For ally-only passives, skip the target
        if ally and ally.currentHP and ally.currentHP > 0 then
            local passiveInfos = getAllPassivesForTrigger(ally, "before_ally_attacked")
            for _, info in ipairs(passiveInfos) do
                local passive = info.passive
                local slot = info.slot
                
                -- Skip if this is ally-only targeting and ally is the target
                if ally == target and passive.targetType ~= "ally_or_self" then
                    goto skip_passive
                end
                
                -- Check conditions (self = ally/passive owner, target = ally being attacked)
                local cond1 = getConditionById(slot.condition1 or "none")
                local cond2 = getConditionById(slot.condition2 or "none")
                
                if cond1.filter(ally, target, M) and cond2.filter(ally, target, M) then
                    if (ally.battlePP or 0) > 0 then
                        table.insert(candidates, {
                            ally = ally,
                            passive = passive,
                            slot = slot,
                            priority = passive.passivePriority or 0,
                            limited = passive.limited or false
                        })
                    end
                end
                
                ::skip_passive::
            end
        end
    end
    
    -- Sort by priority (higher first)
    table.sort(candidates, function(a, b)
        return a.priority > b.priority
    end)
    
    -- Track if a limited passive has already triggered
    local limitedTriggered = false
    
    -- Execute passives respecting limited constraint
    for _, cand in ipairs(candidates) do
        -- Skip limited passives if one already triggered
        if cand.limited and limitedTriggered then
            goto continue
        end
        
        -- Consume PP and execute
        cand.ally.battlePP = cand.ally.battlePP - 1
        local result, message = cand.passive:execute(cand.ally, target, 0, M)
        
        -- Mark limited as triggered
        if cand.limited then
            limitedTriggered = true
        end
        
        -- Collect HP changes for synced display
        local hpChanges = {}
        if cand.ally then
            table.insert(hpChanges, {pokemon = cand.ally, newHP = cand.ally.currentHP})
        end
        if target then
            table.insert(hpChanges, {pokemon = target, newHP = target.currentHP})
        end
        
        -- Queue animation if passive has one
        if message and cand.passive.animationType then
            M.queuePassiveAnimation(cand.passive.animationType, cand.ally, target, message, hpChanges)
        elseif message then
            M.queueMessage(message, hpChanges)
        end
        
        ::continue::
    end
end

-- Trigger before_self_hit for the target itself
function M.triggerBeforeSelfHit(target, attacker)
    if not target or target.currentHP <= 0 then return end
    
    local passiveInfos = getAllPassivesForTrigger(target, "before_self_hit")
    for _, info in ipairs(passiveInfos) do
        local passive = info.passive
        local slot = info.slot
        
        -- Check conditions (self = target, target = attacker)
        local cond1 = getConditionById(slot.condition1 or "none")
        local cond2 = getConditionById(slot.condition2 or "none")
        
        if not cond1.filter(target, attacker, M) then goto continue end
        if not cond2.filter(target, attacker, M) then goto continue end
        
        if (target.battlePP or 0) > 0 then
            target.battlePP = target.battlePP - 1
            local _, message = passive:execute(target, attacker, 0, M)
            if message then
                local hpChanges = {}
                table.insert(hpChanges, {pokemon = target, newHP = target.currentHP})
                M.queueMessage(message, hpChanges)
            end
        end
        
        ::continue::
    end
end

-- Trigger round start passives for all living Pokemon
function M.triggerRoundStartPassives()
    local allPokemon = {}
    
    for i = 1, 6 do
        local p = M.playerFormation[i]
        if p and p.currentHP and p.currentHP > 0 then
            table.insert(allPokemon, p)
        end
    end
    for i = 1, 6 do
        local p = M.enemyFormation[i]
        if p and p.currentHP and p.currentHP > 0 then
            table.insert(allPokemon, p)
        end
    end
    
    for _, pokemon in ipairs(allPokemon) do
        local passiveInfos = getAllPassivesForTrigger(pokemon, "on_round_start")
        for _, info in ipairs(passiveInfos) do
            local passive = info.passive
            local slot = info.slot
            
            -- Get conditions
            local cond1 = getConditionById(slot.condition1 or "none")
            local cond2 = getConditionById(slot.condition2 or "none")
            
            -- For self-targeting passives, check conditions against self
            -- For enemy/ally targeting passives, find appropriate target
            local target = nil
            if passive.targetType == "enemy" then
                local enemyFormation = M.getEnemyFormation(pokemon)
                local validTargets = {}
                if enemyFormation then
                    for j = 1, 6 do
                        local enemy = enemyFormation[j]
                        if enemy and enemy.currentHP and enemy.currentHP > 0 then
                            if cond1.filter(pokemon, enemy, M) and cond2.filter(pokemon, enemy, M) then
                                table.insert(validTargets, enemy)
                            end
                        end
                    end
                end
                -- Sort targets based on conditions and pick best
                if #validTargets > 0 then
                    table.sort(validTargets, function(a, b)
                        if cond2.sort then return cond2.sort(a, b) end
                        if cond1.sort then return cond1.sort(a, b) end
                        return false
                    end)
                    target = validTargets[1]
                end
            elseif passive.targetType == "self" then
                -- Self-targeting passives check conditions against self
                if not cond1.filter(pokemon, pokemon, M) then goto continue end
                if not cond2.filter(pokemon, pokemon, M) then goto continue end
                target = pokemon
            end
            
            if (pokemon.battlePP or 0) > 0 and target then
                pokemon.battlePP = pokemon.battlePP - 1
                
                -- For attack-type passives, set currentAction so Rough Skin/Rage can check category
                if passive.animationType == "attack" and passive.basePower and passive.basePower > 0 then
                    M.currentAction = {
                        user = pokemon,
                        target = target,
                        skill = {
                            name = passive.name,
                            category = "physical",  -- Attack passives are physical
                            moveType = passive.moveType or "normal",
                        }
                    }
                    
                    -- Trigger before_ally_attacked for target (this is where Protect triggers)
                    M.triggerBeforeAllyAttacked(target, pokemon)
                    
                    -- Check if target is protected (Protect triggered)
                    if target.isProtected then
                        target.isProtected = nil
                        target.protectedBy = nil
                        M.currentAction = nil
                        -- Still show the attack animation with a "blocked" message
                        local blockedMessage = pokemon.name .. " used " .. passive.name .. " but it was blocked!"
                        local hpChanges = {{pokemon = pokemon, newHP = pokemon.currentHP}}
                        M.queuePassiveAnimation(passive.animationType, pokemon, target, blockedMessage, hpChanges)
                        goto continue
                    end
                end
                
                local damageDealt, message = passive:execute(pokemon, target, 0, M)
                
                -- For attack passives that dealt damage, trigger after_ally_hit events
                if passive.animationType == "attack" and damageDealt and damageDealt > 0 and target.currentHP > 0 then
                    -- Trigger after_ally_hit for target's side (Rough Skin, Rage, etc.)
                    M.triggerAllyPassives("after_ally_hit", target, pokemon, damageDealt)
                end
                
                -- Clear current action
                M.currentAction = nil
                
                if message then
                    local hpChanges = {{pokemon = pokemon, newHP = pokemon.currentHP}}
                    -- Also track target HP changes for damage-dealing passives
                    if target and target ~= pokemon then
                        table.insert(hpChanges, {pokemon = target, newHP = target.currentHP})
                    end
                    -- Use passive animation for attack-type passives
                    if passive.animationType then
                        M.queuePassiveAnimation(passive.animationType, pokemon, target, message, hpChanges)
                    else
                        M.queueMessage(message, hpChanges)
                    end
                end
            end
            
            ::continue::
        end
    end
end

-- Trigger round end passives for all living Pokemon
function M.triggerRoundEndPassives()
    local allPokemon = {}
    
    for i = 1, 6 do
        local p = M.playerFormation[i]
        if p and p.currentHP and p.currentHP > 0 then
            table.insert(allPokemon, p)
        end
    end
    for i = 1, 6 do
        local p = M.enemyFormation[i]
        if p and p.currentHP and p.currentHP > 0 then
            table.insert(allPokemon, p)
        end
    end
    
    for _, pokemon in ipairs(allPokemon) do
        local passiveInfos = getAllPassivesForTrigger(pokemon, "on_round_end")
        for _, info in ipairs(passiveInfos) do
            local passive = info.passive
            local slot = info.slot
            
            -- Get conditions
            local cond1 = getConditionById(slot.condition1 or "none")
            local cond2 = getConditionById(slot.condition2 or "none")
            
            -- For self-targeting passives, check conditions against self
            -- For enemy/ally targeting passives, find appropriate target
            local target = nil
            if passive.targetType == "enemy" then
                local enemyFormation = M.getEnemyFormation(pokemon)
                local validTargets = {}
                if enemyFormation then
                    for j = 1, 6 do
                        local enemy = enemyFormation[j]
                        if enemy and enemy.currentHP and enemy.currentHP > 0 then
                            if cond1.filter(pokemon, enemy, M) and cond2.filter(pokemon, enemy, M) then
                                table.insert(validTargets, enemy)
                            end
                        end
                    end
                end
                -- Sort targets based on conditions and pick best
                if #validTargets > 0 then
                    table.sort(validTargets, function(a, b)
                        if cond2.sort then return cond2.sort(a, b) end
                        if cond1.sort then return cond1.sort(a, b) end
                        return false
                    end)
                    target = validTargets[1]
                end
            elseif passive.targetType == "self" then
                -- Self-targeting passives check conditions against self
                if not cond1.filter(pokemon, pokemon, M) then goto continue end
                if not cond2.filter(pokemon, pokemon, M) then goto continue end
                target = pokemon
            end
            
            if (pokemon.battlePP or 0) > 0 and target then
                pokemon.battlePP = pokemon.battlePP - 1
                
                -- For attack-type passives, set currentAction so Rough Skin/Rage can check category
                if passive.animationType == "attack" and passive.basePower and passive.basePower > 0 then
                    M.currentAction = {
                        user = pokemon,
                        target = target,
                        skill = {
                            name = passive.name,
                            category = "physical",  -- Attack passives are physical
                            moveType = passive.moveType or "normal",
                        }
                    }
                    
                    -- Trigger before_ally_attacked for target (this is where Protect triggers)
                    M.triggerBeforeAllyAttacked(target, pokemon)
                    
                    -- Check if target is protected (Protect triggered)
                    if target.isProtected then
                        target.isProtected = nil
                        target.protectedBy = nil
                        M.currentAction = nil
                        -- Still show the attack animation with a "blocked" message
                        local blockedMessage = pokemon.name .. " used " .. passive.name .. " but it was blocked!"
                        local hpChanges = {{pokemon = pokemon, newHP = pokemon.currentHP}}
                        M.queuePassiveAnimation(passive.animationType, pokemon, target, blockedMessage, hpChanges)
                        goto continue
                    end
                end
                
                local damageDealt, message = passive:execute(pokemon, target, 0, M)
                
                -- For attack passives that dealt damage, trigger after_ally_hit events
                if passive.animationType == "attack" and damageDealt and damageDealt > 0 and target.currentHP > 0 then
                    -- Trigger after_ally_hit for target's side (Rough Skin, Rage, etc.)
                    M.triggerAllyPassives("after_ally_hit", target, pokemon, damageDealt)
                end
                
                -- Clear current action
                M.currentAction = nil
                
                if message then
                    local hpChanges = {{pokemon = pokemon, newHP = pokemon.currentHP}}
                    -- Also track target HP changes for damage-dealing passives
                    if target and target ~= pokemon then
                        table.insert(hpChanges, {pokemon = target, newHP = target.currentHP})
                    end
                    -- Use passive animation for attack-type passives
                    if passive.animationType then
                        M.queuePassiveAnimation(passive.animationType, pokemon, target, message, hpChanges)
                    else
                        M.queueMessage(message, hpChanges)
                    end
                end
            end
            
            ::continue::
        end
    end
end

--------------------------------------------------
-- FORMATION HELPERS
--------------------------------------------------

local function getLivingPokemon(formation)
    local living = {}
    for i = 1, 6 do
        local pokemon = formation[i]
        if pokemon and pokemon.currentHP and pokemon.currentHP > 0 then
            table.insert(living, {pokemon = pokemon, slot = i})
        end
    end
    return living
end

local function getFrontMost(formation)
    -- Check front row first (slots 1-3)
    for i = 1, 3 do
        if formation[i] and formation[i].currentHP and formation[i].currentHP > 0 then
            return formation[i], i
        end
    end
    -- Then check back row (slots 4-6)
    for i = 4, 6 do
        if formation[i] and formation[i].currentHP and formation[i].currentHP > 0 then
            return formation[i], i
        end
    end
    return nil, nil
end

local function isFormationDefeated(formation)
    for i = 1, 6 do
        local pokemon = formation[i]
        if pokemon and pokemon.currentHP and pokemon.currentHP > 0 then
            return false
        end
    end
    return true
end

local function countLiving(formation)
    local count = 0
    for i = 1, 6 do
        local pokemon = formation[i]
        if pokemon and pokemon.currentHP and pokemon.currentHP > 0 then
            count = count + 1
        end
    end
    return count
end

M.getLivingPokemon = getLivingPokemon
M.getFrontMost = getFrontMost
M.isFormationDefeated = isFormationDefeated
M.countLiving = countLiving

--------------------------------------------------
-- BATTLE INITIALIZATION
--------------------------------------------------

function M.startBattle(player, enemyPokemon, isTrainer, trainerObj)
    M.active = true
    M.mode = "idle"
    M.player = player
    M.isTrainerBattle = isTrainer or false
    M.trainer = trainerObj
    M.trainerDefeated = false
    M.playerWhitedOut = false
    
    M.battleLog = {}
    M.logQueue = {}
    M.actionQueue = {}
    M.currentAction = nil
    M.actionTimer = 0
    M.turnNumber = 0
    M.roundNumber = 1
    M.battlePhase = "tactics"  -- Start in tactics mode
    M.waitingForZ = false
    M.awaitingClose = false
    
    -- Reset tactics state
    M.tacticsMode = true
    M.tacticsCursor = 1
    M.tacticsSelected = nil
    
    -- Clear formations
    M.playerFormation = {nil, nil, nil, nil, nil, nil}
    M.enemyFormation = {nil, nil, nil, nil, nil, nil}
    
    -- Reset EXP tracking
    M.defeatedEnemies = {}
    
    -- Helper to initialize AP/PP and stat stages for a Pokemon
    local function initBattlePoints(pokemon)
        if pokemon then
            pokemon.battleAP = M.defaultAP  -- Action Points remaining
            pokemon.battlePP = M.defaultPP  -- Passive Points remaining
            pokemon.displayHP = pokemon.currentHP  -- Display HP for synced animations
            initStatStages(pokemon)  -- Initialize stat stages to 0
            pokemon.isProtected = false  -- Reset protection status
            pokemon.protectedBy = nil
        end
    end
    
    -- Load player Pokemon into formation
    -- Use saved formation slots if available, otherwise pack sequentially
    if player and player.party then
        -- First pass: place Pokemon with saved formation slots
        local usedSlots = {}
        local placedPokemon = {}
        for i, pokemon in ipairs(player.party) do
            if pokemon and pokemon.currentHP and pokemon.currentHP > 0 then
                local savedSlot = pokemon.formationSlot
                if savedSlot and savedSlot >= 1 and savedSlot <= 6 and not usedSlots[savedSlot] then
                    initBattlePoints(pokemon)
                    M.playerFormation[savedSlot] = pokemon
                    usedSlots[savedSlot] = true
                    placedPokemon[pokemon] = true
                end
            end
        end
        
        -- Second pass: place remaining Pokemon in first available slots
        local nextSlot = 1
        for i, pokemon in ipairs(player.party) do
            if pokemon and pokemon.currentHP and pokemon.currentHP > 0 then
                -- Skip if already placed in first pass
                if not placedPokemon[pokemon] then
                    -- Find next available slot
                    while nextSlot <= 6 and usedSlots[nextSlot] do
                        nextSlot = nextSlot + 1
                    end
                    if nextSlot <= 6 then
                        initBattlePoints(pokemon)
                        M.playerFormation[nextSlot] = pokemon
                        pokemon.formationSlot = nextSlot  -- Save the slot
                        usedSlots[nextSlot] = true
                        nextSlot = nextSlot + 1
                    end
                end
            end
        end
    end
    
    -- Load enemy Pokemon into formation
    if type(enemyPokemon) == "table" then
        if enemyPokemon.speciesId or enemyPokemon.species then
            -- Single Pokemon
            initBattlePoints(enemyPokemon)
            M.enemyFormation[1] = enemyPokemon
        else
            -- Array of Pokemon
            local slot = 1
            for i, pokemon in ipairs(enemyPokemon) do
                if slot <= 6 and pokemon then
                    initBattlePoints(pokemon)
                    M.enemyFormation[slot] = pokemon
                    slot = slot + 1
                end
            end
        end
    end
    
    -- Log battle start
    local enemyCount = countLiving(M.enemyFormation)
    local playerCount = countLiving(M.playerFormation)
    
    if M.isTrainerBattle and M.trainer then
        M.queueMessage(M.trainer.name .. " wants to battle!")
    else
        local firstEnemy = getFrontMost(M.enemyFormation)
        if firstEnemy then
            M.queueMessage("A wild " .. firstEnemy.name .. " appeared!")
        end
    end
    
    M.queueMessage("Organize your formation! (" .. playerCount .. " vs " .. enemyCount .. ")")
end

-- Start a wild Pokemon battle (convenience function)
function M.startWildBattle(wildPokemon, player)
    M.startBattle(player, wildPokemon, false, nil)
end

-- Start a trainer battle
-- Can accept either a trainer ID (string) or a trainer object
function M.startTrainerBattle(trainerIdOrObj, player)
    local trainer = trainerIdOrObj
    
    -- If given a trainer ID string, create trainer from ID
    if type(trainerIdOrObj) == "string" then
        local ok, trainerMod = pcall(require, "trainer")
        if ok and trainerMod and trainerMod.Trainer then
            trainer = trainerMod.Trainer:new(trainerIdOrObj)
        else
            log.log("battle.startTrainerBattle - failed to load trainer module")
            return
        end
    end
    
    if not trainer then
        log.log("battle.startTrainerBattle - invalid trainer")
        return
    end
    
    local enemyParty = {}
    if trainer and trainer.party then
        for _, pokemon in ipairs(trainer.party) do
            table.insert(enemyParty, pokemon)
        end
    end
    M.startBattle(player, enemyParty, true, trainer)
end

--------------------------------------------------
-- MESSAGE SYSTEM
-- Messages can have associated HP changes that apply when the message is shown
-- This creates the visual effect of HP bars updating in sync with battle text
--------------------------------------------------

-- Queue a message with optional HP changes
-- hpChanges is an array of {pokemon, newHP} pairs to apply when message is shown
function M.queueMessage(msg, hpChanges)
    if msg and msg ~= "" then
        table.insert(M.logQueue, {
            text = msg,
            hpChanges = hpChanges or {}
        })
    end
end

-- Apply HP changes from a message
local function applyHPChanges(hpChanges)
    if not hpChanges then return end
    for _, change in ipairs(hpChanges) do
        if change.pokemon and change.newHP then
            change.pokemon.displayHP = change.newHP
        end
    end
end

-- Initialize display HP for a Pokemon (call at battle start)
local function initDisplayHP(pokemon)
    if pokemon then
        pokemon.displayHP = pokemon.currentHP
    end
end

function M.processMessageQueue()
    if #M.logQueue > 0 and not M.waitingForZ then
        local msgData = table.remove(M.logQueue, 1)
        local msg = type(msgData) == "table" and msgData.text or msgData
        local hpChanges = type(msgData) == "table" and msgData.hpChanges or nil
        local animation = type(msgData) == "table" and msgData.animation or nil
        
        -- Apply any HP changes associated with this message
        applyHPChanges(hpChanges)
        
        -- Start animation if this message has one attached
        if animation then
            M.startPassiveAnimation(animation)
        end
        
        table.insert(M.battleLog, msg)
        
        -- Trim log to max display lines (counting newlines in messages)
        local function countDisplayLines()
            local total = 0
            for _, m in ipairs(M.battleLog) do
                -- Count lines in this message
                local lines = 1
                for _ in string.gmatch(m, "\n") do
                    lines = lines + 1
                end
                total = total + lines
            end
            return total
        end
        
        while countDisplayLines() > M.maxLogLines and #M.battleLog > 1 do
            table.remove(M.battleLog, 1)
        end
        
        M.waitingForZ = true
        return true
    end
    return false
end

--------------------------------------------------
-- ACTION EXECUTION
--------------------------------------------------

-- Queue an action to be executed
function M.queueAction(action)
    table.insert(M.actionQueue, action)
end

-- Execute the next turn
function M.executeTurn()
    if M.mode ~= "idle" then return end
    
    M.turnNumber = M.turnNumber + 1
    M.mode = "executing"
    
    -- Gather all actions for this turn
    local actions = {}
    
    -- Player Pokemon actions (each living Pokemon with AP attacks)
    local playerLiving = getLivingPokemon(M.playerFormation)
    for _, data in ipairs(playerLiving) do
        -- Only act if Pokemon has AP remaining
        if (data.pokemon.battleAP or 0) > 0 then
            -- Get skill and target from loadout
            local activeSkill, target = getActiveSkillForAction(data.pokemon, M)
            if activeSkill and target then
                table.insert(actions, {
                    user = data.pokemon,
                    userSlot = data.slot,
                    target = target,
                    skill = activeSkill,
                    team = "player",
                    priority = activeSkill.priority or 0
                })
            end
        end
    end
    
    -- Enemy Pokemon actions
    local enemyLiving = getLivingPokemon(M.enemyFormation)
    for _, data in ipairs(enemyLiving) do
        -- Only act if Pokemon has AP remaining
        if (data.pokemon.battleAP or 0) > 0 then
            -- Get skill and target from loadout
            local activeSkill, target = getActiveSkillForAction(data.pokemon, M)
            if activeSkill and target then
                table.insert(actions, {
                    user = data.pokemon,
                    userSlot = data.slot,
                    target = target,
                    skill = activeSkill,
                    team = "enemy",
                    priority = activeSkill.priority or 0
                })
            end
        end
    end
    
    -- Sort by priority first, then by speed
    table.sort(actions, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        local speedA = (a.user.stats and a.user.stats.speed) or 10
        local speedB = (b.user.stats and b.user.stats.speed) or 10
        return speedA > speedB
    end)
    
    -- Queue all actions
    for _, action in ipairs(actions) do
        M.queueAction(action)
    end
    
    -- Start executing
    M.actionTimer = 0
end

-- Helper to get screen position for a Pokemon in formation
local function getSlotPosition(pokemon, isPlayer)
    local UI = require("ui")
    local screenW, screenH = UI.getGameScreenDimensions()
    
    local slotWidth = 70
    local slotHeight = 85
    local rowGap = 5
    local colGap = 8
    local logBoxHeight = 50
    local logBoxY = screenH - logBoxHeight - 5
    local formationAreaHeight = logBoxY - 30
    local formationAreaTop = 25
    local totalFormationHeight = slotHeight * 3 + rowGap * 2
    local formationStartY = formationAreaTop + (formationAreaHeight - totalFormationHeight) / 2
    
    local playerBackX = 10
    local playerFrontX = playerBackX + slotWidth + colGap
    local enemyFrontX = screenW - 10 - slotWidth * 2 - colGap
    local enemyBackX = screenW - 10 - slotWidth
    
    local formation = isPlayer and M.playerFormation or M.enemyFormation
    for i = 1, 6 do
        local p = formation[i]
        if p == pokemon then
            local x, y
            if isPlayer then
                if i <= 3 then
                    x = playerFrontX
                    y = formationStartY + (i - 1) * (slotHeight + rowGap)
                else
                    x = playerBackX
                    y = formationStartY + (i - 4) * (slotHeight + rowGap)
                end
            else
                if i <= 3 then
                    x = enemyFrontX
                    y = formationStartY + (i - 1) * (slotHeight + rowGap)
                else
                    x = enemyBackX
                    y = formationStartY + (i - 4) * (slotHeight + rowGap)
                end
            end
            return x + slotWidth / 2, y + slotHeight / 2, slotWidth, slotHeight
        end
    end
    return nil, nil, slotWidth, slotHeight
end

M.getSlotPosition = getSlotPosition

-- Start animation for an action
local function startActionAnimation(action)
    local userIsPlayer = action.team == "player"
    local userX, userY = getSlotPosition(action.user, userIsPlayer)
    local targetX, targetY = getSlotPosition(action.target, not userIsPlayer)
    
    if not userX or not targetX then
        -- Can't animate, just execute immediately
        return false
    end
    
    M.animating = true
    M.animAction = action
    M.animTimer = 0
    M.animStartX = userX
    M.animStartY = userY
    M.animTargetX = targetX
    M.animTargetY = targetY
    M.animCurrentX = userX
    M.animCurrentY = userY
    
    -- Check if this is a status move (use flash animation instead of move)
    if action.skill and action.skill.category == "status" then
        M.animPhase = "status_flash"
    else
        M.animPhase = "move_to"
    end
    
    return true
end

-- Execute the actual skill (called after animation)
local function executeAction(action)
    -- Store current action for passive checks (e.g., Rage checks if attack was physical)
    M.currentAction = action
    
    -- Apply attack boost if present
    local originalAttack = nil
    if action.user.battleAttackBoost and action.user.battleAttackBoost > 1 then
        if action.user.stats and action.user.stats.attack then
            originalAttack = action.user.stats.attack
            action.user.stats.attack = math.floor(action.user.stats.attack * action.user.battleAttackBoost)
        end
    end
    
    -- Trigger before passives (before the attack happens)
    M.triggerAllyPassives("before_ally_attack", action.user, action.target, 0)
    M.triggerEnemyPassives("before_enemy_attack", action.user, action.target, 0)
    
    -- Trigger before_ally_attacked for allies of target (this is where Protect triggers)
    M.triggerBeforeAllyAttacked(action.target, action.user)
    
    -- Check if target was protected (by Protect passive)
    if action.target.isProtected then
        action.target.isProtected = false
        local protector = action.target.protectedBy
        action.target.protectedBy = nil
        local protectorName = protector and protector.name or "an ally"
        M.queueMessage(action.target.name .. " was protected!")
        -- Restore original attack if modified
        if originalAttack then
            action.user.stats.attack = originalAttack
        end
        return
    end
    
    -- Trigger before_self_hit for target
    M.triggerBeforeSelfHit(action.target, action.user)
    
    -- Check if target evaded
    if action.target.evadedAttack then
        action.target.evadedAttack = nil
        M.queueMessage(action.target.name .. " evaded " .. action.user.name .. "'s attack!")
        -- Restore original attack if modified
        if originalAttack then
            action.user.stats.attack = originalAttack
        end
        return
    end
    
    -- Execute the skill - deals damage and returns message
    local damage, message = action.skill:execute(action.user, action.target, M)
    
    -- Queue the main attack message with HP changes for synced display
    if message then
        local hpChanges = {}
        -- Track target's HP change
        if action.target then
            table.insert(hpChanges, {pokemon = action.target, newHP = action.target.currentHP})
        end
        -- Track user's HP change (for skills that cost HP or self-damage)
        if action.user then
            table.insert(hpChanges, {pokemon = action.user, newHP = action.user.currentHP})
        end
        M.queueMessage(message, hpChanges)
    end
    
    -- NOW trigger after passives (after the attack message is queued)
    if damage and damage > 0 then
        -- Trigger after_ally_hit for allies of the hit Pokemon (Quick Heal, etc)
        M.triggerAllyPassives("after_ally_hit", action.target, action.user, damage)
        -- Trigger after_ally_attack for allies of the attacker (Pursuit, etc)
        M.triggerAllyPassives("after_ally_attack", action.user, action.target, damage)
        -- Trigger after_enemy_attack for enemies
        M.triggerEnemyPassives("after_enemy_attack", action.user, action.target, damage)
    end
    
    -- Restore original attack if modified
    if originalAttack then
        action.user.stats.attack = originalAttack
    end
    
    -- Clear current action after execution
    M.currentAction = nil
end

-- Process one action from the queue
function M.processNextAction()
    if #M.actionQueue == 0 then
        M.mode = "idle"
        M.checkBattleEnd()
        return false
    end
    
    local action = table.remove(M.actionQueue, 1)
    
    -- Skip if user is fainted or out of AP
    if action.user.currentHP <= 0 then
        return M.processNextAction()
    end
    
    if (action.user.battleAP or 0) <= 0 then
        return M.processNextAction()
    end
    
    -- Consume AP
    action.user.battleAP = (action.user.battleAP or 0) - 1
    
    -- Re-target if target is fainted
    if action.target.currentHP <= 0 then
        local newTarget
        if action.team == "player" then
            newTarget = getFrontMost(M.enemyFormation)
        else
            newTarget = getFrontMost(M.playerFormation)
        end
        
        if not newTarget then
            -- No valid target - check if battle should end before processing more actions
            local enemyDefeated = isFormationDefeated(M.enemyFormation)
            local playerDefeated = isFormationDefeated(M.playerFormation)
            if enemyDefeated or playerDefeated then
                -- Clear remaining actions and check battle end
                M.actionQueue = {}
                M.mode = "idle"
                M.checkBattleEnd()
                return false
            end
            return M.processNextAction()
        end
        action.target = newTarget
    end
    
    -- Start animation
    if not startActionAnimation(action) then
        -- No animation, execute immediately
        executeAction(action)
    end
    
    return true
end

local function teamHasAP(formation)
    for i = 1, 6 do
        local pokemon = formation[i]
        if pokemon and pokemon.currentHP and pokemon.currentHP > 0 then
            if (pokemon.battleAP or 0) > 0 then
                return true
            end
        end
    end
    return false
end

-- Track when an enemy Pokemon is defeated
function M.trackDefeatedEnemy(pokemon)
    if pokemon then
        table.insert(M.defeatedEnemies, {
            pokemon = pokemon,
            level = pokemon.level or 1,
            species = pokemon.species
        })
    end
end

-- Distribute EXP to surviving player Pokemon
function M.distributeExp()
    if #M.defeatedEnemies == 0 then return end
    
    -- Load Pokemon module for EXP calculation
    local ok, pmod = pcall(require, "pokemon")
    if not ok or not pmod then return end
    
    -- Get living player Pokemon
    local livingPlayers = {}
    for i = 1, 6 do
        local pokemon = M.playerFormation[i]
        if pokemon and pokemon.currentHP and pokemon.currentHP > 0 then
            table.insert(livingPlayers, pokemon)
        end
    end
    
    if #livingPlayers == 0 then return end
    
    -- Calculate total EXP from all defeated enemies
    local totalExp = 0
    for _, defeated in ipairs(M.defeatedEnemies) do
        -- Use base exp yield if available, otherwise estimate from level
        local baseExp = (defeated.species and defeated.species.baseExpYield) or (defeated.level * 10)
        local enemyLevel = defeated.level or 1
        -- Simple formula: (baseExp * level) / 7
        local exp = math.floor((baseExp * enemyLevel) / 7)
        totalExp = totalExp + math.max(1, exp)
    end
    
    -- Divide EXP among living Pokemon
    local expPerPokemon = math.floor(totalExp / #livingPlayers)
    if expPerPokemon < 1 then expPerPokemon = 1 end
    
    -- Give EXP to each living Pokemon
    for _, pokemon in ipairs(livingPlayers) do
        local pokeName = pokemon.nickname or pokemon.name or "Pokemon"
        M.queueMessage(pokeName .. " gained " .. expPerPokemon .. " EXP!")
        
        -- Apply EXP and check for level ups
        if pokemon.gainExp then
            local levelsGained, pendingEvolution = pokemon:gainExp(expPerPokemon)
            
            -- Queue level up messages
            if levelsGained and #levelsGained > 0 then
                for _, newLevel in ipairs(levelsGained) do
                    M.queueMessage(pokeName .. " grew to level " .. newLevel .. "!")
                end
            end
            
            -- Handle pending evolution (just notify for now)
            if pendingEvolution then
                M.queueMessage(pokeName .. " is ready to evolve into " .. pendingEvolution .. "!")
            end
        end
    end
end

function M.checkBattleEnd()
    local playerDefeated = isFormationDefeated(M.playerFormation)
    local enemyDefeated = isFormationDefeated(M.enemyFormation)
    
    if enemyDefeated then
        M.battlePhase = "end"
        M.queueMessage("You won!")
        -- Distribute EXP to surviving player Pokemon
        M.distributeExp()
        if M.isTrainerBattle and M.trainer then
            M.trainerDefeated = true
        end
        M.awaitingClose = true
    elseif playerDefeated then
        M.battlePhase = "end"
        M.queueMessage("You lost...")
        M.playerWhitedOut = true
        M.awaitingClose = true
    else
        -- Check if both teams are out of AP (round end)
        local playerHasAP = teamHasAP(M.playerFormation)
        local enemyHasAP = teamHasAP(M.enemyFormation)
        
        if not playerHasAP and not enemyHasAP then
            -- Trigger round end passives (like Quick Heal)
            M.triggerRoundEndPassives()
            
            -- Round ended - give player choice to continue or run
            M.battlePhase = "round_end"
            M.queueMessage("Round " .. M.roundNumber .. " complete!")
        end
    end
end

-- Start a new round - restore all AP/PP for living Pokemon
function M.startNewRound()
    M.roundNumber = M.roundNumber + 1
    M.battlePhase = "start"
    M.mode = "idle"
    
    -- Restore AP/PP for all living Pokemon in both formations
    -- Also reset per-round flags like keenEyeUsedThisRound
    for i = 1, 6 do
        local pokemon = M.playerFormation[i]
        if pokemon and pokemon.currentHP and pokemon.currentHP > 0 then
            pokemon.battleAP = M.defaultAP
            pokemon.battlePP = M.defaultPP
            pokemon.keenEyeUsedThisRound = false
            pokemon.guaranteedHit = false
        end
    end
    for i = 1, 6 do
        local pokemon = M.enemyFormation[i]
        if pokemon and pokemon.currentHP and pokemon.currentHP > 0 then
            pokemon.battleAP = M.defaultAP
            pokemon.battlePP = M.defaultPP
            pokemon.keenEyeUsedThisRound = false
            pokemon.guaranteedHit = false
        end
    end
    
    M.queueMessage("Round " .. M.roundNumber .. " - Fight!")
    
    -- Trigger round start passives (like Regenerate)
    M.triggerRoundStartPassives()
end

--------------------------------------------------
-- END BATTLE
--------------------------------------------------

function M.endBattle()
    M.active = false
    M.mode = "idle"
    M.playerFormation = {nil, nil, nil, nil, nil, nil}
    M.enemyFormation = {nil, nil, nil, nil, nil, nil}
    M.battleLog = {}
    M.logQueue = {}
    M.actionQueue = {}
    
    if M.playerWhitedOut and M.whiteoutCallback then
        M.whiteoutCallback(M.player)
    end
end

--------------------------------------------------
-- UPDATE
--------------------------------------------------

function M.update(dt)
    if not M.active then return end
    
    -- Update attack animation
    if M.animating and M.animAction then
        M.animTimer = M.animTimer + dt
        local progress = math.min(1, M.animTimer / M.animDuration)
        
        if M.animPhase == "move_to" then
            -- Lerp from start to target
            M.animCurrentX = M.animStartX + (M.animTargetX - M.animStartX) * progress
            M.animCurrentY = M.animStartY + (M.animTargetY - M.animStartY) * progress
            
            if progress >= 1 then
                -- Hit the target - execute the skill
                executeAction(M.animAction)
                M.animPhase = "move_back"
                M.animTimer = 0
            end
        elseif M.animPhase == "move_back" then
            -- Lerp from target back to start
            M.animCurrentX = M.animTargetX + (M.animStartX - M.animTargetX) * progress
            M.animCurrentY = M.animTargetY + (M.animStartY - M.animTargetY) * progress
            
            if progress >= 1 then
                -- Animation complete
                M.animating = false
                M.animAction = nil
                M.animPhase = "none"
            end
        elseif M.animPhase == "status_flash" then
            -- Status move animation: flash the target without moving the user
            -- Duration is 0.3 seconds for the flash effect
            local statusDuration = 0.3
            local statusProgress = math.min(1, M.animTimer / statusDuration)
            
            if statusProgress >= 0.5 and not M.statusActionExecuted then
                -- Execute the skill at the midpoint of the flash
                executeAction(M.animAction)
                M.statusActionExecuted = true
            end
            
            if statusProgress >= 1 then
                -- Animation complete
                M.animating = false
                M.animAction = nil
                M.animPhase = "none"
                M.statusActionExecuted = nil
            end
        end
        return
    end
    
    -- Update passive animation
    if M.passiveAnimating then
        M.passiveAnimTimer = M.passiveAnimTimer + dt
        M.passiveFlashTimer = M.passiveFlashTimer + dt
        local progress = math.min(1, M.passiveAnimTimer / M.passiveAnimDuration)
        
        if M.passiveAnimType == "heal" then
            -- Heal animation: healer bounces up then down, target flashes green
            if M.passiveAnimPhase == "bounce_up" then
                -- Move up by 10 pixels
                M.passiveAnimUserCurrentY = M.passiveAnimUserStartY - (10 * progress)
                if progress >= 1 then
                    M.passiveAnimPhase = "bounce_down"
                    M.passiveAnimTimer = 0
                end
            elseif M.passiveAnimPhase == "bounce_down" then
                -- Move back down
                M.passiveAnimUserCurrentY = M.passiveAnimUserStartY - 10 + (10 * progress)
                if progress >= 1 then
                    M.passiveAnimPhase = "flash"
                    M.passiveAnimTimer = 0
                    M.passiveAnimDuration = 0.3
                end
            elseif M.passiveAnimPhase == "flash" then
                -- Target flashes green (handled in draw)
                if progress >= 1 then
                    M.passiveAnimating = false
                    M.passiveAnimPhase = "none"
                    -- Don't auto-start next - let message queue handle it
                end
            end
        elseif M.passiveAnimType == "guard" then
            -- Guard animation: guardian moves to ally, then flash
            if M.passiveAnimPhase == "move_to_ally" then
                -- Get target position
                local isPlayer = M.getFormationSide(M.passiveAnimTarget) == "player"
                local targetX, targetY = M.getSlotPosition(M.passiveAnimTarget, isPlayer)
                if targetX then
                    M.passiveAnimUserCurrentX = M.passiveAnimUserStartX + (targetX - M.passiveAnimUserStartX) * progress
                    M.passiveAnimUserCurrentY = M.passiveAnimUserStartY + (targetY - M.passiveAnimUserStartY) * progress
                end
                if progress >= 1 then
                    M.passiveAnimPhase = "guard_flash"
                    M.passiveAnimTimer = 0
                    M.passiveAnimDuration = 0.25
                end
            elseif M.passiveAnimPhase == "guard_flash" then
                -- Blue flash on both (handled in draw)
                if progress >= 1 then
                    M.passiveAnimPhase = "move_back"
                    M.passiveAnimTimer = 0
                    M.passiveAnimDuration = 0.15
                end
            elseif M.passiveAnimPhase == "move_back" then
                -- Move guardian back to original position
                local isPlayer = M.getFormationSide(M.passiveAnimTarget) == "player"
                local targetX, targetY = M.getSlotPosition(M.passiveAnimTarget, isPlayer)
                if targetX then
                    M.passiveAnimUserCurrentX = targetX + (M.passiveAnimUserStartX - targetX) * progress
                    M.passiveAnimUserCurrentY = targetY + (M.passiveAnimUserStartY - targetY) * progress
                end
                if progress >= 1 then
                    M.passiveAnimating = false
                    M.passiveAnimPhase = "none"
                    -- Don't auto-start next - let message queue handle it
                end
            end
        elseif M.passiveAnimType == "attack" then
            -- Attack animation for passives like Pursuit: move to target, hit, move back
            if M.passiveAnimPhase == "attack_move_to" then
                -- Lerp from user position to target position
                M.passiveAnimUserCurrentX = M.passiveAnimUserStartX + (M.passiveAnimTargetStartX - M.passiveAnimUserStartX) * progress
                M.passiveAnimUserCurrentY = M.passiveAnimUserStartY + (M.passiveAnimTargetStartY - M.passiveAnimUserStartY) * progress
                if progress >= 1 then
                    M.passiveAnimPhase = "attack_hit"
                    M.passiveAnimTimer = 0
                    M.passiveAnimDuration = 0.15
                end
            elseif M.passiveAnimPhase == "attack_hit" then
                -- Brief pause at target with hit effect (handled in draw)
                if progress >= 1 then
                    M.passiveAnimPhase = "attack_move_back"
                    M.passiveAnimTimer = 0
                    M.passiveAnimDuration = 0.15
                end
            elseif M.passiveAnimPhase == "attack_move_back" then
                -- Lerp back to original position
                M.passiveAnimUserCurrentX = M.passiveAnimTargetStartX + (M.passiveAnimUserStartX - M.passiveAnimTargetStartX) * progress
                M.passiveAnimUserCurrentY = M.passiveAnimTargetStartY + (M.passiveAnimUserStartY - M.passiveAnimTargetStartY) * progress
                if progress >= 1 then
                    M.passiveAnimating = false
                    M.passiveAnimPhase = "none"
                    -- Don't auto-start next - let message queue handle it
                end
            end
        elseif M.passiveAnimType == "buff" then
            -- Buff animation: flash effect on user
            M.passiveFlashTimer = M.passiveFlashTimer + dt
            if M.passiveAnimPhase == "buff_flash" then
                -- Just a timed flash effect (handled in draw)
                if progress >= 1 then
                    M.passiveAnimating = false
                    M.passiveAnimPhase = "none"
                    -- Don't auto-start next - let message queue handle it
                end
            end
        elseif M.passiveAnimType == "debuff" then
            -- Debuff animation: flash effect on target
            M.passiveFlashTimer = M.passiveFlashTimer + dt
            if M.passiveAnimPhase == "debuff_flash" then
                if progress >= 1 then
                    M.passiveAnimating = false
                    M.passiveAnimPhase = "none"
                    -- Don't auto-start next - let message queue handle it
                end
            end
        elseif M.passiveAnimType == "recoil" then
            -- Recoil animation: red flash on target (attacker taking recoil damage)
            M.passiveFlashTimer = M.passiveFlashTimer + dt
            if M.passiveAnimPhase == "recoil_flash" then
                if progress >= 1 then
                    M.passiveAnimating = false
                    M.passiveAnimPhase = "none"
                    -- Don't auto-start next - let message queue handle it
                end
            end
        else
            -- Unknown type, just finish
            M.passiveAnimating = false
            M.passiveAnimPhase = "none"
        end
        return
    end
    
    -- Process message queue (animations are now started when messages are shown)
    if M.waitingForZ then
        -- Waiting for player to press Z to continue
        return
    end
    
    if M.processMessageQueue() then
        return
    end
    
    -- If awaiting close, don't process actions
    if M.awaitingClose then
        return
    end
    
    -- Process actions with delay
    if M.mode == "executing" then
        M.actionTimer = M.actionTimer + dt
        if M.actionTimer >= M.actionDelay then
            M.actionTimer = 0
            M.processNextAction()
        end
    end
end

--------------------------------------------------
-- INPUT HANDLING
--------------------------------------------------

-- Handle skill picker input (selecting skill/condition1/condition2)
local function handleSkillPickerInput(key)
    local listItems = {}
    
    if M.skillEditField == 1 then
        -- Skill picker - show only skills this Pokemon knows
        table.insert(listItems, {id = nil, name = "(Empty)"})
        
        -- Get the species ID and level for skill lookups
        local speciesId = M.skillEditPokemon.speciesId or 
                         (M.skillEditPokemon.species and M.skillEditPokemon.species.name and 
                          M.skillEditPokemon.species.name:lower():gsub(" ", "_"))
        local level = M.skillEditPokemon.level or 5
        
        -- Get known skills for this Pokemon
        local knownSkills = SkillsModule.getKnownSkills(speciesId or "unknown", level)
        
        for _, skillId in ipairs(knownSkills) do
            local skill = SkillsModule.getSkillById(skillId)
            if skill then
                table.insert(listItems, skill)
            end
        end
    elseif M.skillEditField == 2 or M.skillEditField == 3 then
        -- Condition picker - two-step: category first, then conditions
        if M.skillPickerMode == "category" then
            -- Show categories
            for _, cat in ipairs(ConditionCategories) do
                table.insert(listItems, cat)
            end
        else
            -- Show conditions in selected category
            local conditions = getConditionsByCategory(M.skillPickerCategory)
            for _, cond in ipairs(conditions) do
                table.insert(listItems, cond)
            end
        end
    end
    
    if key == "up" then
        M.skillPickerCursor = M.skillPickerCursor - 1
        if M.skillPickerCursor < 1 then M.skillPickerCursor = #listItems end
        return true
    elseif key == "down" then
        M.skillPickerCursor = M.skillPickerCursor + 1
        if M.skillPickerCursor > #listItems then M.skillPickerCursor = 1 end
        return true
    elseif key == "z" or key == "return" then
        local selected = listItems[M.skillPickerCursor]
        local loadout = getOrCreateLoadout(M.skillEditPokemon)
        
        -- Ensure slot exists
        if not loadout[M.skillEditSlot] then
            loadout[M.skillEditSlot] = {skill = nil, condition1 = "none", condition2 = "none"}
        end
        
        if M.skillEditField == 1 then
            -- Skill selected
            loadout[M.skillEditSlot].skill = selected.id
            M.skillPickerOpen = false
            M.skillPickerCursor = 1
        elseif M.skillPickerMode == "category" then
            -- Category selected - show conditions in that category
            M.skillPickerCategory = selected.id
            M.skillPickerMode = "list"
            M.skillPickerCursor = 1
        else
            -- Condition selected
            if M.skillEditField == 2 then
                loadout[M.skillEditSlot].condition1 = selected.id
            elseif M.skillEditField == 3 then
                loadout[M.skillEditSlot].condition2 = selected.id
            end
            M.skillPickerOpen = false
            M.skillPickerCursor = 1
            M.skillPickerMode = "category"
            M.skillPickerCategory = nil
        end
        return true
    elseif key == "x" or key == "escape" then
        if M.skillPickerMode == "list" and (M.skillEditField == 2 or M.skillEditField == 3) then
            -- Go back to category selection
            M.skillPickerMode = "category"
            M.skillPickerCategory = nil
            M.skillPickerCursor = 1
        else
            -- Close picker
            M.skillPickerOpen = false
            M.skillPickerCursor = 1
            M.skillPickerMode = "category"
            M.skillPickerCategory = nil
        end
        return true
    end
    
    return false
end

-- Handle skill edit mode input
local function handleSkillEditInput(key)
    if M.skillPickerOpen then
        return handleSkillPickerInput(key)
    end
    
    local loadout = getOrCreateLoadout(M.skillEditPokemon)
    local maxSlots = M.maxSkillSlots
    
    if key == "up" then
        M.skillEditSlot = M.skillEditSlot - 1
        if M.skillEditSlot < 1 then M.skillEditSlot = maxSlots end
        return true
    elseif key == "down" then
        M.skillEditSlot = M.skillEditSlot + 1
        if M.skillEditSlot > maxSlots then M.skillEditSlot = 1 end
        return true
    elseif key == "left" then
        M.skillEditField = M.skillEditField - 1
        if M.skillEditField < 1 then M.skillEditField = 3 end
        return true
    elseif key == "right" then
        M.skillEditField = M.skillEditField + 1
        if M.skillEditField > 3 then M.skillEditField = 1 end
        return true
    elseif key == "z" or key == "return" then
        -- Open picker for current field
        M.skillPickerOpen = true
        M.skillPickerCursor = 1
        -- For condition fields, start with category selection
        if M.skillEditField == 2 or M.skillEditField == 3 then
            M.skillPickerMode = "category"
            M.skillPickerCategory = nil
        else
            M.skillPickerMode = "list"
        end
        return true
    elseif key == "x" or key == "escape" then
        -- Exit skill edit mode
        M.skillEditMode = false
        M.skillEditPokemon = nil
        M.skillEditSlot = 1
        M.skillEditField = 1
        return true
    end
    
    return false
end

-- Handle tactics mode navigation
local function handleTacticsInput(key)
    -- If in skill edit mode, handle that separately
    if M.skillEditMode then
        return handleSkillEditInput(key)
    end
    
    -- Navigation in tactics mode
    -- Layout: Back row (4,5,6) on left, Front row (1,2,3) on right
    -- Cursor positions: 1-6 for player formation
    
    if key == "up" then
        -- Move up in current column
        if M.tacticsCursor == 2 then M.tacticsCursor = 1
        elseif M.tacticsCursor == 3 then M.tacticsCursor = 2
        elseif M.tacticsCursor == 5 then M.tacticsCursor = 4
        elseif M.tacticsCursor == 6 then M.tacticsCursor = 5
        end
        return true
    elseif key == "down" then
        -- Move down in current column
        if M.tacticsCursor == 1 then M.tacticsCursor = 2
        elseif M.tacticsCursor == 2 then M.tacticsCursor = 3
        elseif M.tacticsCursor == 4 then M.tacticsCursor = 5
        elseif M.tacticsCursor == 5 then M.tacticsCursor = 6
        end
        return true
    elseif key == "left" then
        -- Move from front row to back row
        if M.tacticsCursor == 1 then M.tacticsCursor = 4
        elseif M.tacticsCursor == 2 then M.tacticsCursor = 5
        elseif M.tacticsCursor == 3 then M.tacticsCursor = 6
        end
        return true
    elseif key == "right" then
        -- Move from back row to front row
        if M.tacticsCursor == 4 then M.tacticsCursor = 1
        elseif M.tacticsCursor == 5 then M.tacticsCursor = 2
        elseif M.tacticsCursor == 6 then M.tacticsCursor = 3
        end
        return true
    elseif key == "z" or key == "return" then
        -- Select or swap
        if M.tacticsSelected == nil then
            -- Select this slot (even if empty, for swapping)
            M.tacticsSelected = M.tacticsCursor
        else
            -- Swap the two slots
            local slot1 = M.tacticsSelected
            local slot2 = M.tacticsCursor
            
            if slot1 ~= slot2 then
                local temp = M.playerFormation[slot1]
                M.playerFormation[slot1] = M.playerFormation[slot2]
                M.playerFormation[slot2] = temp
                
                -- Update saved formation slots on each Pokemon
                if M.playerFormation[slot1] then
                    M.playerFormation[slot1].formationSlot = slot1
                end
                if M.playerFormation[slot2] then
                    M.playerFormation[slot2].formationSlot = slot2
                end
                
                -- Show swap message
                M.queueMessage("Swapped positions!")
            end
            
            M.tacticsSelected = nil
        end
        return true
    elseif key == "c" then
        -- Open skill edit mode for the hovered Pokemon
        local hoveredPokemon = M.playerFormation[M.tacticsCursor]
        if hoveredPokemon then
            M.skillEditMode = true
            M.skillEditPokemon = hoveredPokemon
            M.skillEditSlot = 1
            M.skillEditField = 1
            M.skillPickerOpen = false
        end
        return true
    elseif key == "x" or key == "escape" then
        if M.tacticsSelected then
            -- Cancel selection
            M.tacticsSelected = nil
        else
            -- Exit tactics mode and start battle/round
            M.tacticsMode = false
            if M.tacticsFromRoundEnd then
                -- Coming from round end - start the new round properly
                M.tacticsFromRoundEnd = false
                M.startNewRound()
            else
                -- Initial battle start (Round 1)
                M.battlePhase = "start"
                M.queueMessage("Battle Start!")
                -- Trigger round start passives for round 1 (Quick Attack, Intimidate, etc.)
                M.triggerRoundStartPassives()
            end
        end
        return true
    end
    
    return false
end

function M.keypressed(key)
    if not M.active then return false end
    
    -- Handle tactics mode separately
    if M.tacticsMode and M.battlePhase == "tactics" then
        return handleTacticsInput(key)
    end
    
    if key == "z" or key == "return" then
        if M.waitingForZ then
            M.waitingForZ = false
            
            -- Check if we should close battle
            if M.awaitingClose and #M.logQueue == 0 then
                M.endBattle()
                return true
            end
            return true
        end
        
        -- At round end, Z opens tactics mode for reorganizing
        if M.mode == "idle" and M.battlePhase == "round_end" then
            M.tacticsMode = true
            M.battlePhase = "tactics"
            M.tacticsCursor = 1
            M.tacticsSelected = nil
            M.tacticsFromRoundEnd = true  -- Mark that we came from round end
            M.queueMessage("Organize your formation for the next round!")
            return true
        end
        
        -- Start executing if idle and not at end
        if M.mode == "idle" and M.battlePhase ~= "end" and M.battlePhase ~= "round_end" and M.battlePhase ~= "tactics" then
            M.executeTurn()
            return true
        end
    end
    
    if key == "x" or key == "escape" then
        -- At round end, X tries to run (always succeeds at round end)
        if M.battlePhase == "round_end" and not M.isTrainerBattle then
            M.queueMessage("Got away safely!")
            M.awaitingClose = true
            return true
        end
        
        -- Try to run from wild battles during normal play
        if not M.isTrainerBattle and M.mode == "idle" and M.battlePhase ~= "end" and M.battlePhase ~= "tactics" then
            local escaped = math.random(1, 100) <= 50 -- 50% chance to escape
            if escaped then
                M.queueMessage("Got away safely!")
                M.awaitingClose = true
            else
                M.queueMessage("Can't escape!")
            end
            return true
        end
    end
    
    return false
end

--------------------------------------------------
-- DRAWING
--------------------------------------------------

-- Helper to load sprites
local function loadSprite(spritePath)
    if not spritePath then return nil end
    if spriteCache[spritePath] then return spriteCache[spritePath] end
    
    local success, image = pcall(love.graphics.newImage, spritePath)
    if success and image then
        spriteCache[spritePath] = image
        return image
    end
    return nil
end

-- Draw a Pokemon sprite
local function drawPokemonSprite(pokemon, x, y, width, height, isBackSprite)
    if not pokemon or not pokemon.species or not pokemon.species.sprite then
        -- Draw placeholder
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.rectangle("fill", x, y, width, height)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    
    local spritePath = isBackSprite and pokemon.species.sprite.back or pokemon.species.sprite.front
    local image = loadSprite(spritePath)
    
    if image then
        local imgWidth = image:getWidth()
        local imgHeight = image:getHeight()
        local scaleX = width / imgWidth
        local scaleY = height / imgHeight
        local scale = math.min(scaleX, scaleY)
        
        local displayWidth = imgWidth * scale
        local displayHeight = imgHeight * scale
        local spriteX = x + (width - displayWidth) / 2
        local spriteY = y + (height - displayHeight) / 2
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, spriteX, spriteY, 0, scale, scale)
    else
        -- Placeholder if no sprite
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.rectangle("fill", x, y, width, height)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.print(pokemon.name or "???", x + 5, y + height/2 - 8)
    end
end

-- Draw HP bar
-- Uses displayHP if available for synced message/HP display, otherwise uses currentHP
local function drawHPBar(pokemon, x, y, width, height)
    if not pokemon then return end
    
    local maxHP = (pokemon.stats and pokemon.stats.hp) or 100
    -- Use displayHP for visual display (synced with messages), fallback to currentHP
    local displayHP = pokemon.displayHP or pokemon.currentHP or 0
    local hpPercent = displayHP / maxHP
    
    -- Background
    love.graphics.setColor(0.2, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", x, y, width, height)
    
    -- HP bar color based on percentage
    if hpPercent > 0.5 then
        love.graphics.setColor(0.2, 0.8, 0.3, 1)
    elseif hpPercent > 0.25 then
        love.graphics.setColor(0.9, 0.8, 0.2, 1)
    else
        love.graphics.setColor(0.9, 0.2, 0.2, 1)
    end
    
    love.graphics.rectangle("fill", x, y, width * math.max(0, hpPercent), height)
    
    -- Border
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", x, y, width, height)
end

-- Draw stat stage indicators as small arrows/icons
local function drawStatStageIndicators(pokemon, x, y, width)
    if not pokemon or not pokemon.statStages then return end
    
    local stages = pokemon.statStages
    local indicators = {}
    
    -- Collect all modified stats
    if stages.attack and stages.attack ~= 0 then
        table.insert(indicators, {stat = "Atk", stage = stages.attack, color = {1, 0.3, 0.3}})  -- Red
    end
    if stages.defense and stages.defense ~= 0 then
        table.insert(indicators, {stat = "Def", stage = stages.defense, color = {0.3, 0.6, 1}})  -- Blue
    end
    if stages.special_attack and stages.special_attack ~= 0 then
        table.insert(indicators, {stat = "SpA", stage = stages.special_attack, color = {1, 0.5, 1}})  -- Magenta
    end
    if stages.special_defense and stages.special_defense ~= 0 then
        table.insert(indicators, {stat = "SpD", stage = stages.special_defense, color = {0.5, 1, 0.5}})  -- Green
    end
    if stages.speed and stages.speed ~= 0 then
        table.insert(indicators, {stat = "Spd", stage = stages.speed, color = {1, 1, 0.3}})  -- Yellow
    end
    
    if #indicators == 0 then return end
    
    -- Draw indicators stacked vertically on the right side of the slot
    local indicatorHeight = 10
    local indicatorWidth = 22
    local startY = y
    
    for i, ind in ipairs(indicators) do
        if i > 3 then break end  -- Max 3 visible at once
        local indY = startY + (i - 1) * (indicatorHeight + 2)
        local indX = x + width - indicatorWidth - 2
        
        -- Background
        local bgColor = ind.stage > 0 and {0.1, 0.3, 0.1} or {0.3, 0.1, 0.1}
        love.graphics.setColor(bgColor[1], bgColor[2], bgColor[3], 0.8)
        love.graphics.rectangle("fill", indX, indY, indicatorWidth, indicatorHeight, 2, 2)
        
        -- Border with stat color
        love.graphics.setColor(ind.color[1], ind.color[2], ind.color[3], 0.9)
        love.graphics.rectangle("line", indX, indY, indicatorWidth, indicatorHeight, 2, 2)
        
        -- Draw arrow and number
        love.graphics.setColor(1, 1, 1, 1)
        local arrow = ind.stage > 0 and "+" or ""
        local stageText = arrow .. tostring(ind.stage)
        love.graphics.print(stageText, indX + 2, indY + 1, 0, 0.7, 0.7)
    end
    
    -- If more than 3 modified stats, show "..."
    if #indicators > 3 then
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.print("...", x + width - 12, startY + 3 * (indicatorHeight + 2), 0, 0.6, 0.6)
    end
end

-- Draw AP/PP indicators as small circles/pips
local function drawPointIndicators(pokemon, x, y, width)
    if not pokemon then return end
    
    local ap = pokemon.battleAP or 0
    local pp = pokemon.battlePP or 0
    local maxAP = M.defaultAP
    local maxPP = M.defaultPP
    
    local pipSize = 6
    local pipGap = 3
    local startX = x
    
    -- Draw AP pips (blue)
    for i = 1, maxAP do
        local pipX = startX + (i - 1) * (pipSize + pipGap)
        if i <= ap then
            love.graphics.setColor(0.2, 0.5, 1, 1)  -- Filled blue
        else
            love.graphics.setColor(0.3, 0.3, 0.4, 1)  -- Empty gray
        end
        love.graphics.circle("fill", pipX + pipSize/2, y + pipSize/2, pipSize/2)
        love.graphics.setColor(0.1, 0.1, 0.2, 1)
        love.graphics.circle("line", pipX + pipSize/2, y + pipSize/2, pipSize/2)
    end
    
    -- Draw PP pips (orange) after AP pips
    local ppStartX = startX + maxAP * (pipSize + pipGap) + 5
    for i = 1, maxPP do
        local pipX = ppStartX + (i - 1) * (pipSize + pipGap)
        if i <= pp then
            love.graphics.setColor(1, 0.6, 0.2, 1)  -- Filled orange
        else
            love.graphics.setColor(0.3, 0.3, 0.4, 1)  -- Empty gray
        end
        love.graphics.circle("fill", pipX + pipSize/2, y + pipSize/2, pipSize/2)
        love.graphics.setColor(0.1, 0.1, 0.2, 1)
        love.graphics.circle("line", pipX + pipSize/2, y + pipSize/2, pipSize/2)
    end
end

-- Draw a formation slot with optional highlighting for tactics mode
local function drawFormationSlot(pokemon, x, y, width, height, isPlayer, slotIndex)
    -- Check if this slot is highlighted in tactics mode (only for player formation)
    local isCursor = isPlayer and M.tacticsMode and M.battlePhase == "tactics" and slotIndex == M.tacticsCursor
    local isSelected = isPlayer and M.tacticsMode and M.battlePhase == "tactics" and slotIndex == M.tacticsSelected
    
    -- Draw slot background
    if isSelected then
        -- Selected slot - gold highlight
        love.graphics.setColor(1, 0.8, 0.2, 0.7)
        love.graphics.rectangle("fill", x, y, width, height, 5, 5)
        love.graphics.setColor(1, 0.9, 0.3, 1)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", x, y, width, height, 5, 5)
        love.graphics.setLineWidth(1)
    elseif isCursor then
        -- Cursor hovering - cyan highlight
        love.graphics.setColor(0.2, 0.8, 1, 0.5)
        love.graphics.rectangle("fill", x, y, width, height, 5, 5)
        love.graphics.setColor(0.3, 0.9, 1, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, width, height, 5, 5)
        love.graphics.setLineWidth(1)
    else
        love.graphics.setColor(0.3, 0.3, 0.4, 0.5)
        love.graphics.rectangle("fill", x, y, width, height, 5, 5)
        love.graphics.setColor(0.5, 0.5, 0.6, 1)
        love.graphics.rectangle("line", x, y, width, height, 5, 5)
    end
    
    if pokemon then
        -- Draw Pokemon sprite (adjusted for AP/PP indicators)
        local spriteHeight = height - 40
        drawPokemonSprite(pokemon, x + 5, y + 5, width - 10, spriteHeight, isPlayer)
        
        -- Draw stat stage indicators (top-right corner of slot)
        drawStatStageIndicators(pokemon, x, y + 5, width - 5)
        
        -- Draw AP/PP indicators
        drawPointIndicators(pokemon, x + 5, y + height - 38, width - 10)
        
        -- Draw HP bar
        drawHPBar(pokemon, x + 5, y + height - 18, width - 10, 8)
        
        -- Draw name (small)
        love.graphics.setColor(1, 1, 1, 1)
        local name = pokemon.nickname or pokemon.name or "???"
        if #name > 8 then name = name:sub(1, 7) .. "." end
        love.graphics.print(name, x + 5, y + height - 30)
    else
        -- Empty slot indicator in tactics mode
        if M.tacticsMode and M.battlePhase == "tactics" then
            love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
            love.graphics.printf("Empty", x, y + height/2 - 8, width, "center")
        end
    end
end

function M.draw()
    if not M.active then return end
    
    local screenW, screenH = UI.getGameScreenDimensions()
    
    -- Draw background
    love.graphics.setColor(0.85, 0.9, 0.85, 1)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)
    
    -- Formation layout constants (left/right layout)
    local slotWidth = 70
    local slotHeight = 85
    local rowGap = 5
    local colGap = 8
    
    -- Log box at bottom
    local logBoxHeight = 50
    local logBoxY = screenH - logBoxHeight - 5
    
    -- Available height for formations (above log box)
    local formationAreaHeight = logBoxY - 30
    local formationAreaTop = 25
    
    -- Center formations vertically in available area
    local totalFormationHeight = slotHeight * 3 + rowGap * 2
    local formationStartY = formationAreaTop + (formationAreaHeight - totalFormationHeight) / 2
    
    -- Player formation on LEFT side
    -- Back row (slots 4-6) on far left, Front row (slots 1-3) closer to center
    local playerBackX = 10
    local playerFrontX = playerBackX + slotWidth + colGap
    
    -- Enemy formation on RIGHT side
    -- Front row (slots 1-3) closer to center, Back row (slots 4-6) on far right
    local enemyFrontX = screenW - 10 - slotWidth * 2 - colGap
    local enemyBackX = screenW - 10 - slotWidth
    
    -- Draw labels
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Player", playerBackX, formationStartY - 18)
    love.graphics.print("Enemy", enemyFrontX, formationStartY - 18)
    
    -- Draw player formation (LEFT side)
    -- Back row (slots 4-6)
    for i = 4, 6 do
        local row = i - 3  -- 1, 2, 3
        local y = formationStartY + (row - 1) * (slotHeight + rowGap)
        drawFormationSlot(M.playerFormation[i], playerBackX, y, slotWidth, slotHeight, true, i)
    end
    
    -- Front row (slots 1-3)
    for i = 1, 3 do
        local y = formationStartY + (i - 1) * (slotHeight + rowGap)
        drawFormationSlot(M.playerFormation[i], playerFrontX, y, slotWidth, slotHeight, true, i)
    end
    
    -- Draw enemy formation (RIGHT side)
    -- Front row (slots 1-3)
    for i = 1, 3 do
        local y = formationStartY + (i - 1) * (slotHeight + rowGap)
        drawFormationSlot(M.enemyFormation[i], enemyFrontX, y, slotWidth, slotHeight, false, nil)
    end
    
    -- Back row (slots 4-6)
    for i = 4, 6 do
        local row = i - 3  -- 1, 2, 3
        local y = formationStartY + (row - 1) * (slotHeight + rowGap)
        drawFormationSlot(M.enemyFormation[i], enemyBackX, y, slotWidth, slotHeight, false, nil)
    end
    
    -- Draw VS indicator in center
    love.graphics.setColor(0.8, 0.2, 0.2, 1)
    local vsX = screenW / 2
    local vsY = formationStartY + totalFormationHeight / 2
    love.graphics.printf("VS", vsX - 30, vsY - 10, 60, "center")
    
    -- Draw attack animation sprite
    if M.animating and M.animAction and M.animAction.user then
        local animPokemon = M.animAction.user
        local animSize = 50
        local animX = M.animCurrentX - animSize / 2
        local animY = M.animCurrentY - animSize / 2
        
        -- For status moves, don't draw the attacker moving - draw flash on target
        if M.animPhase == "status_flash" then
            -- Draw purple/blue flash effect on target for status moves
            local statusDuration = 0.3
            local statusProgress = math.min(1, M.animTimer / statusDuration)
            local flashAlpha = 0.6 * math.sin(statusProgress * math.pi)  -- Fade in and out
            
            love.graphics.setColor(0.5, 0.3, 0.9, flashAlpha)
            love.graphics.circle("fill", M.animTargetX, M.animTargetY, 35 + 10 * math.sin(statusProgress * math.pi))
            
            -- Draw some sparkle effects around the target
            love.graphics.setColor(0.8, 0.6, 1, flashAlpha)
            for i = 1, 4 do
                local angle = (i / 4) * math.pi * 2 + M.animTimer * 3
                local dist = 30 + 10 * math.sin(statusProgress * math.pi * 2)
                local sparkleX = M.animTargetX + math.cos(angle) * dist
                local sparkleY = M.animTargetY + math.sin(angle) * dist
                love.graphics.circle("fill", sparkleX, sparkleY, 5)
            end
        else
            -- Normal attack animation: Draw a slight trail/shadow
            love.graphics.setColor(0.3, 0.3, 0.5, 0.3)
            love.graphics.rectangle("fill", animX - 5, animY - 5, animSize + 10, animSize + 10, 8, 8)
            
            -- Draw the Pokemon sprite using same orientation as formation
            -- Player Pokemon: back sprite (facing right toward enemy)
            -- Enemy Pokemon: front sprite (facing left toward player)
            local isPlayerTeam = M.animAction.team == "player"
            drawPokemonSprite(animPokemon, animX, animY, animSize, animSize, isPlayerTeam)
            
            -- Draw attack effect at impact
            if M.animPhase == "move_back" then
                love.graphics.setColor(1, 1, 0.5, 0.6)
                love.graphics.circle("fill", M.animTargetX, M.animTargetY, 20 + math.random(5))
            end
        end
    end
    
    -- Draw passive animation effects
    if M.passiveAnimating and M.passiveAnimUser then
        local animSize = 50
        
        if M.passiveAnimType == "heal" then
            -- Draw healer at bounced position
            local animX = M.passiveAnimUserCurrentX - animSize / 2
            local animY = M.passiveAnimUserCurrentY - animSize / 2
            local isPlayer = M.getFormationSide(M.passiveAnimUser) == "player"
            -- Use same sprite orientation as formation (back for player, front for enemy)
            drawPokemonSprite(M.passiveAnimUser, animX, animY, animSize, animSize, isPlayer)
            
            -- Draw green flash on target during flash phase
            if M.passiveAnimPhase == "flash" and M.passiveAnimTarget then
                local targetIsPlayer = M.getFormationSide(M.passiveAnimTarget) == "player"
                local targetX, targetY = M.getSlotPosition(M.passiveAnimTarget, targetIsPlayer)
                if targetX then
                    -- Pulsing green glow
                    local flashAlpha = 0.5 + 0.3 * math.sin(M.passiveFlashTimer * 15)
                    love.graphics.setColor(0, 1, 0.3, flashAlpha)
                    love.graphics.circle("fill", targetX, targetY, 35 + 5 * math.sin(M.passiveFlashTimer * 10))
                    
                    -- Green plus sign
                    love.graphics.setColor(0.2, 1, 0.4, 0.9)
                    love.graphics.setLineWidth(4)
                    love.graphics.line(targetX - 12, targetY, targetX + 12, targetY)
                    love.graphics.line(targetX, targetY - 12, targetX, targetY + 12)
                    love.graphics.setLineWidth(1)
                end
            end
            
        elseif M.passiveAnimType == "guard" then
            -- Draw guardian at current animated position
            local animX = M.passiveAnimUserCurrentX - animSize / 2
            local animY = M.passiveAnimUserCurrentY - animSize / 2
            local isPlayer = M.getFormationSide(M.passiveAnimUser) == "player"
            
            -- Draw trail effect
            love.graphics.setColor(0, 0.5, 1, 0.3)
            love.graphics.rectangle("fill", animX - 3, animY - 3, animSize + 6, animSize + 6, 8, 8)
            
            -- Use same sprite orientation as formation (back for player, front for enemy)
            drawPokemonSprite(M.passiveAnimUser, animX, animY, animSize, animSize, isPlayer)
            
            -- Draw blue flash during guard_flash phase
            if M.passiveAnimPhase == "guard_flash" then
                -- Flash on guardian
                local flashAlpha = 0.4 + 0.3 * math.sin(M.passiveFlashTimer * 20)
                love.graphics.setColor(0, 0.5, 1, flashAlpha)
                love.graphics.circle("fill", M.passiveAnimUserCurrentX, M.passiveAnimUserCurrentY, 40)
                
                -- Flash on ally being protected
                if M.passiveAnimTarget then
                    local targetIsPlayer = M.getFormationSide(M.passiveAnimTarget) == "player"
                    local targetX, targetY = M.getSlotPosition(M.passiveAnimTarget, targetIsPlayer)
                    if targetX then
                        love.graphics.setColor(0, 0.4, 0.9, flashAlpha * 0.7)
                        love.graphics.circle("fill", targetX, targetY, 30)
                        
                        -- Shield icon
                        love.graphics.setColor(0.3, 0.6, 1, 0.9)
                        love.graphics.setLineWidth(3)
                        love.graphics.arc("line", "open", targetX, targetY - 5, 15, -2.5, -0.6)
                        love.graphics.setLineWidth(1)
                    end
                end
            end
        elseif M.passiveAnimType == "attack" then
            -- Attack animation for passives like Pursuit
            local animX = M.passiveAnimUserCurrentX - animSize / 2
            local animY = M.passiveAnimUserCurrentY - animSize / 2
            local isPlayer = M.getFormationSide(M.passiveAnimUser) == "player"
            
            -- Draw trail effect (orange for attack)
            love.graphics.setColor(1, 0.5, 0.2, 0.3)
            love.graphics.rectangle("fill", animX - 3, animY - 3, animSize + 6, animSize + 6, 8, 8)
            
            -- Use same sprite orientation as formation (back for player, front for enemy)
            drawPokemonSprite(M.passiveAnimUser, animX, animY, animSize, animSize, isPlayer)
            
            -- Draw orange hit effect during attack_hit phase
            if M.passiveAnimPhase == "attack_hit" and M.passiveAnimTarget then
                local flashAlpha = 0.6 + 0.3 * math.sin(M.passiveFlashTimer * 20)
                love.graphics.setColor(1, 0.6, 0.2, flashAlpha)
                love.graphics.circle("fill", M.passiveAnimTargetStartX, M.passiveAnimTargetStartY, 25 + math.random(5))
                
                -- Impact lines
                love.graphics.setColor(1, 1, 0.5, 0.8)
                love.graphics.setLineWidth(2)
                for i = 1, 4 do
                    local angle = (i / 4) * math.pi * 2 + M.passiveFlashTimer * 5
                    local len = 15 + math.random(10)
                    love.graphics.line(
                        M.passiveAnimTargetStartX + math.cos(angle) * 10,
                        M.passiveAnimTargetStartY + math.sin(angle) * 10,
                        M.passiveAnimTargetStartX + math.cos(angle) * len,
                        M.passiveAnimTargetStartY + math.sin(angle) * len
                    )
                end
                love.graphics.setLineWidth(1)
            end
        elseif M.passiveAnimType == "buff" then
            -- Buff animation: golden/yellow rising effect on user
            local flashAlpha = 0.4 + 0.4 * math.sin(M.passiveFlashTimer * 15)
            local isPlayer = M.getFormationSide(M.passiveAnimUser) == "player"
            local userX, userY = M.passiveAnimUserStartX, M.passiveAnimUserStartY
            
            -- Yellow glow around user
            love.graphics.setColor(1, 0.85, 0.2, flashAlpha)
            love.graphics.circle("fill", userX, userY, 35 + 5 * math.sin(M.passiveFlashTimer * 10))
            
            -- Upward arrow indicators
            love.graphics.setColor(1, 0.9, 0.3, 0.9)
            love.graphics.setLineWidth(3)
            local arrowOffset = 20 + 10 * math.sin(M.passiveFlashTimer * 8)
            for i = -1, 1, 2 do
                local ax = userX + i * 25
                local ay = userY - arrowOffset
                love.graphics.line(ax, ay + 10, ax, ay - 5)
                love.graphics.line(ax - 5, ay, ax, ay - 5)
                love.graphics.line(ax + 5, ay, ax, ay - 5)
            end
            love.graphics.setLineWidth(1)
            
        elseif M.passiveAnimType == "debuff" then
            -- Debuff animation: purple/dark effect on target
            local flashAlpha = 0.4 + 0.4 * math.sin(M.passiveFlashTimer * 15)
            local targetX, targetY = M.passiveAnimTargetStartX, M.passiveAnimTargetStartY
            
            -- Purple glow around target
            love.graphics.setColor(0.6, 0.2, 0.8, flashAlpha)
            love.graphics.circle("fill", targetX, targetY, 35 + 5 * math.sin(M.passiveFlashTimer * 10))
            
            -- Downward arrow indicators
            love.graphics.setColor(0.8, 0.3, 1, 0.9)
            love.graphics.setLineWidth(3)
            local arrowOffset = 20 + 10 * math.sin(M.passiveFlashTimer * 8)
            for i = -1, 1, 2 do
                local ax = targetX + i * 25
                local ay = targetY + arrowOffset
                love.graphics.line(ax, ay - 10, ax, ay + 5)
                love.graphics.line(ax - 5, ay, ax, ay + 5)
                love.graphics.line(ax + 5, ay, ax, ay + 5)
            end
            love.graphics.setLineWidth(1)
            
        elseif M.passiveAnimType == "recoil" then
            -- Recoil animation: red flash on attacker (who takes damage)
            local flashAlpha = 0.5 + 0.4 * math.sin(M.passiveFlashTimer * 20)
            local targetX, targetY = M.passiveAnimTargetStartX, M.passiveAnimTargetStartY
            
            -- Red flash
            love.graphics.setColor(1, 0.2, 0.2, flashAlpha)
            love.graphics.circle("fill", targetX, targetY, 30 + 8 * math.sin(M.passiveFlashTimer * 12))
            
            -- Small damage particles
            love.graphics.setColor(1, 0.5, 0.3, 0.8)
            for i = 1, 6 do
                local angle = (i / 6) * math.pi * 2 + M.passiveFlashTimer * 3
                local dist = 25 + 10 * math.sin(M.passiveFlashTimer * 10 + i)
                local px = targetX + math.cos(angle) * dist
                local py = targetY + math.sin(angle) * dist
                love.graphics.circle("fill", px, py, 4)
            end
        end
    end
    
    -- Draw AP/PP legend
    love.graphics.setColor(0.2, 0.5, 1, 1)
    love.graphics.circle("fill", 15, 10, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("AP", 23, 5)
    
    love.graphics.setColor(1, 0.6, 0.2, 1)
    love.graphics.circle("fill", 50, 10, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("PP", 58, 5)
    
    -- Draw turn/round counter
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Round: " .. M.roundNumber .. "  Turn: " .. M.turnNumber, screenW - 130, 5)
    
    -- Draw battle log at bottom
    UI.drawBox(5, logBoxY, screenW - 10, logBoxHeight)
    
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    local logY = logBoxY + 8
    local lineHeight = 14
    for i, msg in ipairs(M.battleLog) do
        -- Split message by newlines and draw each line
        for line in string.gmatch(msg .. "\n", "([^\n]*)\n") do
            if line ~= "" then
                love.graphics.print(line, 15, logY)
                logY = logY + lineHeight
            end
        end
    end
    
    -- Draw instructions
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    if M.skillEditMode then
        -- Skill edit mode instructions
        if M.skillPickerOpen then
            love.graphics.print("[Z] Select  [X] Cancel", screenW - 160, logBoxY + logBoxHeight - 16)
        else
            love.graphics.print("[Z] Edit  [X] Back  [Arrows] Navigate", screenW - 220, logBoxY + logBoxHeight - 16)
        end
        love.graphics.setColor(0.9, 0.6, 0.2, 1)
        love.graphics.print("SKILL EDIT", screenW / 2 - 40, 5)
    elseif M.tacticsMode and M.battlePhase == "tactics" then
        -- Tactics mode instructions
        if M.tacticsSelected then
            love.graphics.print("[Z] Swap  [X] Cancel", screenW - 145, logBoxY + logBoxHeight - 16)
        else
            love.graphics.print("[Z] Select  [C] Skills  [X] Fight!", screenW - 210, logBoxY + logBoxHeight - 16)
        end
        -- Draw "TACTICS" label
        love.graphics.setColor(0.2, 0.7, 1, 1)
        love.graphics.print("TACTICS", screenW / 2 - 30, 5)
    elseif M.waitingForZ then
        love.graphics.print("[Z] Continue", screenW - 95, logBoxY + logBoxHeight - 16)
    elseif M.mode == "idle" and M.battlePhase == "round_end" then
        if M.isTrainerBattle then
            love.graphics.print("[Z] Organize", screenW - 100, logBoxY + logBoxHeight - 16)
        else
            love.graphics.print("[Z] Organize  [X] Run", screenW - 155, logBoxY + logBoxHeight - 16)
        end
    elseif M.mode == "idle" and M.battlePhase ~= "end" then
        if M.isTrainerBattle then
            love.graphics.print("[Z] Attack", screenW - 85, logBoxY + logBoxHeight - 16)
        else
            love.graphics.print("[Z] Attack  [X] Run", screenW - 140, logBoxY + logBoxHeight - 16)
        end
    end
    
    -- Draw skill edit overlay if active
    if M.skillEditMode and M.skillEditPokemon then
        -- Dim background
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)
        
        -- Skill edit panel
        local panelW = 320
        local panelH = 220
        local panelX = (screenW - panelW) / 2
        local panelY = (screenH - panelH) / 2 - 20
        
        -- Panel background
        love.graphics.setColor(0.15, 0.15, 0.25, 0.95)
        love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 8, 8)
        love.graphics.setColor(0.4, 0.5, 0.8, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 8, 8)
        love.graphics.setLineWidth(1)
        
        -- Title
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(M.skillEditPokemon.name .. " - Skill Loadout", panelX + 10, panelY + 8)
        
        -- Column headers
        local colSkillX = panelX + 15
        local colCond1X = panelX + 115
        local colCond2X = panelX + 220
        local headerY = panelY + 28
        
        love.graphics.setColor(0.7, 0.7, 0.9, 1)
        love.graphics.print("Skill", colSkillX, headerY)
        love.graphics.print("Filter 1", colCond1X, headerY)
        love.graphics.print("Filter 2", colCond2X, headerY)
        
        -- Get loadout
        local loadout = getOrCreateLoadout(M.skillEditPokemon)
        
        -- Draw skill slots
        local slotY = headerY + 18
        local slotHeight = 20
        for i = 1, M.maxSkillSlots do
            local slot = loadout[i] or {}
            local y = slotY + (i - 1) * slotHeight
            
            -- Highlight current slot
            if i == M.skillEditSlot then
                love.graphics.setColor(0.3, 0.4, 0.6, 0.5)
                love.graphics.rectangle("fill", panelX + 5, y - 2, panelW - 10, slotHeight, 3, 3)
            end
            
            -- Slot number
            love.graphics.setColor(0.5, 0.5, 0.6, 1)
            love.graphics.print(i .. ".", panelX + 5, y)
            
            -- Skill name
            local skillName = slot.skill or "(Empty)"
            local skill = Skills[slot.skill] or Passives[slot.skill]
            if skill then skillName = skill.name end
            
            if i == M.skillEditSlot and M.skillEditField == 1 then
                love.graphics.setColor(0.3, 0.8, 1, 1)
            elseif skill and skill.skillType == "passive" then
                love.graphics.setColor(1, 0.7, 0.4, 1)
            else
                love.graphics.setColor(0.8, 0.8, 1, 1)
            end
            love.graphics.print(skillName, colSkillX, y)
            
            -- Condition 1
            local cond1Name = "None"
            local cond1 = getConditionById(slot.condition1)
            if cond1 then cond1Name = cond1.name end
            
            if i == M.skillEditSlot and M.skillEditField == 2 then
                love.graphics.setColor(0.3, 0.8, 1, 1)
            else
                love.graphics.setColor(0.7, 0.7, 0.7, 1)
            end
            -- Truncate long condition names
            if #cond1Name > 12 then cond1Name = cond1Name:sub(1, 11) .. "." end
            love.graphics.print(cond1Name, colCond1X, y)
            
            -- Condition 2
            local cond2Name = "None"
            local cond2 = getConditionById(slot.condition2)
            if cond2 then cond2Name = cond2.name end
            
            if i == M.skillEditSlot and M.skillEditField == 3 then
                love.graphics.setColor(0.3, 0.8, 1, 1)
            else
                love.graphics.setColor(0.7, 0.7, 0.7, 1)
            end
            if #cond2Name > 12 then cond2Name = cond2Name:sub(1, 11) .. "." end
            love.graphics.print(cond2Name, colCond2X, y)
        end
        
        -- Draw picker overlay if open
        if M.skillPickerOpen then
            local pickerItems = {}
            local pickerTitle = ""
            
            if M.skillEditField == 1 then
                pickerTitle = "Select Skill"
                table.insert(pickerItems, {id = nil, name = "(Empty)", desc = "Remove skill from slot"})
                
                -- Show only skills this Pokemon knows
                local speciesId = M.skillEditPokemon.speciesId or 
                                 (M.skillEditPokemon.species and M.skillEditPokemon.species.name and 
                                  M.skillEditPokemon.species.name:lower():gsub(" ", "_"))
                local level = M.skillEditPokemon.level or 5
                local knownSkills = SkillsModule.getKnownSkills(speciesId or "unknown", level)
                
                for _, skillId in ipairs(knownSkills) do
                    local skill = SkillsModule.getSkillById(skillId)
                    if skill then
                        table.insert(pickerItems, skill)
                    end
                end
            elseif M.skillEditField == 2 or M.skillEditField == 3 then
                if M.skillPickerMode == "category" then
                    -- Show categories
                    pickerTitle = M.skillEditField == 2 and "Filter 1 Category" or "Filter 2 Category"
                    for _, cat in ipairs(ConditionCategories) do
                        table.insert(pickerItems, cat)
                    end
                else
                    -- Show conditions in selected category
                    local catName = M.skillPickerCategory or "?"
                    for _, cat in ipairs(ConditionCategories) do
                        if cat.id == M.skillPickerCategory then catName = cat.name break end
                    end
                    pickerTitle = catName .. " Filters"
                    local conditions = getConditionsByCategory(M.skillPickerCategory)
                    for _, cond in ipairs(conditions) do
                        table.insert(pickerItems, cond)
                    end
                end
            end
            
            -- Picker panel - overlay on the main panel for better visibility
            local pickW = 180
            local pickH = math.min(200, 30 + #pickerItems * 16)
            
            -- Position picker based on which field is selected
            local pickX, pickY
            if M.skillEditField == 1 then
                -- Skill picker - overlay on left side of panel
                pickX = panelX + 10
            elseif M.skillEditField == 2 then
                -- Condition picker - center
                pickX = panelX + (panelW - pickW) / 2
            else
                -- Condition 2 picker - right side
                pickX = panelX + panelW - pickW - 10
            end
            pickY = panelY + 20
            
            -- Clamp to screen bounds
            if pickX < 5 then pickX = 5 end
            if pickX + pickW > screenW - 5 then pickX = screenW - pickW - 5 end
            if pickY + pickH > screenH - 10 then pickY = screenH - pickH - 10 end
            
            love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
            love.graphics.rectangle("fill", pickX, pickY, pickW, pickH, 5, 5)
            love.graphics.setColor(0.5, 0.6, 0.9, 1)
            love.graphics.rectangle("line", pickX, pickY, pickW, pickH, 5, 5)
            
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(pickerTitle, pickX + 5, pickY + 5)
            
            -- Scrollable list
            local listY = pickY + 25
            local visibleItems = math.floor((pickH - 30) / 16)
            local scrollOffset = math.max(0, M.skillPickerCursor - visibleItems)
            
            for i = 1, math.min(visibleItems, #pickerItems) do
                local idx = i + scrollOffset
                if idx <= #pickerItems then
                    local item = pickerItems[idx]
                    local itemY = listY + (i - 1) * 16
                    
                    if idx == M.skillPickerCursor then
                        love.graphics.setColor(0.3, 0.5, 0.8, 0.7)
                        love.graphics.rectangle("fill", pickX + 2, itemY - 1, pickW - 4, 16, 2, 2)
                        love.graphics.setColor(1, 1, 0.8, 1)
                    elseif item.skillType == "passive" then
                        love.graphics.setColor(1, 0.7, 0.4, 1)
                    elseif M.skillPickerMode == "category" then
                        love.graphics.setColor(0.6, 0.9, 0.6, 1)
                    else
                        love.graphics.setColor(0.8, 0.8, 0.9, 1)
                    end
                    
                    local displayName = item.name or item.id or "?"
                    if #displayName > 22 then displayName = displayName:sub(1, 21) .. "." end
                    love.graphics.print(displayName, pickX + 8, itemY)
                end
            end
            
            -- Scroll indicators
            if scrollOffset > 0 then
                love.graphics.setColor(0.6, 0.6, 0.8, 1)
                love.graphics.print("^", pickX + pickW - 15, pickY + 22)
            end
            if scrollOffset + visibleItems < #pickerItems then
                love.graphics.setColor(0.6, 0.6, 0.8, 1)
                love.graphics.print("v", pickX + pickW - 15, pickY + pickH - 15)
            end
            
            -- Show back hint for condition picker
            if M.skillPickerMode == "list" and (M.skillEditField == 2 or M.skillEditField == 3) then
                love.graphics.setColor(0.5, 0.5, 0.7, 1)
                love.graphics.print("[X] Back", pickX + 5, pickY + pickH - 15)
            end
        end
    -- Draw selected Pokemon info in tactics mode (when not in skill edit)
    elseif M.tacticsMode and M.battlePhase == "tactics" then
        local hoveredPokemon = M.playerFormation[M.tacticsCursor]
        if hoveredPokemon then
            -- Draw info panel
            local infoX = screenW / 2 - 60
            local infoY = formationStartY + totalFormationHeight / 2 - 40
            
            love.graphics.setColor(0.1, 0.1, 0.2, 0.9)
            love.graphics.rectangle("fill", infoX - 5, infoY - 5, 130, 90, 5, 5)
            love.graphics.setColor(0.3, 0.5, 0.8, 1)
            love.graphics.rectangle("line", infoX - 5, infoY - 5, 130, 90, 5, 5)
            
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(hoveredPokemon.name, infoX, infoY)
            
            -- Count active/passive skills in loadout
            local loadout = getOrCreateLoadout(hoveredPokemon)
            local activeCount, passiveCount = 0, 0
            for _, slot in ipairs(loadout) do
                if slot.skill then
                    if Skills[slot.skill] then activeCount = activeCount + 1
                    elseif Passives[slot.skill] then passiveCount = passiveCount + 1
                    end
                end
            end
            
            love.graphics.setColor(0.8, 0.8, 1, 1)
            love.graphics.print("Active: " .. activeCount .. " skill(s)", infoX, infoY + 16)
            love.graphics.setColor(1, 0.8, 0.5, 1)
            love.graphics.print("Passive: " .. passiveCount .. " skill(s)", infoX, infoY + 32)
            
            -- Show row info
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
            local rowText = M.tacticsCursor <= 3 and "Front Row" or "Back Row"
            love.graphics.print(rowText, infoX, infoY + 48)
            
            love.graphics.setColor(0.5, 0.7, 1, 1)
            love.graphics.print("[C] Edit Skills", infoX, infoY + 64)
        end
    end
end

return M
