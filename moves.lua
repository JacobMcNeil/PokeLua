-- moves.lua
-- Move base class and example moves

local M = {}
local log = require('log')

--------------------------------------------------
-- STAT STAGE SYSTEM (just like the official games)
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
-- Stage -6 to +6 corresponds to index 1 to 13
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

-- Critical hit stage multipliers (Gen 6+ style)
-- Stages 0-4+ map to different crit ratios
local CritStageRatios = {
    [0] = 1/24,   -- ~4.17%
    [1] = 1/8,    -- 12.5%
    [2] = 1/2,    -- 50%
    [3] = 1,      -- 100% (guaranteed)
}

-- Temporary storage for effect messages (cleared after each move use)
M.effectMessages = {}

-- Helper to add an effect message (called by effect functions)
function M.addEffectMessage(msg)
    if msg and msg ~= "" then
        table.insert(M.effectMessages, msg)
    end
end

-- Clear effect messages (called at start of move use)
function M.clearEffectMessages()
    M.effectMessages = {}
end

-- Get and clear effect messages (called at end of move use)
function M.getEffectMessages()
    local msgs = M.effectMessages
    M.effectMessages = {}
    return msgs
end

-- Convert stage (-6 to +6) to array index (1 to 13)
local function stageToIndex(stage)
    return math.max(1, math.min(13, stage + 7))
end

-- Get stat multiplier for a given stage
function M.getStatMultiplier(stage)
    local index = stageToIndex(stage)
    return StatStageMultipliers[index] or 1
end

-- Get accuracy/evasion multiplier for a given stage
function M.getAccuracyEvasionMultiplier(stage)
    local index = stageToIndex(stage)
    return AccuracyEvasionMultipliers[index] or 1
end

-- Get critical hit ratio for a given crit stage
function M.getCritRatio(critStage)
    critStage = math.max(0, math.min(3, critStage or 0))
    return CritStageRatios[critStage] or CritStageRatios[0]
end

-- Initialize stat stages for a Pokemon (called at battle start)
function M.initStatStages(pokemon)
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
    pokemon.critStage = 0
end

-- Reset stat stages (called when Pokemon switches out or battle ends)
function M.resetStatStages(pokemon)
    M.initStatStages(pokemon)
end

-- Modify a stat stage by a number of stages, returns actual change and message
function M.modifyStatStage(pokemon, stat, stages, battle)
    if not pokemon or not pokemon.statStages then
        M.initStatStages(pokemon)
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
    
    -- Automatically add message to effect messages queue
    M.addEffectMessage(message)
    
    return actualChange, message
end

-- Get effective stat value considering base stat, IVs, EVs, level, and stage
function M.getEffectiveStat(pokemon, stat)
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
    
    local multiplier = M.getStatMultiplier(stage)
    return math.floor(baseStat * multiplier)
end

