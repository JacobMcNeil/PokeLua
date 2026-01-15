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
            [1] = {"protect", "fly","hyper_beam", "mega_drain", "solar_beam" ,"thunder_shock","thunder_wave", "sleep_powder", "poison_powder", "confuse_ray","quick_attack","Swords Dance", "bite"},
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
            front = "tiled/sprites/pokemon_front/pikachu.png",
            back  = "tiled/sprites/pokemon_back/pikachu.png"
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
            front = "tiled/sprites/pokemon_front/eevee.png",
            back  = "tiled/sprites/pokemon_back/eevee.png"
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
            front = "tiled/sprites/pokemon_front/bulbasaur.png",
            back  = "tiled/sprites/pokemon_back/bulbasaur.png"
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
            front = "tiled/sprites/pokemon_front/charmander.png",
            back  = "tiled/sprites/pokemon_back/charmander.png"
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
            [10] = {"withdraw"},
            [11] = {"thunder_shock"}
        },
        evolution = {
            method = "level",
            level = 16,
            into = "wartortle"
        },
        sprite = {
            front = "tiled/sprites/pokemon_front/squirtle.png",
            back  = "tiled/sprites/pokemon_back/squirtle.png"
        }
    },

    --------------------------------------------------
    -- EVOLUTIONS
    --------------------------------------------------

    -- Pikachu evolution
    raichu = {
        id = 26,
        name = "Raichu",
        types = {"electric"},
        genderRatio = { male = 50, female = 50 },
        catchRate = 75,
        baseExpYield = 218,
        baseFriendship = 70,
        growthRate = "medium_fast",
        abilities = {"static"},
        hiddenAbility = "lightning_rod",
        baseStats = {
            hp = 60,
            attack = 90,
            defense = 55,
            spAttack = 90,
            spDefense = 80,
            speed = 110
        },
        learnset = {
            [1] = {"thunder_shock", "tail_whip", "quick_attack", "thunderbolt"}
        },
        evolution = nil,
        sprite = {
            front = "tiled/sprites/pokemon_front/raichu.png",
            back  = "tiled/sprites/pokemon_back/raichu.png"
        }
    },

    -- Bulbasaur line
    ivysaur = {
        id = 2,
        name = "Ivysaur",
        types = {"grass", "poison"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 142,
        baseFriendship = 70,
        growthRate = "medium_slow",
        abilities = {"overgrow"},
        hiddenAbility = "chlorophyll",
        baseStats = {
            hp = 60,
            attack = 62,
            defense = 63,
            spAttack = 80,
            spDefense = 80,
            speed = 60
        },
        learnset = {
            [1] = {"tackle", "growl", "vine_whip"},
            [20] = {"razor_leaf"},
            [28] = {"sleep_powder"}
        },
        evolution = {
            method = "level",
            level = 32,
            into = "venusaur"
        },
        sprite = {
            front = "tiled/sprites/pokemon_front/ivysaur.png",
            back  = "tiled/sprites/pokemon_back/ivysaur.png"
        }
    },

    venusaur = {
        id = 3,
        name = "Venusaur",
        types = {"grass", "poison"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 236,
        baseFriendship = 70,
        growthRate = "medium_slow",
        abilities = {"overgrow"},
        hiddenAbility = "chlorophyll",
        baseStats = {
            hp = 80,
            attack = 82,
            defense = 83,
            spAttack = 100,
            spDefense = 100,
            speed = 80
        },
        learnset = {
            [1] = {"tackle", "growl", "vine_whip", "razor_leaf"},
            [32] = {"solar_beam"}
        },
        evolution = nil,
        sprite = {
            front = "tiled/sprites/pokemon_front/venusaur.png",
            back  = "tiled/sprites/pokemon_back/venusaur.png"
        }
    },

    -- Charmander line
    charmeleon = {
        id = 5,
        name = "Charmeleon",
        types = {"fire"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 142,
        baseFriendship = 70,
        growthRate = "medium_slow",
        abilities = {"blaze"},
        hiddenAbility = "solar_power",
        baseStats = {
            hp = 58,
            attack = 64,
            defense = 58,
            spAttack = 80,
            spDefense = 65,
            speed = 80
        },
        learnset = {
            [1] = {"scratch", "growl", "ember"},
            [17] = {"dragon_rage"},
            [24] = {"slash"}
        },
        evolution = {
            method = "level",
            level = 36,
            into = "charizard"
        },
        sprite = {
            front = "tiled/sprites/pokemon_front/charmeleon.png",
            back  = "tiled/sprites/pokemon_back/charmeleon.png"
        }
    },

    charizard = {
        id = 6,
        name = "Charizard",
        types = {"fire", "flying"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 240,
        baseFriendship = 70,
        growthRate = "medium_slow",
        abilities = {"blaze"},
        hiddenAbility = "solar_power",
        baseStats = {
            hp = 78,
            attack = 84,
            defense = 78,
            spAttack = 109,
            spDefense = 85,
            speed = 100
        },
        learnset = {
            [1] = {"scratch", "growl", "ember", "slash"},
            [36] = {"flamethrower"},
            [46] = {"fire_blast"}
        },
        evolution = nil,
        sprite = {
            front = "tiled/sprites/pokemon_front/charizard.png",
            back  = "tiled/sprites/pokemon_back/charizard.png"
        }
    },

    -- Squirtle line
    wartortle = {
        id = 8,
        name = "Wartortle",
        types = {"water"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 142,
        baseFriendship = 70,
        growthRate = "medium_slow",
        abilities = {"torrent"},
        hiddenAbility = "rain_dish",
        baseStats = {
            hp = 59,
            attack = 63,
            defense = 80,
            spAttack = 65,
            spDefense = 80,
            speed = 58
        },
        learnset = {
            [1] = {"tackle", "tail_whip", "water_gun"},
            [20] = {"bite"},
            [28] = {"rapid_spin"}
        },
        evolution = {
            method = "level",
            level = 36,
            into = "blastoise"
        },
        sprite = {
            front = "tiled/sprites/pokemon_front/wartortle.png",
            back  = "tiled/sprites/pokemon_back/wartortle.png"
        }
    },

    blastoise = {
        id = 9,
        name = "Blastoise",
        types = {"water"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 239,
        baseFriendship = 70,
        growthRate = "medium_slow",
        abilities = {"torrent"},
        hiddenAbility = "rain_dish",
        baseStats = {
            hp = 79,
            attack = 83,
            defense = 100,
            spAttack = 85,
            spDefense = 105,
            speed = 78
        },
        learnset = {
            [1] = {"tackle", "tail_whip", "water_gun", "bite"},
            [36] = {"hydro_pump"},
            [42] = {"skull_bash"}
        },
        evolution = nil,
        sprite = {
            front = "tiled/sprites/pokemon_front/blastoise.png",
            back  = "tiled/sprites/pokemon_back/blastoise.png"
        }
    },

    -- Eevee evolutions
    vaporeon = {
        id = 134,
        name = "Vaporeon",
        types = {"water"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 184,
        baseFriendship = 70,
        growthRate = "medium_fast",
        abilities = {"water_absorb"},
        hiddenAbility = "hydration",
        baseStats = {
            hp = 130,
            attack = 65,
            defense = 60,
            spAttack = 110,
            spDefense = 95,
            speed = 65
        },
        learnset = {
            [1] = {"tackle", "tail_whip", "water_gun"},
            [20] = {"aurora_beam"},
            [36] = {"hydro_pump"}
        },
        evolution = nil,
        sprite = {
            front = "tiled/sprites/pokemon_front/vaporeon.png",
            back  = "tiled/sprites/pokemon_back/vaporeon.png"
        }
    },

    jolteon = {
        id = 135,
        name = "Jolteon",
        types = {"electric"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 184,
        baseFriendship = 70,
        growthRate = "medium_fast",
        abilities = {"volt_absorb"},
        hiddenAbility = "quick_feet",
        baseStats = {
            hp = 65,
            attack = 65,
            defense = 60,
            spAttack = 110,
            spDefense = 95,
            speed = 130
        },
        learnset = {
            [1] = {"tackle", "tail_whip", "thunder_shock"},
            [20] = {"double_kick"},
            [36] = {"thunder"}
        },
        evolution = nil,
        sprite = {
            front = "tiled/sprites/pokemon_front/jolteon.png",
            back  = "tiled/sprites/pokemon_back/jolteon.png"
        }
    },

    flareon = {
        id = 136,
        name = "Flareon",
        types = {"fire"},
        genderRatio = { male = 87.5, female = 12.5 },
        catchRate = 45,
        baseExpYield = 184,
        baseFriendship = 70,
        growthRate = "medium_fast",
        abilities = {"flash_fire"},
        hiddenAbility = "guts",
        baseStats = {
            hp = 65,
            attack = 130,
            defense = 60,
            spAttack = 95,
            spDefense = 110,
            speed = 65
        },
        learnset = {
            [1] = {"tackle", "tail_whip", "ember"},
            [20] = {"fire_spin"},
            [36] = {"flamethrower"}
        },
        evolution = nil,
        sprite = {
            front = "tiled/sprites/pokemon_front/flareon.png",
            back  = "tiled/sprites/pokemon_back/flareon.png"
        }
    },

    --------------------------------------------------
    -- TEST POKEMON (for debugging)
    --------------------------------------------------

    exp_dummy = {
        id = 9999,
        name = "EXP Dummy",
        types = {"normal"},
        genderRatio = { male = 50, female = 50 },
        catchRate = 255,
        baseExpYield = 5000,  -- Gives tons of EXP!
        baseFriendship = 70,
        growthRate = "fast",
        abilities = {"run_away"},
        hiddenAbility = nil,
        baseStats = {
            hp = 1,      -- Dies in one hit
            attack = 1,
            defense = 1,
            spAttack = 1,
            spDefense = 1,
            speed = 1
        },
        learnset = {
            [1] = {"splash"}
        },
        evolution = nil,
        sprite = {
            front = "tiled/sprites/pokemon_front/exp_dummy.png",
            back  = "tiled/sprites/pokemon_back/exp_dummy.png"
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
    local pendingEvolution = nil
    -- Check for level ups
    while self.level < 100 do
        local expForNext = self:getExpForLevel(self.level + 1)
        if self.exp >= expForNext then
            table.insert(levelsGained, self.level + 1)
            self:levelUp()
            -- Check if Pokemon can evolve after this level up
            local canEvolve, evolveInto = self:canEvolveByLevel()
            if canEvolve then
                pendingEvolution = evolveInto
            end
        else
            break
        end
    end
    return levelsGained, pendingEvolution
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

-- Check if this Pokemon can evolve by level
function Pokemon:canEvolveByLevel()
    local evo = self.species.evolution
    if not evo then return false end
    if evo.method == "level" and evo.level and self.level >= evo.level then
        return true, evo.into
    end
    return false
end

-- Check if this Pokemon can evolve with a specific item
function Pokemon:canEvolveWithItem(itemId)
    local evo = self.species.evolution
    if not evo then return false end
    
    if evo.method == "item" and evo.item == itemId then
        return true, evo.into
    end
    
    -- Handle branching evolutions (like Eevee)
    if evo.method == "branch" and evo.options then
        for _, opt in ipairs(evo.options) do
            if opt.method == "item" and opt.item == itemId then
                return true, opt.into
            end
        end
    end
    
    return false
end

-- Evolve this Pokemon into a new species
function Pokemon:evolve(newSpeciesId)
    local newSpecies = PokemonSpecies[newSpeciesId]
    if not newSpecies then
        return false, "Unknown species: " .. tostring(newSpeciesId)
    end
    
    local oldName = self.nickname
    local oldSpeciesName = self.species.name
    
    -- Update species
    self.speciesId = newSpeciesId
    self.species = newSpecies
    self.name = newSpecies.name
    
    -- Update nickname if it was the old species name
    if self.nickname == oldSpeciesName then
        self.nickname = newSpecies.name
    end
    
    -- Recalculate stats for the new species
    self.stats = self:calculateStats()
    
    -- Learn any new moves from the new species' learnset
    self:learnMovesForLevel()
    
    return true, oldName .. " evolved into " .. newSpecies.name .. "!"
end

return {
    PokemonSpecies = PokemonSpecies,
    Pokemon = Pokemon
}

