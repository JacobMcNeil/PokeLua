-- item.lua
-- Complete item system for a Pokémon-style game (LÖVE / Lua)
-- Includes: ItemData, Item, Inventory (Bag), and ItemEffects

--------------------------------------------------
-- ItemData (STATIC DEFINITIONS)
--------------------------------------------------

ItemData = {

    -- MEDICINE
    potion = {
        id = "potion",
        name = "Potion",
        category = "medicine",
        description = "Heals a Pokémon by 20 HP.",
        price = 300,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        effect = { type = "heal_hp", amount = 20 }
    },

    super_potion = {
        id = "super_potion",
        name = "Super Potion",
        category = "medicine",
        description = "Heals a Pokémon by 50 HP.",
        price = 700,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        effect = { type = "heal_hp", amount = 50 }
    },

    antidote = {
        id = "antidote",
        name = "Antidote",
        category = "medicine",
        description = "Cures poison.",
        price = 100,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        effect = { type = "cure_status", status = "poison" }
    },

    -- POKÉ BALLS
    pokeball = {
        id = "pokeball",
        name = "Poké Ball",
        category = "pokeball",
        description = "A device for catching wild Pokémon.",
        price = 200,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        effect = { type = "catch", modifier = 1.0 }
    },

    greatball = {
        id = "greatball",
        name = "Great Ball",
        category = "pokeball",
        description = "Better at catching Pokémon than a Poké Ball.",
        price = 600,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        effect = { type = "catch", modifier = 1.5 }
    },

    -- BATTLE ITEMS
    x_attack = {
        id = "x_attack",
        name = "X Attack",
        category = "battle_item",
        description = "Raises Attack during battle.",
        price = 500,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        effect = { type = "stat_boost", stat = "attack", stages = 1 }
    },

    -- EVOLUTION STONES
    fire_stone = {
        id = "fire_stone",
        name = "Fire Stone",
        category = "misc",
        description = "Makes certain species of Pokémon evolve.",
        price = 2100,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        effect = { type = "evolve", stone = "fire_stone" }
    },

    water_stone = {
        id = "water_stone",
        name = "Water Stone",
        category = "misc",
        description = "Makes certain species of Pokémon evolve.",
        price = 2100,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        effect = { type = "evolve", stone = "water_stone" }
    },

    thunder_stone = {
        id = "thunder_stone",
        name = "Thunder Stone",
        category = "misc",
        description = "Makes certain species of Pokémon evolve.",
        price = 2100,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        effect = { type = "evolve", stone = "thunder_stone" }
    },

    leaf_stone = {
        id = "leaf_stone",
        name = "Leaf Stone",
        category = "misc",
        description = "Makes certain species of Pokémon evolve.",
        price = 2100,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        effect = { type = "evolve", stone = "leaf_stone" }
    },

    moon_stone = {
        id = "moon_stone",
        name = "Moon Stone",
        category = "misc",
        description = "Makes certain species of Pokémon evolve.",
        price = 2100,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        effect = { type = "evolve", stone = "moon_stone" }
    },

    -- KEY ITEM
    bicycle = {
        id = "bicycle",
        name = "Bicycle",
        category = "key_item",
        description = "Allows faster movement.",
        price = 0,
        stackLimit = 1,
        consumable = false,
        usableIn = { overworld = true, battle = false },
        effect = { type = "toggle_flag", flag = "has_bicycle" }
    }
}

--------------------------------------------------
-- Item (RUNTIME STACK)
--------------------------------------------------

local Item = {}
Item.__index = Item

function Item:new(itemId, quantity)
    local data = ItemData[itemId]
    assert(data, "Unknown item: " .. tostring(itemId))

    return setmetatable({
        id = itemId,
        data = data,
        quantity = quantity or 1
    }, Item)
end

function Item:canUse(context)
    return self.data.usableIn[context] == true
end

function Item:consume(amount)
    if not self.data.consumable then return end
    self.quantity = math.max(self.quantity - (amount or 1), 0)
end

--------------------------------------------------
-- Inventory (BAG)
--------------------------------------------------

local Inventory = {}
Inventory.__index = Inventory

function Inventory:new()
    return setmetatable({
        medicine = {},
        pokeball = {},
        battle_item = {},
        key_item = {},
        tm = {},
        berry = {},
        misc = {}
    }, Inventory)
end

function Inventory:add(itemId, amount)
    local data = ItemData[itemId]
    assert(data, "Unknown item: " .. tostring(itemId))

    local pocket = data.category
    local items = self[pocket]

    items[itemId] = items[itemId] or Item:new(itemId, 0)
    local item = items[itemId]

    item.quantity = math.min(item.quantity + (amount or 1), data.stackLimit)
end

function Inventory:remove(itemId, amount)
    local data = ItemData[itemId]
    if not data then return end

    local items = self[data.category]
    local item = items[itemId]
    if not item then return end

    item:consume(amount)

    if item.quantity <= 0 then
        items[itemId] = nil
    end
end

function Inventory:getPocket(category)
    return self[category] or {}
end

--------------------------------------------------
-- Item Effects (LOGIC)
--------------------------------------------------

local ItemEffects = {}

function ItemEffects.heal_hp(ctx)
    local pokemon = ctx.target
    if pokemon:isFainted() then 
        return false, pokemon.nickname .. " is fainted and can't be healed."
    end
    
    local oldHP = pokemon.currentHP
    local maxHP = pokemon.stats.hp
    
    if oldHP >= maxHP then
        return false, pokemon.nickname .. "'s HP is already full."
    end
    
    pokemon:heal(ctx.effect.amount)
    local restored = pokemon.currentHP - oldHP
    
    return true, pokemon.nickname .. " recovered " .. restored .. " HP!"
