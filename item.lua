-- item.lua
-- Complete item system for a Pokémon-style game (LÖVE / Lua)
-- Includes: ItemData, Item, Inventory (Bag), and ItemEffects

--------------------------------------------------
-- Item Target Types:
-- "pokemon" = requires selecting a Pokemon (healing items, vitamins)
-- "move" = requires selecting a Pokemon then a move (Ether, PP Up)
-- "self" = no target needed, affects player/field (Repel, Escape Rope)
-- "hold" = can be given to a Pokemon to hold (held items, berries)
--------------------------------------------------

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
        targetType = "pokemon",
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
        targetType = "pokemon",
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
        targetType = "pokemon",
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
        targetType = "enemy",
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
        targetType = "enemy",
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
        targetType = "pokemon",
        effect = { type = "stat_boost", stat = "attack", stages = 1 }
    },

    x_defense = {
        id = "x_defense",
        name = "X Defense",
        category = "battle_item",
        description = "Raises Defense during battle.",
        price = 550,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        targetType = "pokemon",
        effect = { type = "stat_boost", stat = "defense", stages = 1 }
    },

    x_speed = {
        id = "x_speed",
        name = "X Speed",
        category = "battle_item",
        description = "Raises Speed during battle.",
        price = 350,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        targetType = "pokemon",
        effect = { type = "stat_boost", stat = "speed", stages = 1 }
    },

    x_sp_atk = {
        id = "x_sp_atk",
        name = "X Sp. Atk",
        category = "battle_item",
        description = "Raises Sp. Atk during battle.",
        price = 350,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        targetType = "pokemon",
        effect = { type = "stat_boost", stat = "spAttack", stages = 1 }
    },

    x_sp_def = {
        id = "x_sp_def",
        name = "X Sp. Def",
        category = "battle_item",
        description = "Raises Sp. Def during battle.",
        price = 350,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        targetType = "pokemon",
        effect = { type = "stat_boost", stat = "spDefense", stages = 1 }
    },

    x_accuracy = {
        id = "x_accuracy",
        name = "X Accuracy",
        category = "battle_item",
        description = "Raises Accuracy during battle.",
        price = 950,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        targetType = "pokemon",
        effect = { type = "stat_boost", stat = "accuracy", stages = 1 }
    },

    dire_hit = {
        id = "dire_hit",
        name = "Dire Hit",
        category = "battle_item",
        description = "Raises critical hit ratio during battle.",
        price = 650,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        targetType = "pokemon",
        effect = { type = "crit_boost", stages = 1 }
    },

    guard_spec = {
        id = "guard_spec",
        name = "Guard Spec.",
        category = "battle_item",
        description = "Prevents stat reduction for 5 turns.",
        price = 700,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        targetType = "pokemon",
        effect = { type = "guard_spec", turns = 5 }
    },

    -- ADDITIONAL MEDICINE
    hyper_potion = {
        id = "hyper_potion",
        name = "Hyper Potion",
        category = "medicine",
        description = "Heals a Pokémon by 200 HP.",
        price = 1200,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "heal_hp", amount = 200 }
    },

    max_potion = {
        id = "max_potion",
        name = "Max Potion",
        category = "medicine",
        description = "Fully restores a Pokémon's HP.",
        price = 2500,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "heal_hp", amount = 9999 }
    },

    full_restore = {
        id = "full_restore",
        name = "Full Restore",
        category = "medicine",
        description = "Fully restores HP and cures all status.",
        price = 3000,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "full_restore" }
    },

    revive = {
        id = "revive",
        name = "Revive",
        category = "medicine",
        description = "Revives a fainted Pokémon to half HP.",
        price = 1500,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "revive", percent = 50 }
    },

    max_revive = {
        id = "max_revive",
        name = "Max Revive",
        category = "medicine",
        description = "Revives a fainted Pokémon to full HP.",
        price = 4000,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "revive", percent = 100 }
    },

    paralyze_heal = {
        id = "paralyze_heal",
        name = "Paralyze Heal",
        category = "medicine",
        description = "Cures paralysis.",
        price = 200,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "cure_status", status = "paralyzed" }
    },

    burn_heal = {
        id = "burn_heal",
        name = "Burn Heal",
        category = "medicine",
        description = "Cures burns.",
        price = 250,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "cure_status", status = "burned" }
    },

    ice_heal = {
        id = "ice_heal",
        name = "Ice Heal",
        category = "medicine",
        description = "Cures frozen status.",
        price = 250,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "cure_status", status = "frozen" }
    },

    awakening = {
        id = "awakening",
        name = "Awakening",
        category = "medicine",
        description = "Wakes up a sleeping Pokémon.",
        price = 250,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "cure_status", status = "asleep" }
    },

    full_heal = {
        id = "full_heal",
        name = "Full Heal",
        category = "medicine",
        description = "Cures any status condition.",
        price = 600,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "cure_all_status" }
    },

    -- PP RESTORING ITEMS
    ether = {
        id = "ether",
        name = "Ether",
        category = "medicine",
        description = "Restores 10 PP to one move.",
        price = 1200,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "move",
        effect = { type = "restore_pp", amount = 10, targetType = "single_move" }
    },

    max_ether = {
        id = "max_ether",
        name = "Max Ether",
        category = "medicine",
        description = "Fully restores PP to one move.",
        price = 2000,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "move",
        effect = { type = "restore_pp", amount = 9999, targetType = "single_move" }
    },

    elixir = {
        id = "elixir",
        name = "Elixir",
        category = "medicine",
        description = "Restores 10 PP to all moves.",
        price = 3000,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "pokemon",
        effect = { type = "restore_pp", amount = 10, targetType = "all_moves" }
    },

    max_elixir = {
        id = "max_elixir",
        name = "Max Elixir",
        category = "medicine",
        description = "Fully restores PP to all moves.",
        price = 4500,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "pokemon",
        effect = { type = "restore_pp", amount = 9999, targetType = "all_moves" }
    },

    -- PP ENHANCEMENT
    pp_up = {
        id = "pp_up",
        name = "PP Up",
        category = "medicine",
        description = "Raises max PP of a move by 20%.",
        price = 9800,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "move",
        effect = { type = "pp_up", stages = 1 }
    },

    pp_max = {
        id = "pp_max",
        name = "PP Max",
        category = "medicine",
        description = "Maximizes the PP of a move.",
        price = 9800,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "move",
        effect = { type = "pp_up", stages = 3 }
    },

    -- VITAMINS (EV boosters)
    hp_up = {
        id = "hp_up",
        name = "HP Up",
        category = "medicine",
        description = "Raises HP EVs by 10.",
        price = 9800,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "pokemon",
        effect = { type = "vitamin", stat = "hp", amount = 10 }
    },

    protein = {
        id = "protein",
        name = "Protein",
        category = "medicine",
        description = "Raises Attack EVs by 10.",
        price = 9800,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "pokemon",
        effect = { type = "vitamin", stat = "attack", amount = 10 }
    },

    iron = {
        id = "iron",
        name = "Iron",
        category = "medicine",
        description = "Raises Defense EVs by 10.",
        price = 9800,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "pokemon",
        effect = { type = "vitamin", stat = "defense", amount = 10 }
    },

    calcium = {
        id = "calcium",
        name = "Calcium",
        category = "medicine",
        description = "Raises Sp. Atk EVs by 10.",
        price = 9800,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "pokemon",
        effect = { type = "vitamin", stat = "spAttack", amount = 10 }
    },

    zinc = {
        id = "zinc",
        name = "Zinc",
        category = "medicine",
        description = "Raises Sp. Def EVs by 10.",
        price = 9800,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "pokemon",
        effect = { type = "vitamin", stat = "spDefense", amount = 10 }
    },

    carbos = {
        id = "carbos",
        name = "Carbos",
        category = "medicine",
        description = "Raises Speed EVs by 10.",
        price = 9800,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "pokemon",
        effect = { type = "vitamin", stat = "speed", amount = 10 }
    },

    rare_candy = {
        id = "rare_candy",
        name = "Rare Candy",
        category = "medicine",
        description = "Raises a Pokémon's level by 1.",
        price = 4800,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "pokemon",
        effect = { type = "rare_candy" }
    },

    -- FIELD ITEMS
    repel = {
        id = "repel",
        name = "Repel",
        category = "misc",
        description = "Prevents weak wild encounters for 100 steps.",
        price = 350,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "self",
        effect = { type = "repel", steps = 100 }
    },

    super_repel = {
        id = "super_repel",
        name = "Super Repel",
        category = "misc",
        description = "Prevents weak wild encounters for 200 steps.",
        price = 500,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "self",
        effect = { type = "repel", steps = 200 }
    },

    max_repel = {
        id = "max_repel",
        name = "Max Repel",
        category = "misc",
        description = "Prevents weak wild encounters for 250 steps.",
        price = 700,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "self",
        effect = { type = "repel", steps = 250 }
    },

    escape_rope = {
        id = "escape_rope",
        name = "Escape Rope",
        category = "misc",
        description = "Returns you to your last heal location.",
        price = 550,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "self",
        effect = { type = "escape_rope" }
    },

    -- ADDITIONAL POKE BALLS
    ultraball = {
        id = "ultraball",
        name = "Ultra Ball",
        category = "pokeball",
        description = "An ultra-high performance Poké Ball.",
        price = 1200,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        targetType = "enemy",
        effect = { type = "catch", modifier = 2.0 }
    },

    masterball = {
        id = "masterball",
        name = "Master Ball",
        category = "pokeball",
        description = "The best Poké Ball. It never fails.",
        price = 0,
        stackLimit = 1,
        consumable = true,
        usableIn = { overworld = false, battle = true },
        targetType = "enemy",
        effect = { type = "catch", modifier = 255 }
    },

    -- HELD ITEMS (non-consumable, attach to Pokemon)
    leftovers = {
        id = "leftovers",
        name = "Leftovers",
        category = "held_item",
        description = "Held: Restores 1/16 HP each turn.",
        price = 4000,
        stackLimit = 99,
        consumable = false,
        usableIn = { overworld = true, battle = false },
        targetType = "hold",
        effect = { type = "held_item", heldEffect = "leftovers" }
    },

    oran_berry = {
        id = "oran_berry",
        name = "Oran Berry",
        category = "berry",
        description = "Restores 10 HP. Auto-use when held below 50% HP.",
        price = 100,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "berry_heal", amount = 10 },
        heldEffect = "oran_berry"
    },

    sitrus_berry = {
        id = "sitrus_berry",
        name = "Sitrus Berry",
        category = "berry",
        description = "Restores 25% HP. Auto-use when held below 50% HP.",
        price = 200,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "berry_heal", percent = 25 },
        heldEffect = "sitrus_berry"
    },

    lum_berry = {
        id = "lum_berry",
        name = "Lum Berry",
        category = "berry",
        description = "Cures any status condition. Auto-use when held.",
        price = 500,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = true },
        targetType = "pokemon",
        effect = { type = "cure_all_status" },
        heldEffect = "lum_berry"
    },

    choice_band = {
        id = "choice_band",
        name = "Choice Band",
        category = "held_item",
        description = "Held: Boosts Attack 50% but locks move.",
        price = 4000,
        stackLimit = 99,
        consumable = false,
        usableIn = { overworld = true, battle = false },
        targetType = "hold",
        effect = { type = "held_item", heldEffect = "choice_band" }
    },

    choice_specs = {
        id = "choice_specs",
        name = "Choice Specs",
        category = "held_item",
        description = "Held: Boosts Sp. Atk 50% but locks move.",
        price = 4000,
        stackLimit = 99,
        consumable = false,
        usableIn = { overworld = true, battle = false },
        targetType = "hold",
        effect = { type = "held_item", heldEffect = "choice_specs" }
    },

    choice_scarf = {
        id = "choice_scarf",
        name = "Choice Scarf",
        category = "held_item",
        description = "Held: Boosts Speed 50% but locks move.",
        price = 4000,
        stackLimit = 99,
        consumable = false,
        usableIn = { overworld = true, battle = false },
        targetType = "hold",
        effect = { type = "held_item", heldEffect = "choice_scarf" }
    },

    life_orb = {
        id = "life_orb",
        name = "Life Orb",
        category = "held_item",
        description = "Held: Boosts moves 30% but takes recoil.",
        price = 4000,
        stackLimit = 99,
        consumable = false,
        usableIn = { overworld = true, battle = false },
        targetType = "hold",
        effect = { type = "held_item", heldEffect = "life_orb" }
    },

    focus_sash = {
        id = "focus_sash",
        name = "Focus Sash",
        category = "held_item",
        description = "Held: Survives one-hit KO at 1 HP.",
        price = 4000,
        stackLimit = 99,
        consumable = true,
        usableIn = { overworld = true, battle = false },
        targetType = "hold",
        effect = { type = "held_item", heldEffect = "focus_sash" }
    },

    black_sludge = {
        id = "black_sludge",
        name = "Black Sludge",
        category = "held_item",
        description = "Held: Poison types heal; others take damage.",
        price = 4000,
        stackLimit = 99,
        consumable = false,
        usableIn = { overworld = true, battle = false },
        targetType = "hold",
        effect = { type = "held_item", heldEffect = "black_sludge" }
    },

    exp_share = {
        id = "exp_share",
        name = "Exp. Share",
        category = "held_item",
        description = "Held: Shares 50% EXP with holder even when not battling.",
        price = 0,
        stackLimit = 99,
        consumable = false,
        usableIn = { overworld = true, battle = false },
        targetType = "hold",
        effect = { type = "held_item", heldEffect = "exp_share" }
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
        targetType = "pokemon",
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
        targetType = "pokemon",
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
        targetType = "pokemon",
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
        targetType = "pokemon",
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
        targetType = "self",
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
        held_item = {},
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

    -- Directly reduce quantity (bypasses consumable check)
    item.quantity = math.max(item.quantity - (amount or 1), 0)

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

-- Berry heal effect (can heal flat amount or percentage)
function ItemEffects.berry_heal(ctx)
    local pokemon = ctx.target
    if pokemon:isFainted() then 
        return false, pokemon.nickname .. " is fainted and can't be healed."
    end
    
    local oldHP = pokemon.currentHP
    local maxHP = pokemon.stats.hp
    
    if oldHP >= maxHP then
        return false, pokemon.nickname .. "'s HP is already full."
    end
    
    local healAmount
    if ctx.effect.percent then
        healAmount = math.floor(maxHP * ctx.effect.percent / 100)
    else
        healAmount = ctx.effect.amount or 10
    end
    
    pokemon:heal(healAmount)
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

-- Full restore: heals HP and cures all status
function ItemEffects.full_restore(ctx)
    local pokemon = ctx.target
    if pokemon:isFainted() then 
        return false, pokemon.nickname .. " is fainted!"
    end
    
    local oldHP = pokemon.currentHP
    local maxHP = pokemon.stats.hp
    local wasFullHP = oldHP >= maxHP
    local hadStatus = pokemon.status ~= nil
    
    if wasFullHP and not hadStatus then
        return false, pokemon.nickname .. " is already at full health!"
    end
    
    -- Heal to full HP
    pokemon:heal(maxHP)
    local restored = pokemon.currentHP - oldHP
    
    -- Cure all status
    local statusCured = pokemon.status
    pokemon.status = nil
    pokemon.sleepTurns = nil
    pokemon.badlyPoisonedTurns = nil
    
    if restored > 0 and statusCured then
        return true, pokemon.nickname .. " recovered " .. restored .. " HP and was cured of " .. statusCured .. "!"
    elseif restored > 0 then
        return true, pokemon.nickname .. " recovered " .. restored .. " HP!"
    else
        return true, pokemon.nickname .. " was cured of " .. statusCured .. "!"
    end
end

-- Cure all status conditions
function ItemEffects.cure_all_status(ctx)
    local pokemon = ctx.target
    if not pokemon.status then
        return false, pokemon.nickname .. " has no status condition."
    end
    
    local statusCured = pokemon.status
    pokemon.status = nil
    pokemon.sleepTurns = nil
    pokemon.badlyPoisonedTurns = nil
    
    return true, pokemon.nickname .. " was cured of " .. statusCured .. "!"
end

-- Revive a fainted Pokemon
function ItemEffects.revive(ctx)
    local pokemon = ctx.target
    if not pokemon:isFainted() then
        return false, pokemon.nickname .. " isn't fainted!"
    end
    
    local percent = ctx.effect.percent or 50
    local maxHP = pokemon.stats.hp
    local healAmount = math.floor(maxHP * percent / 100)
    healAmount = math.max(healAmount, 1)
    
    pokemon.currentHP = healAmount
    pokemon.status = nil
    pokemon.sleepTurns = nil
    pokemon.badlyPoisonedTurns = nil
    
    if percent >= 100 then
        return true, pokemon.nickname .. " was revived to full HP!"
    else
        return true, pokemon.nickname .. " was revived!"
    end
end

-- Critical hit stage boost
function ItemEffects.crit_boost(ctx)
    local battlePokemon = ctx.target
    if not battlePokemon.critStage then
        battlePokemon.critStage = 0
    end
    local oldStage = battlePokemon.critStage
    battlePokemon.critStage = math.min(battlePokemon.critStage + (ctx.effect.stages or 1), 3)
    
    if battlePokemon.critStage > oldStage then
        return true, battlePokemon.nickname .. " is getting pumped!"
    else
        return false, "It won't have any effect!"
    end
end

-- Guard Spec effect (prevent stat reduction)
function ItemEffects.guard_spec(ctx)
    local battlePokemon = ctx.target
    battlePokemon.guardSpec = ctx.effect.turns or 5
    return true, battlePokemon.nickname .. "'s team is protected from stat drops!"
end

-- Restore PP to moves
function ItemEffects.restore_pp(ctx)
    local pokemon = ctx.target
    local amount = ctx.effect.amount or 10
    local targetType = ctx.effect.targetType or "single_move"
    local moveIndex = ctx.moveIndex -- For single move restoration
    
    if targetType == "single_move" then
        -- Restore PP to one specific move
        if not moveIndex then
            return false, "No move selected."
        end
        
        if not pokemon._move_instances or not pokemon._move_instances[moveIndex] then
            return false, "Invalid move."
        end
        
        local move = pokemon._move_instances[moveIndex]
        if type(move) ~= "table" or not move.maxPP then
            return false, "Invalid move."
        end
        
        local oldPP = move.pp or 0
        local maxPP = move.maxPP or 10
        
        if oldPP >= maxPP then
            return false, (move.name or "Move") .. "'s PP is already full."
        end
        
        move.pp = math.min(oldPP + amount, maxPP)
        local restored = move.pp - oldPP
        
        return true, (move.name or "Move") .. " recovered " .. restored .. " PP!"
    else
        -- Restore PP to all moves
        if not pokemon._move_instances then
            return false, pokemon.nickname .. " has no moves."
        end
        
        local totalRestored = 0
        for i = 1, 4 do
            local move = pokemon._move_instances[i]
            if type(move) == "table" and move.maxPP then
                local oldPP = move.pp or 0
                local maxPP = move.maxPP or 10
                if oldPP < maxPP then
                    move.pp = math.min(oldPP + amount, maxPP)
                    totalRestored = totalRestored + (move.pp - oldPP)
                end
            end
        end
        
        if totalRestored == 0 then
            return false, "PP is already full for all moves."
        end
        
        return true, pokemon.nickname .. "'s moves recovered " .. totalRestored .. " PP total!"
    end
end

-- PP Up: Permanently increase max PP of a move
function ItemEffects.pp_up(ctx)
    local pokemon = ctx.target
    local stages = ctx.effect.stages or 1
    local moveIndex = ctx.moveIndex
    
    if not moveIndex then
        return false, "No move selected."
    end
    
    if not pokemon._move_instances or not pokemon._move_instances[moveIndex] then
        return false, "Invalid move."
    end
    
    local move = pokemon._move_instances[moveIndex]
    if type(move) ~= "table" or not move.maxPP then
        return false, "Invalid move."
    end
    
    -- Each PP Up increases max PP by 20%, up to 60% (3 stages)
    local basePP = move.basePP or move.maxPP or 10
    move.ppStages = (move.ppStages or 0) + stages
    move.ppStages = math.min(move.ppStages, 3)
    
    local newMaxPP = math.floor(basePP * (1 + 0.2 * move.ppStages))
    
    if move.maxPP >= newMaxPP then
        return false, (move.name or "Move") .. "'s PP is already maxed out!"
    end
    
    move.basePP = basePP
    move.maxPP = newMaxPP
    move.pp = move.maxPP -- Fill PP to new max
    
    return true, (move.name or "Move") .. "'s max PP was raised!"
end

-- Vitamins: Boost EVs
function ItemEffects.vitamin(ctx)
    local pokemon = ctx.target
    local stat = ctx.effect.stat
    local amount = ctx.effect.amount or 10
    
    if not pokemon.evs then
        pokemon.evs = { hp = 0, attack = 0, defense = 0, spAttack = 0, spDefense = 0, speed = 0 }
    end
    
    -- Calculate total EVs
    local totalEVs = 0
    for _, v in pairs(pokemon.evs) do
        totalEVs = totalEVs + v
    end
    
    -- Max total EVs is 510, max per stat is 252
    local currentEV = pokemon.evs[stat] or 0
    
    if totalEVs >= 510 then
        return false, pokemon.nickname .. " can't gain any more EVs!"
    end
    
    if currentEV >= 252 then
        return false, pokemon.nickname .. "'s " .. stat .. " EVs are maxed out!"
    end
    
    -- Calculate how much we can actually add
    local maxAdd = math.min(amount, 252 - currentEV, 510 - totalEVs)
    
    if maxAdd <= 0 then
        return false, "It won't have any effect!"
    end
    
    pokemon.evs[stat] = currentEV + maxAdd
    
    -- Recalculate stats with new EVs
    pokemon.stats = pokemon:calculateStats()
    
    local statNames = {
        hp = "HP",
        attack = "Attack",
        defense = "Defense",
        spAttack = "Sp. Atk",
        spDefense = "Sp. Def",
        speed = "Speed"
    }
    
    return true, pokemon.nickname .. "'s " .. (statNames[stat] or stat) .. " went up!"
end

-- Rare Candy: Level up Pokemon
function ItemEffects.rare_candy(ctx)
    local pokemon = ctx.target
    
    if pokemon:isFainted() then
        return false, pokemon.nickname .. " is fainted!"
    end
    
    if pokemon.level >= 100 then
        return false, pokemon.nickname .. " is already at max level!"
    end
    
    local oldLevel = pokemon.level
    pokemon:levelUp()
    
    -- Check for evolution
    local canEvolve, evolveInto = pokemon:canEvolveByLevel()
    
    local message = pokemon.nickname .. " grew to Lv. " .. pokemon.level .. "!"
    if canEvolve then
        message = message .. " (Ready to evolve!)"
    end
    
    return true, message, { pendingEvolution = evolveInto }
end

-- Repel effect: prevent weak wild encounters
function ItemEffects.repel(ctx)
    local steps = ctx.effect.steps or 100
    
    if ctx.player then
        ctx.player.repelSteps = (ctx.player.repelSteps or 0) + steps
        return true, "The Repel's effect will last for " .. steps .. " steps!"
    end
    
    -- If using flags system
    if ctx.flags then
        ctx.flags.repelSteps = (ctx.flags.repelSteps or 0) + steps
        return true, "The Repel's effect will last for " .. steps .. " steps!"
    end
    
    return true, "The Repel's effect will last for " .. steps .. " steps!"
end

-- Escape Rope: Return to last heal location
function ItemEffects.escape_rope(ctx)
    -- This effect is handled by the game/main module
    -- Here we just return success and let the main module handle the teleport
    if ctx.player and ctx.player.lastHealLocation then
        return true, "Used Escape Rope!", { escapeRope = true }
    end
    
    return false, "Cannot use Escape Rope here!"
end

-- Held item: Equip item to Pokemon
function ItemEffects.held_item(ctx)
    local pokemon = ctx.target
    local heldEffect = ctx.effect.heldEffect
    local item = ctx.item
    
    if not pokemon then
        return false, "No Pokémon selected."
    end
    
    -- Check if Pokemon already has a held item
    local oldItem = pokemon.heldItem
    
    -- Equip the new held item
    pokemon.heldItem = {
        id = item and item.id,
        effect = heldEffect
    }
    
    local message = pokemon.nickname .. " is now holding " .. (item and item.data and item.data.name or "the item") .. "!"
    
    if oldItem then
        message = pokemon.nickname .. " swapped " .. (oldItem.id or "item") .. " for " .. (item and item.data and item.data.name or "the item") .. "!"
    end
    
    return true, message, { swappedItem = oldItem }
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

    local result, message, extra = handler({
        target = context.target,
        battle = context.battle,
        player = context.player,
        flags = context.flags,
        effect = item.data.effect,
        moveIndex = context.moveIndex,  -- For PP restoration items
        item = item  -- Reference to the item being used
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

    -- For held_item effects, don't consume since it's being equipped
    if effectType == "held_item" then
        if result then
            item:consume(1)
        end
        return result, message, extra
    end

    -- For all other effects (evolve, heal_hp, cure_status, stat_boost, etc.)
    -- result is boolean with message
    if result then
        item:consume(1)
    end

    return result, message, extra
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