--------------------------------------------------
-- STATUS CONDITION SYSTEM
--------------------------------------------------
-- Primary status conditions (only one at a time):
-- - "paralyzed" - 25% chance to be fully paralyzed, Speed quartered
-- - "burned" - Lose 1/16 max HP each turn, Attack halved (physical only)
-- - "poisoned" - Lose 1/8 max HP each turn
-- - "badly_poisoned" - Lose increasing HP each turn (1/16 * turns)
-- - "asleep" - Can't move for 1-3 turns
-- - "frozen" - Can't move, 20% chance to thaw each turn
--
-- Volatile status (can stack):
-- - "confused" - 33% chance to hurt self
-- - "flinched" - Can't move this turn (resets each turn)
-- - "infatuated" - 50% chance to not move
-- - "seeded" - Leech Seed drains HP each turn
-- - "protected" - Blocks most moves this turn
--
-- Move state tracking (on the Pokemon object):
-- - charging: { move = moveRef, turn = 1 } - Pokemon is charging a 2-turn move
-- - recharging: true - Pokemon must recharge this turn (can't move)
-- - lockedMove: { move = moveRef, turnsRemaining = N } - Pokemon is locked into multi-turn move
-- - protectCount: number of consecutive successful Protect uses (for diminishing returns)

-- Check if a Pokemon can move this turn (returns canMove, messages table, forceMove)
-- Returns: canMove (bool), messages (table of strings to display in order), forceMove (move to force use)
function M.checkCanMove(pokemon, battle)
    if not pokemon then return false, {"No Pokemon!"}, nil end
    
    local pokeName = pokemon.nickname or pokemon.name or "Pokemon"
    local status = pokemon.status
    local messages = {}
    local forceMove = nil
    
    -- Check if Pokemon must recharge from last turn
    if pokemon.recharging then
        pokemon.recharging = nil
        table.insert(messages, pokeName .. " must recharge!")
        return false, messages, nil
    end
    
    -- Check if Pokemon is charging a move (second turn = attack)
    if pokemon.charging then
        forceMove = pokemon.charging.move
        -- Don't return yet - check other conditions first, but we'll force this move
    end
    
    -- Check if Pokemon is locked into a multi-turn move
    if pokemon.lockedMove and pokemon.lockedMove.turnsRemaining > 0 then
        forceMove = pokemon.lockedMove.move
        -- Don't return yet - check other conditions first
    end
    
    -- Check frozen status
    if status == "frozen" then
        -- 20% chance to thaw
        if math.random() < 0.2 then
            pokemon.status = nil
            table.insert(messages, pokeName .. " thawed out!")
            return true, messages, forceMove
        else
            -- Clear charging/locked move if frozen
            pokemon.charging = nil
            pokemon.lockedMove = nil
            table.insert(messages, pokeName .. " is frozen solid!")
            return false, messages, nil
        end
    end
    
    -- Check sleep status
    if status == "asleep" then
        pokemon.sleepTurns = (pokemon.sleepTurns or 0) - 1
        if pokemon.sleepTurns <= 0 then
            pokemon.status = nil
            pokemon.sleepTurns = nil
            table.insert(messages, pokeName .. " woke up!")
            return true, messages, forceMove
        else
            -- Clear charging/locked move if asleep
            pokemon.charging = nil
            pokemon.lockedMove = nil
            table.insert(messages, pokeName .. " is fast asleep!")
            return false, messages, nil
        end
    end
    
    -- Check paralysis (25% full paralysis)
    if status == "paralyzed" then
        if math.random() < 0.25 then
            -- Clear charging/locked move if paralyzed
            pokemon.charging = nil
            pokemon.lockedMove = nil
            table.insert(messages, pokeName .. " is paralyzed! It can't move!")
            return false, messages, nil
        end
    end
    
    -- Check flinch (volatile, one turn only)
    if pokemon.flinched then
        pokemon.flinched = nil  -- Reset flinch for next turn
        -- Clear charging/locked move if flinched
        pokemon.charging = nil
        pokemon.lockedMove = nil
        table.insert(messages, pokeName .. " flinched and couldn't move!")
        return false, messages, nil
    end
    
    -- Check confusion
    if pokemon.confused then
        pokemon.confusedTurns = (pokemon.confusedTurns or 0) - 1
        if pokemon.confusedTurns <= 0 then
            pokemon.confused = nil
            pokemon.confusedTurns = nil
            table.insert(messages, pokeName .. " snapped out of confusion!")
            -- Allow move after snapping out
        else
            table.insert(messages, pokeName .. " is confused!")
            -- 33% chance to hit self
            if math.random() < 0.33 then
                -- Deal confusion damage (40 base power physical attack on self)
                local confusionDmg = M.calculateConfusionDamage(pokemon)
                pokemon.currentHP = math.max(0, (pokemon.currentHP or 0) - confusionDmg)
                table.insert(messages, "It hurt itself in its confusion!")
                -- Clear charging/locked move if hurt by confusion
                pokemon.charging = nil
                pokemon.lockedMove = nil
                -- If Pokemon fainted from confusion, add faint message
                if pokemon.currentHP <= 0 then
                    table.insert(messages, pokeName .. " fainted!")
                end
                return false, messages, nil
            end
        end
    end
    
    -- Check infatuation
    if pokemon.infatuated then
        table.insert(messages, pokeName .. " is in love with the foe!")
        if math.random() < 0.5 then
            table.insert(messages, pokeName .. " is immobilized by love!")
            return false, messages, nil
        end
    end
    
    return true, messages, forceMove
end

-- Calculate confusion self-damage
function M.calculateConfusionDamage(pokemon)
    if not pokemon then return 0 end
    local level = pokemon.level or 50
    local attack = M.getEffectiveStat(pokemon, "attack")
    local defense = M.getEffectiveStat(pokemon, "defense")
    defense = math.max(1, defense)
    
    -- Confusion uses 40 base power
    local base = math.floor(((((2 * level) / 5) + 2) * 40 * attack / defense) / 50) + 2
    return math.floor(base)
end

-- Apply end-of-turn status damage
function M.applyEndOfTurnEffects(pokemon, battle)
    if not pokemon then return nil end
    
    local pokeName = pokemon.nickname or pokemon.name or "Pokemon"
    local status = pokemon.status
    local messages = {}
    
    local maxHP = (pokemon.stats and pokemon.stats.hp) or pokemon.maxHP or 100
    
    -- Burn damage: 1/16 max HP
    if status == "burned" then
        local damage = math.max(1, math.floor(maxHP / 16))
        pokemon.currentHP = math.max(0, (pokemon.currentHP or 0) - damage)
        table.insert(messages, pokeName .. " was hurt by its burn!")
    end
    
    -- Poison damage: 1/8 max HP
    if status == "poisoned" then
        local damage = math.max(1, math.floor(maxHP / 8))
        pokemon.currentHP = math.max(0, (pokemon.currentHP or 0) - damage)
        table.insert(messages, pokeName .. " was hurt by poison!")
    end
    
    -- Badly poisoned: 1/16 * turns (increasing each turn)
    if status == "badly_poisoned" then
        pokemon.toxicCounter = (pokemon.toxicCounter or 1)
        local damage = math.max(1, math.floor(maxHP * pokemon.toxicCounter / 16))
        pokemon.currentHP = math.max(0, (pokemon.currentHP or 0) - damage)
        pokemon.toxicCounter = pokemon.toxicCounter + 1
        table.insert(messages, pokeName .. " was hurt by poison!")
    end
    
    -- Leech Seed
    if pokemon.seeded and battle then
        local damage = math.max(1, math.floor(maxHP / 8))
        pokemon.currentHP = math.max(0, (pokemon.currentHP or 0) - damage)
        -- Heal the opponent (who planted the seed)
        local opponent = (pokemon == battle.p1) and battle.p2 or battle.p1
        if opponent then
            local oppMaxHP = (opponent.stats and opponent.stats.hp) or opponent.maxHP or 100
            opponent.currentHP = math.min(oppMaxHP, (opponent.currentHP or 0) + damage)
        end
        table.insert(messages, pokeName .. "'s health is sapped by Leech Seed!")
    end
    
    return messages
end

-- Apply a status condition to a Pokemon
function M.applyStatus(pokemon, status, battle)
    if not pokemon then return false, "No target!" end
    
    local pokeName = pokemon.nickname or pokemon.name or "Pokemon"
    
    -- Check if Pokemon already has a status
    if pokemon.status then
        local msg = pokeName .. " is already affected by a status condition!"
        M.addEffectMessage(msg)
        return false, msg
    end
    
    -- Type immunities
    local types = pokemon.types or pokemon.type or (pokemon.species and pokemon.species.types) or {}
    if type(types) == "string" then types = {types} end
    
    for _, ptype in ipairs(types) do
        ptype = string.lower(ptype)
        -- Electric types can't be paralyzed
        if status == "paralyzed" and ptype == "electric" then
            local msg = "It doesn't affect " .. pokeName .. "..."
            M.addEffectMessage(msg)
            return false, msg
        end
        -- Fire types can't be burned
        if status == "burned" and ptype == "fire" then
            local msg = "It doesn't affect " .. pokeName .. "..."
            M.addEffectMessage(msg)
            return false, msg
        end
        -- Poison and Steel types can't be poisoned
        if (status == "poisoned" or status == "badly_poisoned") and (ptype == "poison" or ptype == "steel") then
            local msg = "It doesn't affect " .. pokeName .. "..."
            M.addEffectMessage(msg)
            return false, msg
        end
        -- Ice types can't be frozen
        if status == "frozen" and ptype == "ice" then
            local msg = "It doesn't affect " .. pokeName .. "..."
            M.addEffectMessage(msg)
            return false, msg
        end
    end
    
    -- Apply the status
    pokemon.status = status
    
    -- Set up status-specific counters
    if status == "asleep" then
        pokemon.sleepTurns = math.random(1, 3) -- 1-3 turns
    elseif status == "badly_poisoned" then
        pokemon.toxicCounter = 1
    end
    
    -- Generate message
    local statusMessages = {
        paralyzed = pokeName .. " is paralyzed! It may be unable to move!",
        burned = pokeName .. " was burned!",
        poisoned = pokeName .. " was poisoned!",
        badly_poisoned = pokeName .. " was badly poisoned!",
        asleep = pokeName .. " fell asleep!",
        frozen = pokeName .. " was frozen solid!",
    }
    
    local message = statusMessages[status] or (pokeName .. " was afflicted with " .. status .. "!")
    -- Automatically add message to effect messages queue
    M.addEffectMessage(message)
    
    return true, message
end

-- Apply a volatile status condition
function M.applyVolatileStatus(pokemon, volatile, battle)
    if not pokemon then return false, "No target!" end
    
    local pokeName = pokemon.nickname or pokemon.name or "Pokemon"
    
    if volatile == "confused" then
        if pokemon.confused then
            local msg = pokeName .. " is already confused!"
            M.addEffectMessage(msg)
            return false, msg
        end
        pokemon.confused = true
        pokemon.confusedTurns = math.random(2, 5) -- 2-5 turns
        local msg = pokeName .. " became confused!"
        M.addEffectMessage(msg)
        return true, msg
    elseif volatile == "flinched" then
        pokemon.flinched = true
        return true, nil -- No message for flinch
    elseif volatile == "infatuated" then
        if pokemon.infatuated then
            local msg = pokeName .. " is already infatuated!"
            M.addEffectMessage(msg)
            return false, msg
        end
        pokemon.infatuated = true
        local msg = pokeName .. " fell in love!"
        M.addEffectMessage(msg)
        return true, msg
    elseif volatile == "seeded" then
        if pokemon.seeded then
            local msg = pokeName .. " is already seeded!"
            M.addEffectMessage(msg)
            return false, msg
        end
        -- Grass types immune to Leech Seed
        local types = pokemon.types or pokemon.type or (pokemon.species and pokemon.species.types) or {}
        if type(types) == "string" then types = {types} end
        for _, ptype in ipairs(types) do
            if string.lower(ptype) == "grass" then
                local msg = "It doesn't affect " .. pokeName .. "..."
                M.addEffectMessage(msg)
                return false, msg
            end
        end
        pokemon.seeded = true
        local msg = pokeName .. " was seeded!"
        M.addEffectMessage(msg)
        return true, msg
    end
    
    return false, "Unknown volatile status!"
end

-- Cure a Pokemon's status
function M.cureStatus(pokemon)
    if not pokemon then return end
    pokemon.status = nil
    pokemon.sleepTurns = nil
    pokemon.toxicCounter = nil
end

-- Cure volatile statuses (when switching out)
function M.cureVolatileStatus(pokemon)
    if not pokemon then return end
    pokemon.confused = nil
    pokemon.confusedTurns = nil
    pokemon.flinched = nil
    pokemon.infatuated = nil
    pokemon.seeded = nil
    -- Also clear move state when switching
    pokemon.charging = nil
    pokemon.recharging = nil
    pokemon.lockedMove = nil
    pokemon.protected = nil
    pokemon.protectCount = nil
end

--------------------------------------------------
-- PROTECTION SYSTEM
--------------------------------------------------

-- Check if a move is blocked by Protect/Detect
-- Returns true if move is blocked, false otherwise
function M.checkProtection(target, move, user)
    if not target or not target.protected then
        return false
    end
    
    -- Some moves bypass Protect (like Feint, Shadow Force's attack turn, etc.)
    if move and move.bypassesProtect then
        return false
    end
    
    return true
end

-- Try to use Protect/Detect - returns success and message
function M.tryProtect(pokemon, battle)
    if not pokemon then return false, "No Pokemon!" end
    
    local pokeName = pokemon.nickname or pokemon.name or "Pokemon"
    
    -- Calculate success chance based on consecutive uses
    -- First use: 100%, second: 50%, third: 25%, etc.
    local protectCount = pokemon.protectCount or 0
    local successChance = 1 / (2 ^ protectCount)
    
    if math.random() < successChance then
        pokemon.protected = true
        pokemon.protectCount = protectCount + 1
        local msg = pokeName .. " protected itself!"
        M.addEffectMessage(msg)
        return true, msg
    else
        pokemon.protectCount = 0 -- Reset on failure
        local msg = "But it failed!"
        M.addEffectMessage(msg)
        return false, msg
    end
end

-- Reset protect at end of turn (called by battle system)
function M.resetProtect(pokemon)
    if not pokemon then return end
    pokemon.protected = nil
end

-- Reset protect count when a different move is used
function M.resetProtectCount(pokemon)
    if not pokemon then return end
    pokemon.protectCount = 0
end

--------------------------------------------------
-- DRAINING MOVE SYSTEM
--------------------------------------------------

-- Apply HP drain effect - heals user for percentage of damage dealt
-- drainPercent is a decimal (0.5 = 50%, 0.75 = 75%)
function M.applyDrain(user, damageDealt, drainPercent)
    if not user or not damageDealt or damageDealt <= 0 then return 0 end
    
    drainPercent = drainPercent or 0.5
    local healAmount = math.max(1, math.floor(damageDealt * drainPercent))
    local maxHP = (user.stats and user.stats.hp) or user.maxHP or 100
    
    local oldHP = user.currentHP or 0
    user.currentHP = math.min(maxHP, oldHP + healAmount)
    local actualHeal = user.currentHP - oldHP
    
    return actualHeal
end

--------------------------------------------------
-- CHARGING MOVE SYSTEM
--------------------------------------------------

-- Start charging a move (first turn)
function M.startCharging(pokemon, move, chargeMessage)
    if not pokemon or not move then return end
    
    -- Determine semi-invulnerable state from move
    local semiInvulnerable = false
    local underground = false
    local flying = false
    local underwater = false
    
    if type(move) == "table" then
        semiInvulnerable = move.makesUserSemiInvulnerable or false
        -- Determine which type of invulnerability based on move name
        local moveName = move.name or ""
        if moveName == "Dig" then
            underground = true
        elseif moveName == "Fly" or moveName == "Bounce" or moveName == "Sky Drop" then
            flying = true
        elseif moveName == "Dive" then
            underwater = true
        end
    end
    
    pokemon.charging = {
        move = move,
        turn = 1,
        semiInvulnerable = semiInvulnerable,
        underground = underground,
        flying = flying,
        underwater = underwater
    }
    
    local pokeName = pokemon.nickname or pokemon.name or "Pokemon"
    local msg = chargeMessage or (pokeName .. " is charging power!")
    M.addEffectMessage(msg)
end

-- Check if Pokemon is on the charging turn (returns true if should skip attack)
function M.isCharging(pokemon)
    return pokemon and pokemon.charging and pokemon.charging.turn == 1
end

-- Complete charging (move to attack turn)
function M.completeCharging(pokemon)
    if pokemon and pokemon.charging then
        pokemon.charging = nil
    end
end

--------------------------------------------------
-- RECHARGE MOVE SYSTEM
--------------------------------------------------

-- Set Pokemon to recharge next turn
function M.setRecharge(pokemon)
    if not pokemon then return end
    pokemon.recharging = true
end

--------------------------------------------------
-- MULTI-TURN MOVE SYSTEM (Thrash, Outrage, Petal Dance)
--------------------------------------------------

-- Start a locked-in multi-turn move
function M.startLockedMove(pokemon, move, minTurns, maxTurns)
    if not pokemon or not move then return end
    
    minTurns = minTurns or 2
    maxTurns = maxTurns or 3
    local turns = math.random(minTurns, maxTurns)
    
    pokemon.lockedMove = {
        move = move,
        turnsRemaining = turns,
        totalTurns = turns
    }
end

-- Decrement turn counter and check if move ends
-- Returns true if move continues, false if it ends (and applies confusion)
function M.continueLockedMove(pokemon)
    if not pokemon or not pokemon.lockedMove then
        return false
    end
    
    pokemon.lockedMove.turnsRemaining = pokemon.lockedMove.turnsRemaining - 1
    
    if pokemon.lockedMove.turnsRemaining <= 0 then
        pokemon.lockedMove = nil
        -- Apply confusion after rampage ends
        M.applyVolatileStatus(pokemon, "confused")
        return false
    end
    
    return true
end

-- Check if Pokemon is in a locked move
function M.isLockedInMove(pokemon)
    return pokemon and pokemon.lockedMove and pokemon.lockedMove.turnsRemaining > 0
end

-- Force end a locked move (e.g., if target faints or switches)
function M.endLockedMove(pokemon, applyConfusion)
    if not pokemon then return end
    
    if pokemon.lockedMove and applyConfusion ~= false then
        M.applyVolatileStatus(pokemon, "confused")
    end
    pokemon.lockedMove = nil
end

--------------------------------------------------
-- RECOIL DAMAGE SYSTEM
--------------------------------------------------

-- Apply recoil damage to user
-- recoilPercent is a decimal (0.33 = 1/3 of damage dealt)
function M.applyRecoil(user, damageDealt, recoilPercent)
    if not user or not damageDealt or damageDealt <= 0 then return 0 end
    
    recoilPercent = recoilPercent or 0.33
    local recoilDamage = math.max(1, math.floor(damageDealt * recoilPercent))
    
    user.currentHP = math.max(0, (user.currentHP or 0) - recoilDamage)
    
    local pokeName = user.nickname or user.name or "Pokemon"
    M.addEffectMessage(pokeName .. " was hurt by recoil!")
    
    return recoilDamage
end

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
    steel = { fire = 0.5, water = 0.5, electric = 0.5, ice = 2, normal = 2, flying = 1, poison = 0, ground = 1, rock = 2, bug = 1, grass = 0.5, psychic = 2, dragon = 1, steel = 0.5, fairy = 2 },
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

-- Calculate if a move hits, considering accuracy, evasion, and stat stages
function Move:calculateHitChance(user, target)
    local baseAccuracy = self.accuracy or 100
    
    -- Moves with accuracy of 0 or nil (like Swift) never miss
    if baseAccuracy == 0 or baseAccuracy == nil then
        return 100
    end
    
    -- Get accuracy stage of user and evasion stage of target
    local accuracyStage = 0
    local evasionStage = 0
    
    if user and user.statStages then
        accuracyStage = user.statStages.accuracy or 0
    end
    
    if target and target.statStages then
        evasionStage = target.statStages.evasion or 0
    end
    
    -- Calculate combined stage (accuracy - evasion), clamped to -6 to +6
    local combinedStage = math.max(-6, math.min(6, accuracyStage - evasionStage))
    
    -- Get multiplier for the combined stage
    local stageMultiplier = M.getAccuracyEvasionMultiplier(combinedStage)
    
    -- Final accuracy = base accuracy * stage multiplier
    local finalAccuracy = math.floor(baseAccuracy * stageMultiplier)
    
    return finalAccuracy
end

-- Use a move: consumes PP, checks accuracy with stat stages, applies damage formula with stat stages, runs effect
function Move:use(user, target, battle)
    -- Clear any previous effect messages
    M.clearEffectMessages()
    
    if self.pp and self.pp > 0 then self.pp = self.pp - 1 end

    -- Check if target is protected
    if M.checkProtection(target, self, user) then
        local targetName = target.nickname or target.name or "Pokemon"
        return { hit = false, message = targetName .. " protected itself!", protected = true }
    end

    -- Check if target is semi-invulnerable (Fly, Dig, etc.)
    if target and target.charging and target.charging.semiInvulnerable then
        local targetName = target.nickname or target.name or "Pokemon"
        local chargingMove = target.charging.move or ""
        -- Check if this move can hit semi-invulnerable targets
        local canHit = false
        -- Earthquake and Magnitude can hit Dig users
        if target.charging.underground then
            if self.name == "Earthquake" or self.name == "Magnitude" then
                canHit = true
            end
        end
        -- Thunder, Gust, Twister, Sky Uppercut can hit Fly users
        if target.charging.flying then
            if self.name == "Thunder" or self.name == "Gust" or self.name == "Twister" or self.name == "Sky Uppercut" or self.name == "Hurricane" then
                canHit = true
            end
        end
        -- Surf can hit Dive users
        if target.charging.underwater then
            if self.name == "Surf" or self.name == "Whirlpool" then
                canHit = true
            end
        end
        if not canHit then
            return { hit = false, message = targetName .. " avoided the attack!" }
        end
    end

    -- Calculate accuracy considering stat stages
    local effectiveAccuracy = self:calculateHitChance(user, target)
    local hitRoll = math.random(1, 100)
    
    if effectiveAccuracy < 100 and hitRoll > effectiveAccuracy then
        return { hit = false, message = (user and (user.nickname or user.name) or tostring(user)) .. "'s " .. self.name .. " missed!" }
    end

    if self.power and self.power > 0 then
        log.log("moves.Move:use: calculating damage")
        local Level = (user and user.level) or 50
        local Power = self.power
        local category = self.category or self.cat or "Physical"

        -- Choose attack/defense stats based on category, applying stat stages
        local A, D
        if category == "Physical" then
            -- Get effective attack with stat stage modifier
            A = M.getEffectiveStat(user, "attack")
            if A == 1 and user and user.stats then
                A = user.stats.attack or 5
            end
            -- Get effective defense with stat stage modifier
            D = M.getEffectiveStat(target, "defense")
            if D == 1 and target and target.stats then
                D = target.stats.defense or 5
            end
        else
            -- Special attack/defense
            A = M.getEffectiveStat(user, "spAttack")
            if A == 1 and user and user.stats then
                A = user.stats.spAttack or 5
            end
            D = M.getEffectiveStat(target, "spDefense")
            if D == 1 and target and target.stats then
                D = target.stats.spDefense or 5
            end
        end
        D = math.max(1, D)

        -- Optional modifiers (default to 1)
        local Targets = self.targets or 1
        local PB = self.pb or 1
        local Weather = (battle and battle.weather) or 1
        local GlaiveRush = self.glaiveRush or 1
        local rand = math.random(85, 100) / 100
        
        -- Critical hit calculation using crit stages
        local Critical = 1
        local critStage = (user and user.critStage) or 0
        if self.highCritRatio then
            critStage = critStage + 1 -- High crit moves add +1 stage
        end
        local critRatio = M.getCritRatio(critStage)
        if math.random() < critRatio then
            Critical = 1.5 -- Gen 6+ crit multiplier
            log.log("  Critical hit!")
        end
        
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
        
        -- Burn halves physical attack damage (already factored into stat via getEffectiveStat if we want,
        -- but the official formula applies it as a modifier)
        local Burn = 1
        if user and user.status == 'burned' and category == "Physical" then Burn = 0.5 end
        
        -- Paralysis quarters speed (handled in getEffectiveStat for speed)
        
        local other = self.other or 1
        local ZMove = self.zmove or 1
        local TeraShield = self.teraShield or 1

        local base = math.floor(((((2 * Level) / 5) + 2) * Power * A / D) / 50) + 2
        local modifier = Targets * PB * Weather * GlaiveRush * Critical * rand * STAB * Type * Burn * other * ZMove * TeraShield
        local damage = math.max(1, math.floor(base * modifier))
        target.currentHP = math.max(0, (target.currentHP or 0) - damage)
        
        -- Handle draining moves - heal user for percentage of damage dealt
        if self.drainPercent and self.drainPercent > 0 and damage > 0 then
            local healAmount = M.applyDrain(user, damage, self.drainPercent)
            if healAmount > 0 then
                local userName = user.nickname or user.name or "Pokemon"
                M.addEffectMessage(userName .. " had its energy drained!")
            end
        end
        
        -- Handle recoil moves - damage user for percentage of damage dealt
        if self.recoilPercent and self.recoilPercent > 0 and damage > 0 then
            M.applyRecoil(user, damage, self.recoilPercent)
        end
        
        -- Handle recharge moves - set user to recharge next turn
        if self.requiresRecharge and damage > 0 then
            M.setRecharge(user)
        end
        
        if self.effect then self.effect(user, target, battle) end
        local uname = (user and (user.nickname or user.name)) or tostring(user)
        
        -- Add type effectiveness and critical hit to message
        local effectText = ""
        if Critical > 1 then
            effectText = " A critical hit!"
        end
        if Type >= 2 then
            effectText = effectText .. " It was super effective!"
        elseif Type > 1 and Type < 2 then
            effectText = effectText .. " It was super effective!"
        elseif Type <= 0.5 and Type > 0 then
            effectText = effectText .. " It's not very effective..."
        elseif Type == 0 then
            effectText = " It had no effect!"
        end
        
        local msg = string.format("It dealt %d damage!%s", damage, effectText)
        
        -- Collect any effect messages (from stat changes, status effects, etc.)
        local effectMessages = M.getEffectMessages()
        
        return { hit = true, damage = damage, message = msg, critical = Critical > 1, effectMessages = effectMessages }
    else
        if self.effect then self.effect(user, target, battle) end
        
        -- Collect any effect messages (from stat changes, status effects, etc.)
        local effectMessages = M.getEffectMessages()
        
        -- For status moves, don't return a separate message since battle.lua already shows "X used Move!"
        -- Only return effect messages
        return { hit = true, damage = 0, message = nil, effectMessages = effectMessages }
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

--------------------------------------------------
-- MOVES DEFINITIONS
-- Now using proper stat stage system
--------------------------------------------------

-- ============ NORMAL TYPE MOVES ============

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

local Pound = Move:extend{
    defaults = {
        name = "Pound",
        type = "Normal",
        category = "Physical",
        power = 40,
        accuracy = 100,
        maxPP = 35,
    }
}
M.Pound = Pound

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

local Slam = Move:extend{
    defaults = {
        name = "Slam",
        type = "Normal",
        category = "Physical",
        power = 80,
        accuracy = 75,
        maxPP = 20,
    }
}
M.Slam = Slam

local BodySlam = Move:extend{
    defaults = {
        name = "Body Slam",
        type = "Normal",
        category = "Physical",
        power = 85,
        accuracy = 100,
        maxPP = 15,
        effect = function(user, target, battle)
            if math.random() < 0.3 then
                M.applyStatus(target, "paralyzed", battle)
            end
        end,
    }
}
M.BodySlam = BodySlam

local Slash = Move:extend{
    defaults = {
        name = "Slash",
        type = "Normal",
        category = "Physical",
        power = 70,
        accuracy = 100,
        maxPP = 20,
        highCritRatio = true, -- +1 crit stage
    }
}
M.Slash = Slash

local HyperBeam = Move:extend{
    defaults = {
        name = "Hyper Beam",
        type = "Normal",
        category = "Special",
        power = 150,
        accuracy = 90,
        maxPP = 5,
        requiresRecharge = true, -- User must recharge next turn
    }
}
M.HyperBeam = HyperBeam

-- Giga Impact: Physical counterpart to Hyper Beam
local GigaImpact = Move:extend{
    defaults = {
        name = "Giga Impact",
        type = "Normal",
        category = "Physical",
        power = 150,
        accuracy = 90,
        maxPP = 5,
        requiresRecharge = true, -- User must recharge next turn
    }
}
M.GigaImpact = GigaImpact

-- Double-Edge: Powerful recoil move
local DoubleEdge = Move:extend{
    defaults = {
        name = "Double-Edge",
        type = "Normal",
        category = "Physical",
        power = 120,
        accuracy = 100,
        maxPP = 15,
        recoilPercent = 0.33, -- Recoil: 1/3 of damage dealt
    }
}
M.DoubleEdge = DoubleEdge

-- Take Down: Recoil move
local TakeDown = Move:extend{
    defaults = {
        name = "Take Down",
        type = "Normal",
        category = "Physical",
        power = 90,
        accuracy = 85,
        maxPP = 20,
        recoilPercent = 0.25, -- Recoil: 1/4 of damage dealt
    }
}
M.TakeDown = TakeDown

local Swift = Move:extend{
    defaults = {
        name = "Swift",
        type = "Normal",
        category = "Special",
        power = 60,
        accuracy = 0, -- Never misses (accuracy of 0 bypasses check)
        maxPP = 20,
    }
}
M.Swift = Swift

local Bite = Move:extend{
    defaults = {
        name = "Bite",
        type = "Dark",
        category = "Physical",
        power = 60,
        accuracy = 100,
        maxPP = 25,
        effect = function(user, target, battle)
            if math.random() < 0.3 then
                M.applyVolatileStatus(target, "flinched", battle)
            end
        end,
    }
}
M.Bite = Bite

-- ============ STAT MODIFYING MOVES ============

-- Growl: Lowers target's Attack by 1 stage
local Growl = Move:extend{
    defaults = {
        name = "Growl",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 100,
        maxPP = 40,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(target, "attack", -1, battle)
            -- Message will be shown through the battle system
        end,
    }
}
M.Growl = Growl

-- Tail Whip: Lowers target's Defense by 1 stage
local TailWhip = Move:extend{
    defaults = {
        name = "Tail Whip",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 100,
        maxPP = 30,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(target, "defense", -1, battle)
        end,
    }
}
M.TailWhip = TailWhip

-- Leer: Lowers target's Defense by 1 stage
local Leer = Move:extend{
    defaults = {
        name = "Leer",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 100,
        maxPP = 30,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(target, "defense", -1, battle)
        end,
    }
}
M.Leer = Leer

-- Screech: Harshly lowers target's Defense by 2 stages
local Screech = Move:extend{
    defaults = {
        name = "Screech",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 85,
        maxPP = 40,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(target, "defense", -2, battle)
        end,
    }
}
M.Screech = Screech

-- Swords Dance: Sharply raises user's Attack by 2 stages
local SwordsDance = Move:extend{
    defaults = {
        name = "Swords Dance",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 20,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(user, "attack", 2, battle)
        end,
    }
}
M.SwordsDance = SwordsDance

-- Agility: Sharply raises user's Speed by 2 stages
local Agility = Move:extend{
    defaults = {
        name = "Agility",
        type = "Psychic",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 30,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(user, "speed", 2, battle)
        end,
    }
}
M.Agility = Agility

-- Nasty Plot: Sharply raises user's Sp. Attack by 2 stages
local NastyPlot = Move:extend{
    defaults = {
        name = "Nasty Plot",
        type = "Dark",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 20,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(user, "spAttack", 2, battle)
        end,
    }
}
M.NastyPlot = NastyPlot

-- Iron Defense: Sharply raises user's Defense by 2 stages
local IronDefense = Move:extend{
    defaults = {
        name = "Iron Defense",
        type = "Steel",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 15,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(user, "defense", 2, battle)
        end,
    }
}
M.IronDefense = IronDefense

-- Calm Mind: Raises user's Sp. Attack and Sp. Defense by 1 stage each
local CalmMind = Move:extend{
    defaults = {
        name = "Calm Mind",
        type = "Psychic",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 20,
        effect = function(user, target, battle)
            M.modifyStatStage(user, "spAttack", 1, battle)
            M.modifyStatStage(user, "spDefense", 1, battle)
        end,
    }
}
M.CalmMind = CalmMind

-- Dragon Dance: Raises user's Attack and Speed by 1 stage each
local DragonDance = Move:extend{
    defaults = {
        name = "Dragon Dance",
        type = "Dragon",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 20,
        effect = function(user, target, battle)
            M.modifyStatStage(user, "attack", 1, battle)
            M.modifyStatStage(user, "speed", 1, battle)
        end,
    }
}
M.DragonDance = DragonDance

-- Bulk Up: Raises user's Attack and Defense by 1 stage each
local BulkUp = Move:extend{
    defaults = {
        name = "Bulk Up",
        type = "Fighting",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 20,
        effect = function(user, target, battle)
            M.modifyStatStage(user, "attack", 1, battle)
            M.modifyStatStage(user, "defense", 1, battle)
        end,
    }
}
M.BulkUp = BulkUp

-- Harden: Raises user's Defense by 1 stage
local Harden = Move:extend{
    defaults = {
        name = "Harden",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 30,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(user, "defense", 1, battle)
        end,
    }
}
M.Harden = Harden

-- Withdraw: Raises user's Defense by 1 stage
local Withdraw = Move:extend{
    defaults = {
        name = "Withdraw",
        type = "Water",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 40,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(user, "defense", 1, battle)
        end,
    }
}
M.Withdraw = Withdraw

-- Defense Curl: Raises user's Defense by 1 stage
local DefenseCurl = Move:extend{
    defaults = {
        name = "Defense Curl",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 40,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(user, "defense", 1, battle)
        end,
    }
}
M.DefenseCurl = DefenseCurl

-- ============ ACCURACY/EVASION MOVES ============

-- Sand Attack: Lowers target's Accuracy by 1 stage
local SandAttack = Move:extend{
    defaults = {
        name = "Sand Attack",
        type = "Ground",
        category = "Status",
        power = 0,
        accuracy = 100,
        maxPP = 15,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(target, "accuracy", -1, battle)
        end,
    }
}
M.SandAttack = SandAttack

-- Smokescreen: Lowers target's Accuracy by 1 stage
local Smokescreen = Move:extend{
    defaults = {
        name = "Smokescreen",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 100,
        maxPP = 20,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(target, "accuracy", -1, battle)
        end,
    }
}
M.Smokescreen = Smokescreen

-- Flash: Lowers target's Accuracy by 1 stage
local Flash = Move:extend{
    defaults = {
        name = "Flash",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 100,
        maxPP = 20,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(target, "accuracy", -1, battle)
        end,
    }
}
M.Flash = Flash

-- Double Team: Raises user's Evasion by 1 stage
local DoubleTeam = Move:extend{
    defaults = {
        name = "Double Team",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 15,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(user, "evasion", 1, battle)
        end,
    }
}
M.DoubleTeam = DoubleTeam

-- Minimize: Sharply raises user's Evasion by 2 stages
local Minimize = Move:extend{
    defaults = {
        name = "Minimize",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 10,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(user, "evasion", 2, battle)
        end,
    }
}
M.Minimize = Minimize

-- Sweet Scent: Harshly lowers target's Evasion by 2 stages
local SweetScent = Move:extend{
    defaults = {
        name = "Sweet Scent",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 100,
        maxPP = 20,
        effect = function(user, target, battle)
            local change, msg = M.modifyStatStage(target, "evasion", -2, battle)
        end,
    }
}
M.SweetScent = SweetScent

-- ============ STATUS INFLICTING MOVES ============

-- Thunder Wave: Paralyzes the target (doesn't deal damage)
local ThunderWave = Move:extend{
    defaults = {
        name = "Thunder Wave",
        type = "Electric",
        category = "Status",
        power = 0,
        accuracy = 90,
        maxPP = 20,
        effect = function(user, target, battle)
            M.applyStatus(target, "paralyzed", battle)
        end,
    }
}
M.ThunderWave = ThunderWave

-- Stun Spore: Paralyzes the target
local StunSpore = Move:extend{
    defaults = {
        name = "Stun Spore",
        type = "Grass",
        category = "Status",
        power = 0,
        accuracy = 75,
        maxPP = 30,
        effect = function(user, target, battle)
            M.applyStatus(target, "paralyzed", battle)
        end,
    }
}
M.StunSpore = StunSpore

-- Sleep Powder: Puts the target to sleep
local SleepPowder = Move:extend{
    defaults = {
        name = "Sleep Powder",
        type = "Grass",
        category = "Status",
        power = 0,
        accuracy = 75,
        maxPP = 15,
        effect = function(user, target, battle)
            M.applyStatus(target, "asleep", battle)
        end,
    }
}
M.SleepPowder = SleepPowder

-- Sing: Puts the target to sleep
local Sing = Move:extend{
    defaults = {
        name = "Sing",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 55,
        maxPP = 15,
        effect = function(user, target, battle)
            M.applyStatus(target, "asleep", battle)
        end,
    }
}
M.Sing = Sing

-- Hypnosis: Puts the target to sleep
local Hypnosis = Move:extend{
    defaults = {
        name = "Hypnosis",
        type = "Psychic",
        category = "Status",
        power = 0,
        accuracy = 60,
        maxPP = 20,
        effect = function(user, target, battle)
            M.applyStatus(target, "asleep", battle)
        end,
    }
}
M.Hypnosis = Hypnosis

-- Toxic: Badly poisons the target
local Toxic = Move:extend{
    defaults = {
        name = "Toxic",
        type = "Poison",
        category = "Status",
        power = 0,
        accuracy = 90,
        maxPP = 10,
        effect = function(user, target, battle)
            M.applyStatus(target, "badly_poisoned", battle)
        end,
    }
}
M.Toxic = Toxic

-- Poison Powder: Poisons the target
local PoisonPowder = Move:extend{
    defaults = {
        name = "Poison Powder",
        type = "Poison",
        category = "Status",
        power = 0,
        accuracy = 75,
        maxPP = 35,
        effect = function(user, target, battle)
            M.applyStatus(target, "poisoned", battle)
        end,
    }
}
M.PoisonPowder = PoisonPowder

-- Poison Gas: Poisons the target
local PoisonGas = Move:extend{
    defaults = {
        name = "Poison Gas",
        type = "Poison",
        category = "Status",
        power = 0,
        accuracy = 90,
        maxPP = 40,
        effect = function(user, target, battle)
            M.applyStatus(target, "poisoned", battle)
        end,
    }
}
M.PoisonGas = PoisonGas

-- Will-O-Wisp: Burns the target
local WillOWisp = Move:extend{
    defaults = {
        name = "Will-O-Wisp",
        type = "Fire",
        category = "Status",
        power = 0,
        accuracy = 85,
        maxPP = 15,
        effect = function(user, target, battle)
            M.applyStatus(target, "burned", battle)
        end,
    }
}
M.WillOWisp = WillOWisp

-- Confuse Ray: Confuses the target
local ConfuseRay = Move:extend{
    defaults = {
        name = "Confuse Ray",
        type = "Ghost",
        category = "Status",
        power = 0,
        accuracy = 100,
        maxPP = 10,
        effect = function(user, target, battle)
            M.applyVolatileStatus(target, "confused", battle)
        end,
    }
}
M.ConfuseRay = ConfuseRay

-- Supersonic: Confuses the target
local Supersonic = Move:extend{
    defaults = {
        name = "Supersonic",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 55,
        maxPP = 20,
        effect = function(user, target, battle)
            M.applyVolatileStatus(target, "confused", battle)
        end,
    }
}
M.Supersonic = Supersonic

-- Leech Seed: Drains HP each turn
local LeechSeed = Move:extend{
    defaults = {
        name = "Leech Seed",
        type = "Grass",
        category = "Status",
        power = 0,
        accuracy = 90,
        maxPP = 10,
        effect = function(user, target, battle)
            M.applyVolatileStatus(target, "seeded", battle)
        end,
    }
}
M.LeechSeed = LeechSeed

-- ============ ELECTRIC TYPE MOVES ============

local ThunderShock = Move:extend{
    defaults = {
        name = "Thunder Shock",
        type = "Electric",
        category = "Special",
        power = 40,
        accuracy = 100,
        maxPP = 30,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyStatus(target, "paralyzed", battle)
            end
        end,
    }
}
M.ThunderShock = ThunderShock

local Thunderbolt = Move:extend{
    defaults = {
        name = "Thunderbolt",
        type = "Electric",
        category = "Special",
        power = 90,
        accuracy = 100,
        maxPP = 15,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyStatus(target, "paralyzed", battle)
            end
        end,
    }
}
M.Thunderbolt = Thunderbolt

local Thunder = Move:extend{
    defaults = {
        name = "Thunder",
        type = "Electric",
        category = "Special",
        power = 110,
        accuracy = 70,
        maxPP = 10,
        effect = function(user, target, battle)
            if math.random() < 0.3 then
                M.applyStatus(target, "paralyzed", battle)
            end
        end,
    }
}
M.Thunder = Thunder

local Spark = Move:extend{
    defaults = {
        name = "Spark",
        type = "Electric",
        category = "Physical",
        power = 65,
        accuracy = 100,
        maxPP = 20,
        effect = function(user, target, battle)
            if math.random() < 0.3 then
                M.applyStatus(target, "paralyzed", battle)
            end
        end,
    }
}
M.Spark = Spark

-- Wild Charge: Electric recoil move
local WildCharge = Move:extend{
    defaults = {
        name = "Wild Charge",
        type = "Electric",
        category = "Physical",
        power = 90,
        accuracy = 100,
        maxPP = 15,
        recoilPercent = 0.25, -- Recoil: 1/4 of damage dealt
    }
}
M.WildCharge = WildCharge

-- Volt Tackle: Powerful electric recoil move, may paralyze
local VoltTackle = Move:extend{
    defaults = {
        name = "Volt Tackle",
        type = "Electric",
        category = "Physical",
        power = 120,
        accuracy = 100,
        maxPP = 15,
        recoilPercent = 0.33, -- Recoil: 1/3 of damage dealt
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyStatus(target, "paralyzed", battle)
            end
        end,
    }
}
M.VoltTackle = VoltTackle

-- ============ FIRE TYPE MOVES ============

local Ember = Move:extend{
    defaults = {
        name = "Ember",
        type = "Fire",
        category = "Special",
        power = 40,
        accuracy = 100,
        maxPP = 25,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyStatus(target, "burned", battle)
            end
        end,
    }
}
M.Ember = Ember

local Flamethrower = Move:extend{
    defaults = {
        name = "Flamethrower",
        type = "Fire",
        category = "Special",
        power = 90,
        accuracy = 100,
        maxPP = 15,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyStatus(target, "burned", battle)
            end
        end,
    }
}
M.Flamethrower = Flamethrower

local FireBlast = Move:extend{
    defaults = {
        name = "Fire Blast",
        type = "Fire",
        category = "Special",
        power = 110,
        accuracy = 85,
        maxPP = 5,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyStatus(target, "burned", battle)
            end
        end,
    }
}
M.FireBlast = FireBlast

local FireSpin = Move:extend{
    defaults = {
        name = "Fire Spin",
        type = "Fire",
        category = "Special",
        power = 35,
        accuracy = 85,
        maxPP = 15,
        -- Note: Trapping effect would need battle system support
    }
}
M.FireSpin = FireSpin

-- Flare Blitz: Powerful fire recoil move, may burn
local FlareBlitz = Move:extend{
    defaults = {
        name = "Flare Blitz",
        type = "Fire",
        category = "Physical",
        power = 120,
        accuracy = 100,
        maxPP = 15,
        recoilPercent = 0.33, -- Recoil: 1/3 of damage dealt
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyStatus(target, "burned", battle)
            end
        end,
    }
}
M.FlareBlitz = FlareBlitz

-- ============ WATER TYPE MOVES ============

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

local BubbleBeam = Move:extend{
    defaults = {
        name = "Bubble Beam",
        type = "Water",
        category = "Special",
        power = 65,
        accuracy = 100,
        maxPP = 20,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.modifyStatStage(target, "speed", -1, battle)
            end
        end,
    }
}
M.BubbleBeam = BubbleBeam

local Surf = Move:extend{
    defaults = {
        name = "Surf",
        type = "Water",
        category = "Special",
        power = 90,
        accuracy = 100,
        maxPP = 15,
    }
}
M.Surf = Surf

local HydroPump = Move:extend{
    defaults = {
        name = "Hydro Pump",
        type = "Water",
        category = "Special",
        power = 110,
        accuracy = 80,
        maxPP = 5,
    }
}
M.HydroPump = HydroPump

local Waterfall = Move:extend{
    defaults = {
        name = "Waterfall",
        type = "Water",
        category = "Physical",
        power = 80,
        accuracy = 100,
        maxPP = 15,
        effect = function(user, target, battle)
            if math.random() < 0.2 then
                M.applyVolatileStatus(target, "flinched", battle)
            end
        end,
    }
}
M.Waterfall = Waterfall

local AquaTail = Move:extend{
    defaults = {
        name = "Aqua Tail",
        type = "Water",
        category = "Physical",
        power = 90,
        accuracy = 90,
        maxPP = 10,
    }
}
M.AquaTail = AquaTail

-- ============ GRASS TYPE MOVES ============

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

local RazorLeaf = Move:extend{
    defaults = {
        name = "Razor Leaf",
        type = "Grass",
        category = "Physical",
        power = 55,
        accuracy = 95,
        maxPP = 25,
        highCritRatio = true,
    }
}
M.RazorLeaf = RazorLeaf

local SolarBeam = Move:extend{
    defaults = {
        name = "Solar Beam",
        type = "Grass",
        category = "Special",
        power = 120,
        accuracy = 100,
        maxPP = 10,
        isChargingMove = true,
        chargeMessage = "took in sunlight!",
    }
}
M.SolarBeam = SolarBeam

local EnergyBall = Move:extend{
    defaults = {
        name = "Energy Ball",
        type = "Grass",
        category = "Special",
        power = 90,
        accuracy = 100,
        maxPP = 10,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.modifyStatStage(target, "spDefense", -1, battle)
            end
        end,
    }
}
M.EnergyBall = EnergyBall

local GigaDrain = Move:extend{
    defaults = {
        name = "Giga Drain",
        type = "Grass",
        category = "Special",
        power = 75,
        accuracy = 100,
        maxPP = 10,
        drainPercent = 0.5, -- Heals 50% of damage dealt
    }
}
M.GigaDrain = GigaDrain

-- Absorb: Drains HP from target
local Absorb = Move:extend{
    defaults = {
        name = "Absorb",
        type = "Grass",
        category = "Special",
        power = 20,
        accuracy = 100,
        maxPP = 25,
        drainPercent = 0.5, -- Heals 50% of damage dealt
    }
}
M.Absorb = Absorb

-- Mega Drain: Drains HP from target
local MegaDrain = Move:extend{
    defaults = {
        name = "Mega Drain",
        type = "Grass",
        category = "Special",
        power = 40,
        accuracy = 100,
        maxPP = 15,
        drainPercent = 0.5, -- Heals 50% of damage dealt
    }
}
M.MegaDrain = MegaDrain

-- ============ ICE TYPE MOVES ============

local IceBeam = Move:extend{
    defaults = {
        name = "Ice Beam",
        type = "Ice",
        category = "Special",
        power = 90,
        accuracy = 100,
        maxPP = 10,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyStatus(target, "frozen", battle)
            end
        end,
    }
}
M.IceBeam = IceBeam

local Blizzard = Move:extend{
    defaults = {
        name = "Blizzard",
        type = "Ice",
        category = "Special",
        power = 110,
        accuracy = 70,
        maxPP = 5,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyStatus(target, "frozen", battle)
            end
        end,
    }
}
M.Blizzard = Blizzard

local AuroraBeam = Move:extend{
    defaults = {
        name = "Aurora Beam",
        type = "Ice",
        category = "Special",
        power = 65,
        accuracy = 100,
        maxPP = 20,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.modifyStatStage(target, "attack", -1, battle)
            end
        end,
    }
}
M.AuroraBeam = AuroraBeam

local IcePunch = Move:extend{
    defaults = {
        name = "Ice Punch",
        type = "Ice",
        category = "Physical",
        power = 75,
        accuracy = 100,
        maxPP = 15,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyStatus(target, "frozen", battle)
            end
        end,
    }
}
M.IcePunch = IcePunch

-- ============ FIGHTING TYPE MOVES ============

local KarateChop = Move:extend{
    defaults = {
        name = "Karate Chop",
        type = "Fighting",
        category = "Physical",
        power = 50,
        accuracy = 100,
        maxPP = 25,
        highCritRatio = true,
    }
}
M.KarateChop = KarateChop

local LowKick = Move:extend{
    defaults = {
        name = "Low Kick",
        type = "Fighting",
        category = "Physical",
        power = 60, -- Actually varies by weight, simplified here
        accuracy = 100,
        maxPP = 20,
    }
}
M.LowKick = LowKick

local DoubleKick = Move:extend{
    defaults = {
        name = "Double Kick",
        type = "Fighting",
        category = "Physical",
        power = 30, -- Hits twice = 60 effective
        accuracy = 100,
        maxPP = 30,
    }
}
M.DoubleKick = DoubleKick

local CloseCombat = Move:extend{
    defaults = {
        name = "Close Combat",
        type = "Fighting",
        category = "Physical",
        power = 120,
        accuracy = 100,
        maxPP = 5,
        effect = function(user, target, battle)
            M.modifyStatStage(user, "defense", -1, battle)
            M.modifyStatStage(user, "spDefense", -1, battle)
        end,
    }
}
M.CloseCombat = CloseCombat

local BrickBreak = Move:extend{
    defaults = {
        name = "Brick Break",
        type = "Fighting",
        category = "Physical",
        power = 75,
        accuracy = 100,
        maxPP = 15,
        -- Note: Breaks Light Screen/Reflect
    }
}
M.BrickBreak = BrickBreak

-- Drain Punch: Draining fighting move
local DrainPunch = Move:extend{
    defaults = {
        name = "Drain Punch",
        type = "Fighting",
        category = "Physical",
        power = 75,
        accuracy = 100,
        maxPP = 10,
        drainPercent = 0.5, -- Heals 50% of damage dealt
    }
}
M.DrainPunch = DrainPunch

-- ============ POISON TYPE MOVES ============

local PoisonSting = Move:extend{
    defaults = {
        name = "Poison Sting",
        type = "Poison",
        category = "Physical",
        power = 15,
        accuracy = 100,
        maxPP = 35,
        effect = function(user, target, battle)
            if math.random() < 0.3 then
                M.applyStatus(target, "poisoned", battle)
            end
        end,
    }
}
M.PoisonSting = PoisonSting

local Sludge = Move:extend{
    defaults = {
        name = "Sludge",
        type = "Poison",
        category = "Special",
        power = 65,
        accuracy = 100,
        maxPP = 20,
        effect = function(user, target, battle)
            if math.random() < 0.3 then
                M.applyStatus(target, "poisoned", battle)
            end
        end,
    }
}
M.Sludge = Sludge

local SludgeBomb = Move:extend{
    defaults = {
        name = "Sludge Bomb",
        type = "Poison",
        category = "Special",
        power = 90,
        accuracy = 100,
        maxPP = 10,
        effect = function(user, target, battle)
            if math.random() < 0.3 then
                M.applyStatus(target, "poisoned", battle)
            end
        end,
    }
}
M.SludgeBomb = SludgeBomb

-- ============ GROUND TYPE MOVES ============

local Dig = Move:extend{
    defaults = {
        name = "Dig",
        type = "Ground",
        category = "Physical",
        power = 80,
        accuracy = 100,
        maxPP = 10,
        isChargingMove = true,
        chargeMessage = "dug a hole!",
        makesUserSemiInvulnerable = true, -- Can't be hit while underground (except Earthquake, Magnitude)
    }
}
M.Dig = Dig

local Earthquake = Move:extend{
    defaults = {
        name = "Earthquake",
        type = "Ground",
        category = "Physical",
        power = 100,
        accuracy = 100,
        maxPP = 10,
    }
}
M.Earthquake = Earthquake

local MudSlap = Move:extend{
    defaults = {
        name = "Mud-Slap",
        type = "Ground",
        category = "Special",
        power = 20,
        accuracy = 100,
        maxPP = 10,
        effect = function(user, target, battle)
            M.modifyStatStage(target, "accuracy", -1, battle)
        end,
    }
}
M.MudSlap = MudSlap

-- ============ FLYING TYPE MOVES ============

local Gust = Move:extend{
    defaults = {
        name = "Gust",
        type = "Flying",
        category = "Special",
        power = 40,
        accuracy = 100,
        maxPP = 35,
    }
}
M.Gust = Gust

local WingAttack = Move:extend{
    defaults = {
        name = "Wing Attack",
        type = "Flying",
        category = "Physical",
        power = 60,
        accuracy = 100,
        maxPP = 35,
    }
}
M.WingAttack = WingAttack

local AerialAce = Move:extend{
    defaults = {
        name = "Aerial Ace",
        type = "Flying",
        category = "Physical",
        power = 60,
        accuracy = 0, -- Never misses
        maxPP = 20,
    }
}
M.AerialAce = AerialAce

local Fly = Move:extend{
    defaults = {
        name = "Fly",
        type = "Flying",
        category = "Physical",
        power = 90,
        accuracy = 95,
        maxPP = 15,
        isChargingMove = true,
        chargeMessage = "flew up high!",
        makesUserSemiInvulnerable = true, -- Can't be hit while flying (except Thunder, etc.)
    }
}
M.Fly = Fly

local BraveBird = Move:extend{
    defaults = {
        name = "Brave Bird",
        type = "Flying",
        category = "Physical",
        power = 120,
        accuracy = 100,
        maxPP = 15,
        recoilPercent = 0.33, -- Recoil: 1/3 of damage dealt
    }
}
M.BraveBird = BraveBird

-- ============ PSYCHIC TYPE MOVES ============

local Confusion = Move:extend{
    defaults = {
        name = "Confusion",
        type = "Psychic",
        category = "Special",
        power = 50,
        accuracy = 100,
        maxPP = 25,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyVolatileStatus(target, "confused", battle)
            end
        end,
    }
}
M.Confusion = Confusion

local Psychic = Move:extend{
    defaults = {
        name = "Psychic",
        type = "Psychic",
        category = "Special",
        power = 90,
        accuracy = 100,
        maxPP = 10,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.modifyStatStage(target, "spDefense", -1, battle)
            end
        end,
    }
}
M.Psychic = Psychic

local Psybeam = Move:extend{
    defaults = {
        name = "Psybeam",
        type = "Psychic",
        category = "Special",
        power = 65,
        accuracy = 100,
        maxPP = 20,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.applyVolatileStatus(target, "confused", battle)
            end
        end,
    }
}
M.Psybeam = Psybeam

-- Dream Eater: Only works on sleeping targets, drains HP
local DreamEater = Move:extend{
    defaults = {
        name = "Dream Eater",
        type = "Psychic",
        category = "Special",
        power = 100,
        accuracy = 100,
        maxPP = 15,
        drainPercent = 0.5, -- Heals 50% of damage dealt
        effect = function(user, target, battle)
            -- Dream Eater only works if target is asleep
            if not target or target.status ~= "asleep" then
                M.addEffectMessage("But it failed!")
                return false -- Signal that the move should fail
            end
        end,
    }
}
M.DreamEater = DreamEater

-- ============ BUG TYPE MOVES ============

local BugBite = Move:extend{
    defaults = {
        name = "Bug Bite",
        type = "Bug",
        category = "Physical",
        power = 60,
        accuracy = 100,
        maxPP = 20,
    }
}
M.BugBite = BugBite

local XScissor = Move:extend{
    defaults = {
        name = "X-Scissor",
        type = "Bug",
        category = "Physical",
        power = 80,
        accuracy = 100,
        maxPP = 15,
    }
}
M.XScissor = XScissor

local StringShot = Move:extend{
    defaults = {
        name = "String Shot",
        type = "Bug",
        category = "Status",
        power = 0,
        accuracy = 95,
        maxPP = 40,
        effect = function(user, target, battle)
            M.modifyStatStage(target, "speed", -2, battle)
        end,
    }
}
M.StringShot = StringShot

-- ============ ROCK TYPE MOVES ============

local RockThrow = Move:extend{
    defaults = {
        name = "Rock Throw",
        type = "Rock",
        category = "Physical",
        power = 50,
        accuracy = 90,
        maxPP = 15,
    }
}
M.RockThrow = RockThrow

local RockSlide = Move:extend{
    defaults = {
        name = "Rock Slide",
        type = "Rock",
        category = "Physical",
        power = 75,
        accuracy = 90,
        maxPP = 10,
        effect = function(user, target, battle)
            if math.random() < 0.3 then
                M.applyVolatileStatus(target, "flinched", battle)
            end
        end,
    }
}
M.RockSlide = RockSlide

local StoneEdge = Move:extend{
    defaults = {
        name = "Stone Edge",
        type = "Rock",
        category = "Physical",
        power = 100,
        accuracy = 80,
        maxPP = 5,
        highCritRatio = true,
    }
}
M.StoneEdge = StoneEdge

-- ============ GHOST TYPE MOVES ============

local Lick = Move:extend{
    defaults = {
        name = "Lick",
        type = "Ghost",
        category = "Physical",
        power = 30,
        accuracy = 100,
        maxPP = 30,
        effect = function(user, target, battle)
            if math.random() < 0.3 then
                M.applyStatus(target, "paralyzed", battle)
            end
        end,
    }
}
M.Lick = Lick

local ShadowBall = Move:extend{
    defaults = {
        name = "Shadow Ball",
        type = "Ghost",
        category = "Special",
        power = 80,
        accuracy = 100,
        maxPP = 15,
        effect = function(user, target, battle)
            if math.random() < 0.2 then
                M.modifyStatStage(target, "spDefense", -1, battle)
            end
        end,
    }
}
M.ShadowBall = ShadowBall

local ShadowClaw = Move:extend{
    defaults = {
        name = "Shadow Claw",
        type = "Ghost",
        category = "Physical",
        power = 70,
        accuracy = 100,
        maxPP = 15,
        highCritRatio = true,
    }
}
M.ShadowClaw = ShadowClaw

-- ============ DRAGON TYPE MOVES ============

local DragonRage = Move:extend{
    defaults = {
        name = "Dragon Rage",
        type = "Dragon",
        category = "Special",
        power = 0, -- Fixed 40 damage
        accuracy = 100,
        maxPP = 10,
        effect = function(user, target, battle)
            -- Dragon Rage always deals exactly 40 damage
            target.currentHP = math.max(0, (target.currentHP or 0) - 40)
        end,
    }
}
M.DragonRage = DragonRage

local DragonClaw = Move:extend{
    defaults = {
        name = "Dragon Claw",
        type = "Dragon",
        category = "Physical",
        power = 80,
        accuracy = 100,
        maxPP = 15,
    }
}
M.DragonClaw = DragonClaw

local DragonPulse = Move:extend{
    defaults = {
        name = "Dragon Pulse",
        type = "Dragon",
        category = "Special",
        power = 85,
        accuracy = 100,
        maxPP = 10,
    }
}
M.DragonPulse = DragonPulse

local Outrage = Move:extend{
    defaults = {
        name = "Outrage",
        type = "Dragon",
        category = "Physical",
        power = 120,
        accuracy = 100,
        maxPP = 10,
        isLockedMove = true,  -- Multi-turn rampage move
        lockedTurnsMin = 2,   -- 2-3 turns
        lockedTurnsMax = 3,
        confusesAfter = true, -- Causes confusion when it ends
    }
}
M.Outrage = Outrage

-- Thrash: Normal-type multi-turn move
local Thrash = Move:extend{
    defaults = {
        name = "Thrash",
        type = "Normal",
        category = "Physical",
        power = 120,
        accuracy = 100,
        maxPP = 10,
        isLockedMove = true,
        lockedTurnsMin = 2,
        lockedTurnsMax = 3,
        confusesAfter = true,
    }
}
M.Thrash = Thrash

-- Petal Dance: Grass-type multi-turn move
local PetalDance = Move:extend{
    defaults = {
        name = "Petal Dance",
        type = "Grass",
        category = "Special",
        power = 120,
        accuracy = 100,
        maxPP = 10,
        isLockedMove = true,
        lockedTurnsMin = 2,
        lockedTurnsMax = 3,
        confusesAfter = true,
    }
}
M.PetalDance = PetalDance

-- ============ DARK TYPE MOVES ============

local Crunch = Move:extend{
    defaults = {
        name = "Crunch",
        type = "Dark",
        category = "Physical",
        power = 80,
        accuracy = 100,
        maxPP = 15,
        effect = function(user, target, battle)
            if math.random() < 0.2 then
                M.modifyStatStage(target, "defense", -1, battle)
            end
        end,
    }
}
M.Crunch = Crunch

local DarkPulse = Move:extend{
    defaults = {
        name = "Dark Pulse",
        type = "Dark",
        category = "Special",
        power = 80,
        accuracy = 100,
        maxPP = 15,
        effect = function(user, target, battle)
            if math.random() < 0.2 then
                M.applyVolatileStatus(target, "flinched", battle)
            end
        end,
    }
}
M.DarkPulse = DarkPulse

local Feint = Move:extend{
    defaults = {
        name = "Feint",
        type = "Normal",
        category = "Physical",
        power = 30,
        accuracy = 100,
        maxPP = 10,
        priority = 2, -- High priority
    }
}
M.Feint = Feint

-- ============ STEEL TYPE MOVES ============

local MetalClaw = Move:extend{
    defaults = {
        name = "Metal Claw",
        type = "Steel",
        category = "Physical",
        power = 50,
        accuracy = 95,
        maxPP = 35,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.modifyStatStage(user, "attack", 1, battle)
            end
        end,
    }
}
M.MetalClaw = MetalClaw

local IronTail = Move:extend{
    defaults = {
        name = "Iron Tail",
        type = "Steel",
        category = "Physical",
        power = 100,
        accuracy = 75,
        maxPP = 15,
        effect = function(user, target, battle)
            if math.random() < 0.3 then
                M.modifyStatStage(target, "defense", -1, battle)
            end
        end,
    }
}
M.IronTail = IronTail

local FlashCannon = Move:extend{
    defaults = {
        name = "Flash Cannon",
        type = "Steel",
        category = "Special",
        power = 80,
        accuracy = 100,
        maxPP = 10,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.modifyStatStage(target, "spDefense", -1, battle)
            end
        end,
    }
}
M.FlashCannon = FlashCannon

-- ============ FAIRY TYPE MOVES ============

local FairyWind = Move:extend{
    defaults = {
        name = "Fairy Wind",
        type = "Fairy",
        category = "Special",
        power = 40,
        accuracy = 100,
        maxPP = 30,
    }
}
M.FairyWind = FairyWind

local Moonblast = Move:extend{
    defaults = {
        name = "Moonblast",
        type = "Fairy",
        category = "Special",
        power = 95,
        accuracy = 100,
        maxPP = 15,
        effect = function(user, target, battle)
            if math.random() < 0.3 then
                M.modifyStatStage(target, "spAttack", -1, battle)
            end
        end,
    }
}
M.Moonblast = Moonblast

local DrainingKiss = Move:extend{
    defaults = {
        name = "Draining Kiss",
        type = "Fairy",
        category = "Special",
        power = 50,
        accuracy = 100,
        maxPP = 10,
        drainPercent = 0.75, -- Heals 75% of damage dealt (unique to this move)
    }
}
M.DrainingKiss = DrainingKiss

local PlayRough = Move:extend{
    defaults = {
        name = "Play Rough",
        type = "Fairy",
        category = "Physical",
        power = 90,
        accuracy = 90,
        maxPP = 10,
        effect = function(user, target, battle)
            if math.random() < 0.1 then
                M.modifyStatStage(target, "attack", -1, battle)
            end
        end,
    }
}
M.PlayRough = PlayRough

-- ============ PROTECTION MOVES ============

local Protect = Move:extend{
    defaults = {
        name = "Protect",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 0, -- Success is determined by protectCount, not accuracy
        maxPP = 10,
        priority = 4, -- Very high priority
        isProtectMove = true,
        effect = function(user, target, battle)
            M.tryProtect(user, battle)
        end,
    }
}
M.Protect = Protect

local Detect = Move:extend{
    defaults = {
        name = "Detect",
        type = "Fighting",
        category = "Status",
        power = 0,
        accuracy = 0,
        maxPP = 5,
        priority = 4,
        isProtectMove = true,
        effect = function(user, target, battle)
            M.tryProtect(user, battle)
        end,
    }
}
M.Detect = Detect

-- Endure: Survives with 1 HP if hit by a KO move
local Endure = Move:extend{
    defaults = {
        name = "Endure",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 0,
        maxPP = 10,
        priority = 4,
        isProtectMove = true, -- Shares the diminishing returns with Protect
        effect = function(user, target, battle)
            -- Similar to Protect but different effect
            local pokeName = user.nickname or user.name or "Pokemon"
            local protectCount = user.protectCount or 0
            local successChance = 1 / (2 ^ protectCount)
            
            if math.random() < successChance then
                user.enduring = true
                user.protectCount = protectCount + 1
                M.addEffectMessage(pokeName .. " braced itself!")
            else
                user.protectCount = 0
                M.addEffectMessage("But it failed!")
            end
        end,
    }
}
M.Endure = Endure

-- ============ RECOVERY MOVES ============

local Recover = Move:extend{
    defaults = {
        name = "Recover",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 10,
        effect = function(user, target, battle)
            local maxHP = (user.stats and user.stats.hp) or user.maxHP or 100
            local healAmount = math.floor(maxHP / 2)
            local oldHP = user.currentHP or 0
            user.currentHP = math.min(maxHP, oldHP + healAmount)
            local actualHeal = user.currentHP - oldHP
            if actualHeal > 0 then
                local pokeName = user.nickname or user.name or "Pokemon"
                M.addEffectMessage(pokeName .. " regained health!")
            else
                M.addEffectMessage("But it failed!")
            end
        end,
    }
}
M.Recover = Recover

local Rest = Move:extend{
    defaults = {
        name = "Rest",
        type = "Psychic",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 10,
        effect = function(user, target, battle)
            -- Full heal but fall asleep
            M.cureStatus(user)
            local maxHP = (user.stats and user.stats.hp) or user.maxHP or 100
            user.currentHP = maxHP
            user.status = "asleep"
            user.sleepTurns = 2 -- Rest always sleeps for 2 turns
        end,
    }
}
M.Rest = Rest

local Synthesis = Move:extend{
    defaults = {
        name = "Synthesis",
        type = "Grass",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses
        maxPP = 5,
        effect = function(user, target, battle)
            local maxHP = (user.stats and user.stats.hp) or user.maxHP or 100
            local healAmount = math.floor(maxHP / 2)
            -- Weather would modify this, but simplified here
            user.currentHP = math.min(maxHP, (user.currentHP or 0) + healAmount)
        end,
    }
}
M.Synthesis = Synthesis

-- ============ SPECIAL MOVES ============

local Splash = Move:extend{
    defaults = {
        name = "Splash",
        type = "Normal",
        category = "Status",
        power = 0,
        accuracy = 0, -- Never misses (but does nothing)
        maxPP = 40,
        effect = function(user, target, battle)
            -- "But nothing happened!"
        end,
    }
}
M.Splash = Splash

local RapidSpin = Move:extend{
    defaults = {
        name = "Rapid Spin",
        type = "Normal",
        category = "Physical",
        power = 50,
        accuracy = 100,
        maxPP = 40,
        effect = function(user, target, battle)
            -- Remove entry hazards, Leech Seed, etc.
            user.seeded = nil
            -- Speed boost (Gen 8+)
            M.modifyStatStage(user, "speed", 1, battle)
        end,
    }
}
M.RapidSpin = RapidSpin

local SkullBash = Move:extend{
    defaults = {
        name = "Skull Bash",
        type = "Normal",
        category = "Physical",
        power = 130,
        accuracy = 100,
        maxPP = 10,
        isChargingMove = true,
        chargeMessage = "lowered its head!",
        -- Skull Bash raises Defense during charge turn
        chargeEffect = function(user)
            M.modifyStatStage(user, "defense", 1)
        end,
    }
}
M.SkullBash = SkullBash

-- ============ UNDERSCORE KEY ALIASES FOR LEARNSET COMPATIBILITY ============

M.tackle = Tackle
M.scratch = Scratch
M.pound = Pound
M.quick_attack = QuickAttack
M.slam = Slam
M.body_slam = BodySlam
M.slash = Slash
M.hyper_beam = HyperBeam
M.swift = Swift
M.bite = Bite
M.growl = Growl
M.tail_whip = TailWhip
M.leer = Leer
M.screech = Screech
M.swords_dance = SwordsDance
M.agility = Agility
M.nasty_plot = NastyPlot
M.iron_defense = IronDefense
M.calm_mind = CalmMind
M.dragon_dance = DragonDance
M.bulk_up = BulkUp
M.harden = Harden
M.withdraw = Withdraw
M.defense_curl = DefenseCurl
M.sand_attack = SandAttack
M.smokescreen = Smokescreen
M.flash = Flash
M.double_team = DoubleTeam
M.minimize = Minimize
M.sweet_scent = SweetScent
M.thunder_wave = ThunderWave
M.stun_spore = StunSpore
M.sleep_powder = SleepPowder
M.sing = Sing
M.hypnosis = Hypnosis
M.toxic = Toxic
M.poison_powder = PoisonPowder
M.poison_gas = PoisonGas
M.will_o_wisp = WillOWisp
M.confuse_ray = ConfuseRay
M.supersonic = Supersonic
M.leech_seed = LeechSeed
M.thunder_shock = ThunderShock
M.thunderbolt = Thunderbolt
M.thunder = Thunder
M.spark = Spark
M.ember = Ember
M.flamethrower = Flamethrower
M.fire_blast = FireBlast
M.fire_spin = FireSpin
M.water_gun = WaterGun
M.bubble_beam = BubbleBeam
M.surf = Surf
M.hydro_pump = HydroPump
M.waterfall = Waterfall
M.aqua_tail = AquaTail
M.vine_whip = VineWhip
M.razor_leaf = RazorLeaf
M.solar_beam = SolarBeam
M.energy_ball = EnergyBall
M.giga_drain = GigaDrain
M.ice_beam = IceBeam
M.blizzard = Blizzard
M.aurora_beam = AuroraBeam
M.ice_punch = IcePunch
M.karate_chop = KarateChop
M.low_kick = LowKick
M.double_kick = DoubleKick
M.close_combat = CloseCombat
M.brick_break = BrickBreak
M.poison_sting = PoisonSting
M.sludge = Sludge
M.sludge_bomb = SludgeBomb
M.dig = Dig
M.earthquake = Earthquake
M.mud_slap = MudSlap
M.gust = Gust
M.wing_attack = WingAttack
M.aerial_ace = AerialAce
M.fly = Fly
M.brave_bird = BraveBird
M.confusion = Confusion
M.psychic = Psychic
M.psybeam = Psybeam
M.bug_bite = BugBite
M.x_scissor = XScissor
M.string_shot = StringShot
M.rock_throw = RockThrow
M.rock_slide = RockSlide
M.stone_edge = StoneEdge
M.lick = Lick
M.shadow_ball = ShadowBall
M.shadow_claw = ShadowClaw
M.dragon_rage = DragonRage
M.dragon_claw = DragonClaw
M.dragon_pulse = DragonPulse
M.outrage = Outrage
M.thrash = Thrash
M.petal_dance = PetalDance
M.crunch = Crunch
M.dark_pulse = DarkPulse
M.feint = Feint
M.metal_claw = MetalClaw
M.iron_tail = IronTail
M.flash_cannon = FlashCannon
M.fairy_wind = FairyWind
M.moonblast = Moonblast
M.draining_kiss = DrainingKiss
M.play_rough = PlayRough
M.protect = Protect
M.detect = Detect
M.endure = Endure
M.recover = Recover
M.rest = Rest
M.synthesis = Synthesis
M.splash = Splash
M.rapid_spin = RapidSpin
M.skull_bash = SkullBash
M.absorb = Absorb
M.mega_drain = MegaDrain
M.giga_impact = GigaImpact
M.double_edge = DoubleEdge
M.take_down = TakeDown
M.wild_charge = WildCharge
M.volt_tackle = VoltTackle
M.flare_blitz = FlareBlitz
M.drain_punch = DrainPunch
M.dream_eater = DreamEater

return M