end

function ItemEffects.cure_status(ctx)
    local pokemon = ctx.target
    if pokemon.status == ctx.effect.status then
        pokemon.status = nil
        return true, pokemon.nickname .. "'s " .. ctx.effect.status .. " was cured!"
    end
    return false, pokemon.nickname .. " doesn't have " .. ctx.effect.status .. "."
end

function ItemEffects.stat_boost(ctx)
    local battlePokemon = ctx.target
    battlePokemon.statStages[ctx.effect.stat] =
        battlePokemon.statStages[ctx.effect.stat] + ctx.effect.stages
    local statName = ctx.effect.stat:gsub("^%l", string.upper)
    return true, battlePokemon.nickname .. "'s " .. statName .. " rose!"
end

function ItemEffects.catch(ctx)
    -- ctx.target = the wild Pokemon to catch
    -- ctx.effect.modifier = ball modifier (1.0 for Pokeball, 1.5 for Great Ball, etc.)
    -- ctx.player = the player object (to add Pokemon to party)
    -- Returns: "caught", "failed", or "party_full"
    
    local pokemon = ctx.target
    local ballModifier = ctx.effect.modifier or 1.0
    local player = ctx.player
    
    if not pokemon then return "failed" end
    
    -- Get catch rate from species data
    local catchRate = 45 -- Default catch rate
    if pokemon.species and pokemon.species.catchRate then
        catchRate = pokemon.species.catchRate
    end
    
    -- Calculate catch probability using simplified Gen III-IV formula
    -- a = ((3 * maxHP - 2 * currentHP) * catchRate * ballModifier) / (3 * maxHP)
    local maxHP = (pokemon.stats and pokemon.stats.hp) or pokemon.maxHp or 100
    local currentHP = pokemon.currentHP or maxHP
    
    -- Ensure HP values are valid
    if currentHP < 1 then currentHP = 1 end
    if maxHP < 1 then maxHP = 100 end
    
    local a = ((3 * maxHP - 2 * currentHP) * catchRate * ballModifier) / (3 * maxHP)
    
    -- Status condition bonuses (if implemented)
    local statusBonus = 1.0
    if pokemon.status then
        if pokemon.status == "sleep" or pokemon.status == "freeze" then
            statusBonus = 2.5
        elseif pokemon.status == "paralysis" or pokemon.status == "poison" or pokemon.status == "burn" then
            statusBonus = 1.5
        end
    end
    a = a * statusBonus
    
    -- Cap at 255 (guaranteed catch)
    if a >= 255 then
        -- Guaranteed catch
        return ItemEffects._finalizeCatch(pokemon, player)
    end
    
    -- Calculate shake probability
    -- b = 1048560 / sqrt(sqrt(16711680 / a))
    -- Each shake succeeds if random(0, 65535) < b
    -- For simplicity, we'll do a single roll based on catch rate percentage
    local catchChance = (a / 255) * 100
    
    -- Roll for capture
    local roll = math.random(1, 100)
    
    if roll <= catchChance then
        return ItemEffects._finalizeCatch(pokemon, player)
    else
        return "failed"
    end
end

-- Helper function to add caught Pokemon to party or box
function ItemEffects._finalizeCatch(pokemon, player)
    if not player then return "caught" end
    
    -- Check if party has space (max 6 Pokemon)
    if not player.party then
        player.party = {}
    end
    
    if #player.party >= 6 then
        -- Party is full - send to box
        if not player.box then
            player.box = {}
        end
        table.insert(player.box, pokemon)
        return "sent_to_box"
    end
    
    -- Add Pokemon to party
    table.insert(player.party, pokemon)
    return "caught"
end

function ItemEffects.toggle_flag(ctx)
    ctx.flags[ctx.effect.flag] = true
    return true, "Used item."
end

function ItemEffects.evolve(ctx)
    -- ctx.target = the Pokemon to evolve
    -- ctx.effect.stone = the stone id being used
    local pokemon = ctx.target
    local stone = ctx.effect.stone
    
    if not pokemon then return false, "No Pokemon selected" end
    
    -- Check if this Pokemon can evolve with this stone
    local canEvolve, evolveInto = pokemon:canEvolveWithItem(stone)
    
    if not canEvolve then
        return false, pokemon.nickname .. " cannot use this item."
    end
    
    -- Perform the evolution
    local success, message = pokemon:evolve(evolveInto)
    
    if success then
        return true, message
    else
        return false, message
    end
end

--------------------------------------------------
-- Item Usage Entry Point
--------------------------------------------------

function useItem(item, context)
    if not item:canUse(context.type) then 
        return false, "Can't use that here."
    end

    local effectType = item.data.effect.type
    local handler = ItemEffects[effectType]
    if not handler then 
        return false, "Item has no effect."
    end

    local result, message = handler({
        target = context.target,
        battle = context.battle,
        player = context.player,
        flags = context.flags,
        effect = item.data.effect
    })

    -- For catch effects, result is a string status
    if effectType == "catch" then
        if result == "caught" or result == "party_full" or result == "sent_to_box" then
            item:consume(1)
            return result
        else
            item:consume(1) -- Ball is consumed even on failure
            return result
        end
    end

    -- For all other effects (evolve, heal_hp, cure_status, stat_boost, etc.)
    -- result is boolean with message
    if result then
        item:consume(1)
    end

    return result, message
end

--------------------------------------------------
-- Module Export
--------------------------------------------------

return {
    ItemData = ItemData,
    Item = Item,
    Inventory = Inventory,
    ItemEffects = ItemEffects,
    useItem = useItem
}
