-- pokemon_core.lua
-- Defines PokemonSpecies (static data) and Pokemon (runtime instances)
-- Designed for LÖVE 2D / Lua

--------------------------------------------------
-- PokemonSpecies (STATIC DATA)
--------------------------------------------------

PokemonSpecies = {
    pikachu = {
        id = 25,
        name = "Pikachu",
        types = {"electric"},
        genderRatio = { male = 50, female = 50 },
        catchRate = 190,
        baseExpYield = 112,
        baseFriendship = 70,
        growthRate = "medium_fast",
        abilities = {"static"},
        hiddenAbility = "lightning_rod",
        baseStats = {
            hp = 35,
            attack = 55,
            defense = 40,
            spAttack = 50,
            spDefense = 50,
            speed = 90
        },
        learnset = {
            [1] = {"thunder_shock"},
            [5] = {"tail_whip"},
            [6] = {"growl"},
            [10] = {"quick_attack"},
            [20] = {"thunderbolt"}
        },
        evolution = {
            method = "item",
            item = "thunder_stone",
            into = "raichu"
        },
        sprite = {
            front = "assets/pokemon/pikachu_front.png",
            back  = "assets/pokemon/pikachu_back.png"
        }
    },

    eevee = {
        id = 133,
        name = "Eevee",
        types = {"normal"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 65,
        baseFriendship = 70,
        growthRate = "medium_fast",
        abilities = {"run_away", "adaptability"},
        hiddenAbility = "anticipation",
        baseStats = {
            hp = 55,
            attack = 55,
            defense = 50,
            spAttack = 45,
            spDefense = 65,
            speed = 55
        },
        learnset = {
            [1] = {"tackle", "tail_whip"},
            [10] = {"quick_attack"},
            [20] = {"bite"}
        },
        evolution = {
            method = "branch",
            options = {
                { method = "item", item = "water_stone", into = "vaporeon" },
                { method = "item", item = "thunder_stone", into = "jolteon" },
                { method = "item", item = "fire_stone", into = "flareon" }
            }
        },
        sprite = {
            front = "assets/pokemon/eevee_front.png",
            back  = "assets/pokemon/eevee_back.png"
        }
    },

    bulbasaur = {
        id = 1,
        name = "Bulbasaur",
        types = {"grass", "poison"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 64,
        baseFriendship = 70,
        growthRate = "medium_slow",
        abilities = {"overgrow"},
        hiddenAbility = "chlorophyll",
        baseStats = {
            hp = 45,
            attack = 49,
            defense = 49,
            spAttack = 65,
            spDefense = 65,
            speed = 45
        },
        learnset = {
            [1] = {"tackle", "growl"},
            [7] = {"vine_whip"},
            [13] = {"razor_leaf"}
        },
        evolution = {
            method = "level",
            level = 16,
            into = "ivysaur"
        },
        sprite = {
            front = "assets/pokemon/bulbasaur_front.png",
            back  = "assets/pokemon/bulbasaur_back.png"
        }
    },

    charmander = {
        id = 4,
        name = "Charmander",
        types = {"fire"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 62,
        baseFriendship = 70,
        growthRate = "medium_slow",
        abilities = {"blaze"},
        hiddenAbility = "solar_power",
        baseStats = {
            hp = 39,
            attack = 52,
            defense = 43,
            spAttack = 60,
            spDefense = 50,
            speed = 65
        },
        learnset = {
            [1] = {"scratch", "growl"},
            [7] = {"ember"},
            [10] = {"smokescreen"}
        },
        evolution = {
            method = "level",
            level = 16,
            into = "charmeleon"
        },
        sprite = {
            front = "assets/pokemon/charmander_front.png",
            back  = "assets/pokemon/charmander_back.png"
        }
    },

    squirtle = {
        id = 7,
        name = "Squirtle",
        types = {"water"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 63,
        baseFriendship = 70,
        growthRate = "medium_slow",
        abilities = {"torrent"},
        hiddenAbility = "rain_dish",
        baseStats = {
            hp = 44,
            attack = 48,
            defense = 65,
            spAttack = 50,
            spDefense = 64,
            speed = 43
        },
        learnset = {
            [1] = {"tackle", "tail_whip"},
            [7] = {"water_gun"},
            [10] = {"withdraw"}
        },
        evolution = {
            method = "level",
            level = 16,
            into = "wartortle"
        },
        sprite = {
            front = "assets/pokemon/squirtle_front.png",
            back  = "assets/pokemon/squirtle_back.png"
        }
    }
}

--------------------------------------------------
-- Pokemon (RUNTIME INSTANCE)
--------------------------------------------------

Pokemon = {}
Pokemon.__index = Pokemon

function Pokemon:new(speciesId, level)
    local species = PokemonSpecies[speciesId]
    assert(species, "Unknown Pokemon species: " .. tostring(speciesId))

    local p = {
        speciesId = speciesId,
        species = species,
        name = species.name,
        nickname = species.name,
        level = level or 1,
        exp = 0,  -- will be set after calculating stats
        nature = "hardy",
        gender = Pokemon:rollGender(species.genderRatio),
        ability = species.abilities[1],
        friendship = species.baseFriendship,
        shiny = (math.random(1, 4096) == 1),
        ivs = {
            hp = math.random(0, 31),
            attack = math.random(0, 31),
            defense = math.random(0, 31),
            spAttack = math.random(0, 31),
            spDefense = math.random(0, 31),
            speed = math.random(0, 31)
        },
        evs = {
            hp = 0,
            attack = 0,
            defense = 0,
            spAttack = 0,
            spDefense = 0,
            speed = 0
        },
        status = nil,
        moves = {},
        heldItem = nil
    }

    setmetatable(p, Pokemon)

    p.stats = p:calculateStats()
    p.currentHP = p.stats.hp
    p:learnMovesForLevel()
    
    -- Initialize exp to the cumulative total for this level
    p.exp = p:getExpForLevel(p.level)

    return p
end

-- Reconstruct a Pokemon instance from saved data (after loading from JSON)
-- This ensures the metatable is set and methods are available
function Pokemon.fromSavedData(data)
    if not data or not data.speciesId then
        return nil
    end
    
    local species = PokemonSpecies[data.speciesId]
    if not species then
        return nil
    end
    
    -- Create a new instance with the saved data
    local p = {}
    for k, v in pairs(data) do
        p[k] = v
    end
    
    -- Ensure species reference is set
    p.species = species
    
    -- Add name property from species if not already set (for menu.lua compatibility)
    if not p.name then
        p.name = species.name
    end
    
    -- Set the metatable so methods are available
    setmetatable(p, Pokemon)
    
    return p
end

--------------------------------------------------
-- Pokemon Methods
--------------------------------------------------

function Pokemon:rollGender(ratio)
    if not ratio then return "genderless" end
    local roll = math.random() * 100
    return (roll <= ratio.male) and "male" or "female"
end

function Pokemon:calculateStats()
    local stats = {}
    local base = self.species.baseStats
    local lvl = self.level

    stats.hp = math.floor(((2 * base.hp + self.ivs.hp) * lvl) / 100) + lvl + 10

    for _, stat in ipairs({"attack", "defense", "spAttack", "spDefense", "speed"}) do
        stats[stat] = math.floor(((2 * base[stat] + self.ivs[stat]) * lvl) / 100) + 5
    end

    return stats
end

function Pokemon:learnMovesForLevel()
    for lvl, moveList in pairs(self.species.learnset) do
        if lvl <= self.level then
            for _, moveId in ipairs(moveList) do
                self:learnMove(moveId)
            end
        end
    end
end

function Pokemon:learnMove(moveId)
    for _, m in ipairs(self.moves) do
        if m == moveId then return end
    end

    if #self.moves >= 4 then return end
    table.insert(self.moves, moveId)
end

function Pokemon:isFainted()
    return self.currentHP <= 0
end

function Pokemon:heal(amount)
    self.currentHP = math.min(self.currentHP + amount, self.stats.hp)
end

function Pokemon:takeDamage(amount)
    self.currentHP = math.max(self.currentHP - amount, 0)
end

function Pokemon:gainExp(amount)
    self.exp = self.exp + amount
    local levelsGained = {}
    -- Check for level ups
    while self.level < 100 do
        local expForNext = self:getExpForLevel(self.level + 1)
        if self.exp >= expForNext then
            table.insert(levelsGained, self.level + 1)
            self:levelUp()
        else
            break
        end
    end
    return levelsGained
end

-- Calculate total experience needed to reach a specific level based on growth rate
function Pokemon:getExpForLevel(level)
    if level <= 1 then return 0 end
    
    local rate = self.species.growthRate
    local exp
    
    if rate == "fast" then
        -- 0.8 * n^3
        exp = math.floor(0.8 * level * level * level)
    elseif rate == "medium_fast" then
        -- n^3
        exp = level * level * level
    elseif rate == "medium_slow" then
        -- 1.2*n^3 - 15*n^2 + 100*n - 140
        exp = math.floor(1.2 * level * level * level - 15 * level * level + 100 * level - 140)
    elseif rate == "slow" then
        -- 1.25 * n^4
        exp = math.floor(1.25 * level * level * level * level)
    else
        -- fallback to medium_fast
        exp = level * level * level
    end
    
    return math.max(0, exp)
end

-- Handle leveling up: recalculate stats and learn new moves
function Pokemon:levelUp()
    self.level = self.level + 1
    -- Recalculate stats for the new level
    self.stats = self:calculateStats()
    -- Cap current HP to new max
    if self.currentHP > self.stats.hp then
        self.currentHP = self.stats.hp
    end
    -- Learn moves for this level
    self:learnMovesForLevel()
end

-- Calculate experience yield from defeating another Pokémon
-- Formula based on official Pokémon games
function Pokemon.calculateExpYield(defeatedPokemon, winnerLevel)
    if not defeatedPokemon or not defeatedPokemon.species then
        return 0
    end
    
    local baseExp = defeatedPokemon.species.baseExpYield or 0
    local defeatedLevel = defeatedPokemon.level or 1
    
    -- Basic formula: (baseExp * defeatedLevel) / 7
    local exp = math.floor((baseExp * defeatedLevel) / 7)
    
    -- Apply level scaling: penalize overleveled Pokémon, bonus for underleveled
    if winnerLevel and winnerLevel > defeatedLevel then
        -- Penalty for overleveled trainer
        exp = math.floor(exp * (2 * defeatedLevel + 5) / (winnerLevel + defeatedLevel + 5))
    elseif winnerLevel and winnerLevel < defeatedLevel then
        -- Bonus for underleveled trainer
        exp = math.floor(exp * (2 * defeatedLevel + 5) / (winnerLevel + defeatedLevel + 5))
    end
    
    return math.max(1, exp)
end

function Pokemon:__tostring()
    return self.nickname or "Pokemon"
end

return {
    PokemonSpecies = PokemonSpecies,
    Pokemon = Pokemon
}

