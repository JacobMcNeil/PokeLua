-- trainer.lua
-- Trainer class for Pokemon trainer battles

local log = require("log")

--------------------------------------------------
-- TrainerData (STATIC DEFINITIONS)
-- Trainers are referenced by ID for map lookups
--------------------------------------------------

local TrainerData = {
    -- Bug Catcher trainers (using available Pokemon)
    bug_catcher_1 = {
        id = "bug_catcher_1",
        name = "Bug Catcher Joey",
        class = "Bug Catcher",
        money = 100,  -- Base money (multiplied by highest Pokemon level)
        pokemon = {
            { species = "bulbasaur", level = 5 },
            { species = "eevee", level = 5 }
        },
        defeat_message = "My Pokemon weren't strong enough!",
        sprite = nil  -- Optional sprite path
    },
    
    bug_catcher_2 = {
        id = "bug_catcher_2",
        name = "Bug Catcher Wade",
        class = "Bug Catcher",
        money = 120,
        pokemon = {
            { species = "bulbasaur", level = 6 },
            { species = "bulbasaur", level = 6 },
            { species = "eevee", level = 6 }
        },
        defeat_message = "You're better than I thought!",
        sprite = nil
    },
    
    -- Youngster trainers
    youngster_1 = {
        id = "youngster_1",
        name = "Youngster Ben",
        class = "Youngster",
        money = 150,
        pokemon = {
            { species = "eevee", level = 7 },
            { species = "pikachu", level = 7 }
        },
        defeat_message = "Aw man, I lost!",
        sprite = nil
    },
    
    -- Lass trainers
    lass_1 = {
        id = "lass_1",
        name = "Lass Sally",
        class = "Lass",
        money = 160,
        pokemon = {
            { species = "eevee", level = 8 },
            { species = "pikachu", level = 8 }
        },
        defeat_message = "Oh, you're pretty good!",
        sprite = nil
    },
    
    -- Rival trainer (for testing)
    rival_1 = {
        id = "rival_1",
        name = "Rival Blue",
        class = "Pokémon Trainer",
        money = 500,
        pokemon = {
            { species = "pikachu", level = 9 },
            { species = "squirtle", level = 10 }
        },
        defeat_message = "What?! I lost?! How could this be!",
        sprite = nil
    },
    
    -- Test trainer with common Pokemon
    test_trainer = {
        id = "test_trainer",
        name = "Trainer Red",
        class = "Pokémon Trainer",
        money = 200,
        pokemon = {
            { species = "pikachu", level = 8 },
            { species = "bulbasaur", level = 7 },
            { species = "charmander", level = 7 },
            { species = "pidgey", level = 8 },
            { species = "caterpie", level = 7 },
            { species = "eevee", level = 7 }
        },
        defeat_message = "Great battle!",
        sprite = nil
    }
}

--------------------------------------------------
-- Trainer (RUNTIME INSTANCE)
--------------------------------------------------

local Trainer = {}
Trainer.__index = Trainer

-- Create a new trainer instance from trainer ID
function Trainer:new(trainerId)
    local data = TrainerData[trainerId]
    if not data then
        log.log("Trainer:new - Unknown trainer ID: " .. tostring(trainerId))
        return nil
    end
    
    local self = setmetatable({}, Trainer)
    
    self.id = data.id
    self.name = data.name
    self.class = data.class
    self.baseMoney = data.money
    self.defeatMessage = data.defeat_message
    self.sprite = data.sprite
    self.defeated = false  -- Track if trainer has been beaten
    
    -- Create Pokemon party for this trainer
    self.party = {}
    local ok, pmod = pcall(require, "pokemon")
    if ok and pmod and pmod.Pokemon then
        for _, pokeData in ipairs(data.pokemon) do
            local pokemon = pmod.Pokemon:new(pokeData.species, pokeData.level)
            if pokemon then
                table.insert(self.party, pokemon)
            else
                log.log("Trainer:new - Failed to create Pokemon: " .. tostring(pokeData.species))
            end
        end
    else
        log.log("Trainer:new - Failed to load pokemon module")
    end
    
    self.currentPokemonIndex = 1
    
    return self
end

-- Get the trainer's currently active Pokemon
function Trainer:getCurrentPokemon()
    return self.party[self.currentPokemonIndex]
end

-- Get the next available (alive) Pokemon, returns nil if none left
function Trainer:getNextAlivePokemon()
    for i, pokemon in ipairs(self.party) do
        if pokemon and (pokemon.currentHP or 0) > 0 then
            self.currentPokemonIndex = i
            return pokemon
        end
    end
    return nil
end

-- Check if trainer has any Pokemon left that can battle
function Trainer:hasAlivePokemon()
    for _, pokemon in ipairs(self.party) do
        if pokemon and (pokemon.currentHP or 0) > 0 then
            return true
        end
    end
    return false
end

-- Get the number of Pokemon remaining
function Trainer:getRemainingPokemonCount()
    local count = 0
    for _, pokemon in ipairs(self.party) do
        if pokemon and (pokemon.currentHP or 0) > 0 then
            count = count + 1
        end
    end
    return count
end

-- Calculate prize money (based on highest level Pokemon)
function Trainer:getPrizeMoney()
    local maxLevel = 1
    for _, pokemon in ipairs(self.party) do
        if pokemon and pokemon.level then
            maxLevel = math.max(maxLevel, pokemon.level)
        end
    end
    return self.baseMoney * maxLevel
end

-- Get full display name (class + name)
function Trainer:getDisplayName()
    if self.class and self.class ~= "" then
        return self.class .. " " .. self.name
    end
    return self.name
end

-- Mark trainer as defeated
function Trainer:setDefeated()
    self.defeated = true
end

-- Check if already defeated (for rematch prevention)
function Trainer:isDefeated()
    return self.defeated
end

-- Reset trainer for rematch (restore all Pokemon)
function Trainer:reset()
    self.defeated = false
    self.currentPokemonIndex = 1
    
    -- Restore all Pokemon to full health
    for _, pokemon in ipairs(self.party) do
        if pokemon and pokemon.stats and pokemon.stats.hp then
            pokemon.currentHP = pokemon.stats.hp
            pokemon.status = nil
        end
    end
end

--------------------------------------------------
-- Module Export
--------------------------------------------------

return {
    TrainerData = TrainerData,
    Trainer = Trainer
}
