-- encounters.lua
-- Defines Pokemon encounters for each route
-- Routes are defined in Tiled as objects in the "routes" layer with an "id" property
-- Collision tiles (grass, water) determine encounter type

local M = {}

-------------------------------------------------
-- ENCOUNTER DATA STRUCTURE
-------------------------------------------------
-- Each route has grass and/or water encounters
-- Format: { species = "pokemon_id", minLevel = #, maxLevel = #, weight = # }
-- Weight is optional (defaults to 1) and determines relative encounter rate

M.routes = {
    -------------------------------------------------
    -- Route 29 (New Bark Town -> Cherrygrove City)
    -------------------------------------------------
    ["route_29"] = {
        grass = {
            { species = "pidgey",     minLevel = 2, maxLevel = 5, weight = 30 },
            { species = "sentret",    minLevel = 2, maxLevel = 5, weight = 30 },
            { species = "rattata",    minLevel = 2, maxLevel = 4, weight = 20 },
            { species = "hoothoot",   minLevel = 2, maxLevel = 4, weight = 10 },  -- Night only in real game
            { species = "hoppip",     minLevel = 3, maxLevel = 5, weight = 10 },
        },
        water = {
            -- Route 29 doesn't have water encounters in original games
        }
    },
    
    -------------------------------------------------
    -- Route 30 (Cherrygrove City -> Route 31)
    -------------------------------------------------
    ["route_30"] = {
        grass = {
            { species = "pidgey",     minLevel = 3, maxLevel = 6, weight = 30 },
            { species = "caterpie",   minLevel = 3, maxLevel = 5, weight = 20 },
            { species = "weedle",     minLevel = 3, maxLevel = 5, weight = 20 },
            { species = "metapod",    minLevel = 4, maxLevel = 6, weight = 10 },
            { species = "kakuna",     minLevel = 4, maxLevel = 6, weight = 10 },
            { species = "hoppip",     minLevel = 4, maxLevel = 6, weight = 10 },
        },
        water = {
            { species = "poliwag",    minLevel = 10, maxLevel = 15, weight = 60 },
            { species = "poliwhirl",  minLevel = 15, maxLevel = 20, weight = 30 },
            { species = "magikarp",   minLevel = 10, maxLevel = 15, weight = 10 },
        }
    },
    
    -------------------------------------------------
    -- Route 31 (Route 30 -> Violet City)
    -------------------------------------------------
    ["route_31"] = {
        grass = {
            { species = "pidgey",     minLevel = 4, maxLevel = 6, weight = 25 },
            { species = "caterpie",   minLevel = 4, maxLevel = 6, weight = 20 },
            { species = "weedle",     minLevel = 4, maxLevel = 6, weight = 20 },
            { species = "bellsprout", minLevel = 4, maxLevel = 6, weight = 15 },
            { species = "geodude",    minLevel = 4, maxLevel = 6, weight = 10 },
            { species = "hoppip",     minLevel = 5, maxLevel = 7, weight = 10 },
        },
        water = {
            { species = "poliwag",    minLevel = 10, maxLevel = 15, weight = 60 },
            { species = "poliwhirl",  minLevel = 15, maxLevel = 20, weight = 30 },
            { species = "magikarp",   minLevel = 10, maxLevel = 15, weight = 10 },
        }
    },
    
    -------------------------------------------------
    -- Route 32 (Violet City -> Union Cave)
    -------------------------------------------------
    ["route_32"] = {
        grass = {
            { species = "rattata",    minLevel = 6, maxLevel = 8, weight = 20 },
            { species = "ekans",      minLevel = 6, maxLevel = 8, weight = 20 },
            { species = "bellsprout", minLevel = 6, maxLevel = 8, weight = 20 },
            { species = "mareep",     minLevel = 6, maxLevel = 8, weight = 20 },
            { species = "hoppip",     minLevel = 6, maxLevel = 8, weight = 10 },
            { species = "wooper",     minLevel = 6, maxLevel = 8, weight = 10 },
        },
        water = {
            { species = "tentacool",  minLevel = 15, maxLevel = 20, weight = 40 },
            { species = "tentacruel", minLevel = 20, maxLevel = 25, weight = 10 },
            { species = "quagsire",   minLevel = 15, maxLevel = 25, weight = 30 },
            { species = "magikarp",   minLevel = 10, maxLevel = 20, weight = 20 },
        }
    },
    
    -------------------------------------------------
    -- Route 46 (Route 29 -> Blackthorn City area)
    -------------------------------------------------
    ["route_46"] = {
        grass = {
            { species = "geodude",    minLevel = 2, maxLevel = 5, weight = 30 },
            { species = "spearow",    minLevel = 2, maxLevel = 5, weight = 30 },
            { species = "rattata",    minLevel = 2, maxLevel = 5, weight = 20 },
            { species = "phanpy",     minLevel = 3, maxLevel = 5, weight = 20 },
        },
        water = {}
    },
    
    -------------------------------------------------
    -- Union Cave
    -------------------------------------------------
    ["union_cave"] = {
        grass = {
            { species = "geodude",    minLevel = 6, maxLevel = 10, weight = 25 },
            { species = "sandshrew",  minLevel = 6, maxLevel = 10, weight = 20 },
            { species = "zubat",      minLevel = 6, maxLevel = 10, weight = 30 },
            { species = "rattata",    minLevel = 6, maxLevel = 10, weight = 15 },
            { species = "onix",       minLevel = 6, maxLevel = 10, weight = 10 },
        },
        water = {
            { species = "wooper",     minLevel = 10, maxLevel = 15, weight = 40 },
            { species = "quagsire",   minLevel = 15, maxLevel = 20, weight = 30 },
            { species = "magikarp",   minLevel = 10, maxLevel = 15, weight = 30 },
        }
    },
    
    -------------------------------------------------
    -- New Bark Town (typically no wild encounters, but for testing)
    -------------------------------------------------
    ["new_bark_town"] = {
        grass = {},
        water = {
            { species = "tentacool",  minLevel = 20, maxLevel = 25, weight = 50 },
            { species = "tentacruel", minLevel = 25, maxLevel = 30, weight = 20 },
            { species = "magikarp",   minLevel = 15, maxLevel = 25, weight = 30 },
        }
    },
    
    -------------------------------------------------
    -- Cherrygrove City
    -------------------------------------------------
    ["cherrygrove_city"] = {
        grass = {},
        water = {
            { species = "tentacool",  minLevel = 20, maxLevel = 25, weight = 50 },
            { species = "tentacruel", minLevel = 25, maxLevel = 30, weight = 20 },
            { species = "magikarp",   minLevel = 15, maxLevel = 25, weight = 30 },
        }
    },
    
    -------------------------------------------------
    -- Violet City
    -------------------------------------------------
    ["violet_city"] = {
        grass = {},
        water = {
            { species = "poliwag",    minLevel = 15, maxLevel = 20, weight = 60 },
            { species = "poliwhirl",  minLevel = 20, maxLevel = 25, weight = 30 },
            { species = "magikarp",   minLevel = 10, maxLevel = 20, weight = 10 },
        }
    },
}

-------------------------------------------------
-- ENCOUNTER LOGIC
-------------------------------------------------

-- Get the encounter data for a specific route and terrain type
-- terrainType: "grass" or "water"
function M.getEncounterTable(routeId, terrainType)
    local route = M.routes[routeId]
    if not route then return nil end
    
    local encounters = route[terrainType]
    if not encounters or #encounters == 0 then return nil end
    
    return encounters
end

-- Roll for a random encounter from the encounter table
-- Returns: { species = string, level = number } or nil
function M.rollEncounter(routeId, terrainType)
    local encounters = M.getEncounterTable(routeId, terrainType)
    if not encounters then return nil end
    
    -- Calculate total weight
    local totalWeight = 0
    for _, enc in ipairs(encounters) do
        totalWeight = totalWeight + (enc.weight or 1)
    end
    
    if totalWeight <= 0 then return nil end
    
    -- Roll for encounter
    local roll = math.random(1, totalWeight)
    local cumulative = 0
    
    for _, enc in ipairs(encounters) do
        cumulative = cumulative + (enc.weight or 1)
        if roll <= cumulative then
            -- Determine level
            local minLevel = enc.minLevel or 1
            local maxLevel = enc.maxLevel or minLevel
            if minLevel > maxLevel then minLevel, maxLevel = maxLevel, minLevel end
            local level = math.random(minLevel, maxLevel)
            
            return {
                species = enc.species,
                level = level,
                minLevel = minLevel,  -- For repel checks
                maxLevel = maxLevel
            }
        end
    end
    
    -- Fallback to first encounter
    local enc = encounters[1]
    local minLevel = enc.minLevel or 1
    local maxLevel = enc.maxLevel or minLevel
    return {
        species = enc.species,
        level = math.random(minLevel, maxLevel),
        minLevel = minLevel,
        maxLevel = maxLevel
    }
end

-- Check if a route has any encounters for a terrain type
function M.hasEncounters(routeId, terrainType)
    local encounters = M.getEncounterTable(routeId, terrainType)
    return encounters and #encounters > 0
end

-- Get the minimum level of all encounters for a route/terrain (for repel check)
function M.getMinEncounterLevel(routeId, terrainType)
    local encounters = M.getEncounterTable(routeId, terrainType)
    if not encounters or #encounters == 0 then return 1 end
    
    local minLevel = math.huge
    for _, enc in ipairs(encounters) do
        local encMin = enc.minLevel or 1
        if encMin < minLevel then
            minLevel = encMin
        end
    end
    
    return minLevel ~= math.huge and minLevel or 1
end

-- Roll a wild party matching player party size and average level
-- Returns array of {species, level} entries with varied Pokemon
-- partySize: number of Pokemon to generate
-- targetLevel: the level to use for all wild Pokemon
function M.rollWildParty(routeId, terrainType, partySize, targetLevel)
    local encounters = M.getEncounterTable(routeId, terrainType)
    if not encounters or #encounters == 0 then return nil end
    
    partySize = partySize or 1
    targetLevel = targetLevel or 5
    
    -- Build weighted pool
    local totalWeight = 0
    for _, enc in ipairs(encounters) do
        totalWeight = totalWeight + (enc.weight or 1)
    end
    
    if totalWeight <= 0 then return nil end
    
    -- Roll for party, trying to avoid duplicates when possible
    local wildParty = {}
    local usedSpecies = {}
    local availableEncounters = #encounters
    
    for i = 1, partySize do
        -- Build pool excluding recently used species (if we have enough variety)
        local rollPool = {}
        local poolWeight = 0
        
        for _, enc in ipairs(encounters) do
            -- Allow duplicates only if we've used all available species
            local canUse = not usedSpecies[enc.species] or #wildParty >= availableEncounters
            if canUse then
                table.insert(rollPool, enc)
                poolWeight = poolWeight + (enc.weight or 1)
            end
        end
        
        -- If pool is empty (all species used), reset and allow any
        if #rollPool == 0 then
            rollPool = encounters
            poolWeight = totalWeight
        end
        
        -- Roll from pool
        local roll = math.random(1, poolWeight)
        local cumulative = 0
        local selected = rollPool[1]
        
        for _, enc in ipairs(rollPool) do
            cumulative = cumulative + (enc.weight or 1)
            if roll <= cumulative then
                selected = enc
                break
            end
        end
        
        -- Add to party with target level
        table.insert(wildParty, {
            species = selected.species,
            level = targetLevel
        })
        usedSpecies[selected.species] = true
    end
    
    return wildParty
end

return M
