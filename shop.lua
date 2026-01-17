-- shop.lua
-- Shop system for buying and selling items

local UI = require("ui")
local log = require("log")

local M = {}

--------------------------------------------------
-- ShopData (STATIC DEFINITIONS)
-- Shops are referenced by ID for map lookups
--------------------------------------------------

local ShopData = {
    -- PokeMart - basic items
    pokemart = {
        id = "pokemart",
        name = "Poké Mart",
        greeting = "Welcome! How may I help you?",
        farewell = "Please come again!",
        inventory = {
            { itemId = "pokeball", stock = -1 },     -- -1 = unlimited
            { itemId = "greatball", stock = -1 },
            { itemId = "ultraball", stock = -1 },
            { itemId = "potion", stock = -1 },
            { itemId = "super_potion", stock = -1 },
            { itemId = "hyper_potion", stock = -1 },
            { itemId = "max_potion", stock = -1 },
            { itemId = "full_restore", stock = -1 },
            { itemId = "revive", stock = -1 },
            { itemId = "antidote", stock = -1 },
            { itemId = "paralyze_heal", stock = -1 },
            { itemId = "burn_heal", stock = -1 },
            { itemId = "ice_heal", stock = -1 },
            { itemId = "awakening", stock = -1 },
            { itemId = "full_heal", stock = -1 },
            { itemId = "repel", stock = -1 },
            { itemId = "super_repel", stock = -1 },
            { itemId = "max_repel", stock = -1 },
            { itemId = "escape_rope", stock = -1 },
        },
        sellMultiplier = 0.5  -- Player gets 50% of item price when selling
    },
    
    -- Pokemon Center shop - medicine focused
    pokecenter_shop = {
        id = "pokecenter_shop",
        name = "Poké Center Shop",
        greeting = "Need some supplies?",
        farewell = "Take care!",
        inventory = {
            { itemId = "potion", stock = -1 },
            { itemId = "super_potion", stock = -1 },
            { itemId = "hyper_potion", stock = -1 },
            { itemId = "revive", stock = -1 },
            { itemId = "antidote", stock = -1 },
            { itemId = "paralyze_heal", stock = -1 },
            { itemId = "burn_heal", stock = -1 },
            { itemId = "awakening", stock = -1 },
            { itemId = "full_heal", stock = -1 },
        },
        sellMultiplier = 0.5
    },
    
    -- Stone shop - evolution items
    stone_shop = {
        id = "stone_shop",
        name = "Stone Emporium",
        greeting = "Looking for evolution stones?",
        farewell = "May your Pokémon evolve splendidly!",
        inventory = {
            { itemId = "fire_stone", stock = 3 },
            { itemId = "water_stone", stock = 3 },
            { itemId = "thunder_stone", stock = 3 },
            { itemId = "leaf_stone", stock = 3 },
            { itemId = "moon_stone", stock = 3 },
        },
        sellMultiplier = 0.5
    },
    
    -- Battle supplies shop
    battle_shop = {
        id = "battle_shop",
        name = "Battle Supplies",
        greeting = "Ready to power up?",
        farewell = "Good luck in battle!",
        inventory = {
            { itemId = "x_attack", stock = -1 },
            { itemId = "x_defense", stock = -1 },
            { itemId = "x_speed", stock = -1 },
            { itemId = "x_sp_atk", stock = -1 },
            { itemId = "x_sp_def", stock = -1 },
            { itemId = "x_accuracy", stock = -1 },
            { itemId = "dire_hit", stock = -1 },
            { itemId = "guard_spec", stock = -1 },
            { itemId = "pokeball", stock = -1 },
            { itemId = "greatball", stock = -1 },
            { itemId = "ultraball", stock = -1 },
        },
        sellMultiplier = 0.5
    },
    
    -- Vitamin shop - training items
    vitamin_shop = {
        id = "vitamin_shop",
        name = "Vitamin Store",
        greeting = "Looking to boost your Pokémon's potential?",
        farewell = "Train hard!",
        inventory = {
            { itemId = "hp_up", stock = -1 },
            { itemId = "protein", stock = -1 },
            { itemId = "iron", stock = -1 },
            { itemId = "calcium", stock = -1 },
            { itemId = "zinc", stock = -1 },
            { itemId = "carbos", stock = -1 },
            { itemId = "rare_candy", stock = 5 },
            { itemId = "pp_up", stock = 3 },
        },
        sellMultiplier = 0.5
    },
    
    -- PP and Ether shop
    pp_shop = {
        id = "pp_shop",
        name = "Move Specialist",
        greeting = "Need to restore your moves?",
        farewell = "May your moves never run out!",
        inventory = {
            { itemId = "ether", stock = -1 },
            { itemId = "max_ether", stock = -1 },
            { itemId = "elixir", stock = -1 },
            { itemId = "max_elixir", stock = 3 },
            { itemId = "pp_up", stock = 5 },
            { itemId = "pp_max", stock = 1 },
        },
        sellMultiplier = 0.5
    },
    
    -- Held items shop
    held_item_shop = {
        id = "held_item_shop",
        name = "Battle Items Boutique",
        greeting = "Looking for competitive gear?",
        farewell = "Use them wisely!",
        inventory = {
            { itemId = "leftovers", stock = 1 },
            { itemId = "life_orb", stock = 1 },
            { itemId = "choice_band", stock = 1 },
            { itemId = "choice_specs", stock = 1 },
            { itemId = "choice_scarf", stock = 1 },
            { itemId = "focus_sash", stock = 3 },
            { itemId = "black_sludge", stock = 1 },
        },
        sellMultiplier = 0.5
    },
    
    -- Berry shop
    berry_shop = {
        id = "berry_shop",
        name = "Berry Mart",
        greeting = "Fresh berries for your Pokémon!",
        farewell = "Enjoy the berries!",
        inventory = {
            { itemId = "oran_berry", stock = -1 },
            { itemId = "sitrus_berry", stock = -1 },
            { itemId = "lum_berry", stock = -1 },
        },
        sellMultiplier = 0.5
    },
    
    -- Test shop with everything
    test_shop = {
        id = "test_shop",
        name = "Test Shop",
        greeting = "Welcome to the test shop!",
        farewell = "Thanks for testing!",
        inventory = {
            { itemId = "pokeball", stock = -1 },
            { itemId = "greatball", stock = -1 },
            { itemId = "ultraball", stock = -1 },
            { itemId = "potion", stock = -1 },
            { itemId = "super_potion", stock = -1 },
            { itemId = "hyper_potion", stock = -1 },
            { itemId = "max_potion", stock = -1 },
            { itemId = "full_restore", stock = -1 },
            { itemId = "revive", stock = -1 },
            { itemId = "max_revive", stock = -1 },
            { itemId = "antidote", stock = -1 },
            { itemId = "full_heal", stock = -1 },
            { itemId = "ether", stock = -1 },
            { itemId = "max_ether", stock = -1 },
            { itemId = "elixir", stock = -1 },
            { itemId = "max_elixir", stock = -1 },
            { itemId = "x_attack", stock = -1 },
            { itemId = "x_defense", stock = -1 },
            { itemId = "x_speed", stock = -1 },
            { itemId = "repel", stock = -1 },
            { itemId = "escape_rope", stock = -1 },
            { itemId = "rare_candy", stock = -1 },
            { itemId = "pp_up", stock = -1 },
            { itemId = "hp_up", stock = -1 },
            { itemId = "protein", stock = -1 },
            { itemId = "fire_stone", stock = 5 },
            { itemId = "water_stone", stock = 5 },
            { itemId = "thunder_stone", stock = 5 },
            { itemId = "leftovers", stock = 5 },
            { itemId = "choice_band", stock = 5 },
            { itemId = "life_orb", stock = 5 },
            { itemId = "oran_berry", stock = -1 },
            { itemId = "sitrus_berry", stock = -1 },
            { itemId = "lum_berry", stock = -1 },
        },
        sellMultiplier = 0.5
    }
}

--------------------------------------------------
-- Shop (RUNTIME INSTANCE)
--------------------------------------------------

local Shop = {}
Shop.__index = Shop

-- Create a new shop instance from shop ID
function Shop:new(shopId)
    local data = ShopData[shopId]
    if not data then
        log.log("Shop:new - Unknown shop ID: " .. tostring(shopId))
        return nil
    end
    
    local self = setmetatable({}, Shop)
    
    self.id = data.id
    self.name = data.name
    self.greeting = data.greeting
    self.farewell = data.farewell
    self.sellMultiplier = data.sellMultiplier or 0.5
    
    -- Copy inventory with stock tracking
    self.inventory = {}
    local ok, itemModule = pcall(require, "item")
    if ok and itemModule and itemModule.ItemData then
        for _, shopItem in ipairs(data.inventory) do
            local itemData = itemModule.ItemData[shopItem.itemId]
            if itemData then
                table.insert(self.inventory, {
                    itemId = shopItem.itemId,
                    data = itemData,
                    stock = shopItem.stock,  -- -1 = unlimited
                    price = itemData.price or 0
                })
            else
                log.log("Shop:new - Unknown item: " .. tostring(shopItem.itemId))
            end
        end
    end
    
    return self
end

-- Get the sell price for an item
function Shop:getSellPrice(itemData)
    if not itemData or not itemData.price then return 0 end
    return math.floor(itemData.price * self.sellMultiplier)
end

-- Check if an item is in stock
function Shop:isInStock(index)
    local item = self.inventory[index]
    if not item then return false end
    return item.stock == -1 or item.stock > 0
end

-- Purchase an item (decreases stock if limited)
function Shop:purchase(index, quantity)
    local item = self.inventory[index]
    if not item then return false end
    
    quantity = quantity or 1
    
    -- Check stock
    if item.stock ~= -1 then
        if item.stock < quantity then
            return false
        end
        item.stock = item.stock - quantity
    end
    
    return true
end

--------------------------------------------------
-- SHOP MENU STATE
--------------------------------------------------

M.open = false
M.player = nil  -- Set by main.lua
M.currentShop = nil  -- Current Shop instance

-- Menu state
M.state = "main"  -- "main", "buy", "sell", "buy_confirm", "sell_confirm", "message"
M.mainOptions = {"Buy", "Sell", "Exit"}
M.mainSelected = 1

-- Buy menu state
M.buySelected = 1
M.buyQuantity = 1
M.buyScrollOffset = 0
M.maxVisibleItems = 6

-- Sell menu state
M.sellSelected = 1
M.sellQuantity = 1
M.sellScrollOffset = 0
M.sellItems = {}  -- Items player can sell
M.sellCategories = {"medicine", "pokeball", "battle_item", "misc", "berry", "tm"}

-- Message state
M.message = ""
M.messageCallback = nil

-- Key holding state
M.heldKeys = {}  -- Tracks which keys are being held
M.holdDelays = {}  -- Tracks how long each key has been held
M.holdInitialDelay = 0.3  -- Delay before first repeat
M.holdRepeatDelay = 0.1   -- Delay between repeats

--------------------------------------------------
-- SHOP MENU FUNCTIONS
--------------------------------------------------

function M.openShop(shopId, player)
    local shop = Shop:new(shopId)
    if not shop then
        log.log("Failed to open shop: " .. tostring(shopId))
        return false
    end
    
    M.currentShop = shop
    M.player = player
    M.open = true
    M.state = "message"
    M.message = shop.greeting
    M.messageCallback = function()
        M.state = "main"
    end
    M.mainSelected = 1
    M.buySelected = 1
    M.buyQuantity = 1
    M.buyScrollOffset = 0
    M.sellSelected = 1
    M.sellQuantity = 1
    M.sellScrollOffset = 0
    
    return true
end

function M.close()
    if M.currentShop then
        M.message = M.currentShop.farewell
        M.state = "message"
        M.messageCallback = function()
            M.open = false
            M.currentShop = nil
            M.state = "main"
        end
    else
        M.open = false
        M.currentShop = nil
        M.state = "main"
    end
end

function M.isOpen()
    return M.open
end

-- Refresh sellable items from player's bag
local function refreshSellItems()
    M.sellItems = {}
    if not M.player or not M.player.bag then return end
    
    for _, category in ipairs(M.sellCategories) do
        local pocket = M.player.bag[category]
        if pocket then
            for itemId, item in pairs(pocket) do
                if item and item.quantity and item.quantity > 0 then
                    -- Don't allow selling key items
                    if item.data and item.data.category ~= "key_item" then
                        table.insert(M.sellItems, {
                            item = item,
                            sellPrice = M.currentShop:getSellPrice(item.data)
                        })
                    end
                end
            end
        end
    end
    
    -- Sort by name
    table.sort(M.sellItems, function(a, b)
        return (a.item.data.name or "") < (b.item.data.name or "")
    end)
end

--------------------------------------------------
-- UPDATE
--------------------------------------------------

function M.update(dt)
    if not M.open then return end
    
    -- Handle held keys for repeating actions
    local keysToCheck = {"up", "down", "left", "right"}
    for _, keyName in ipairs(keysToCheck) do
        if love.keyboard.isDown(keyName) then
            -- Key is being held down
            if not M.heldKeys[keyName] then
                -- Key just started being held
                M.heldKeys[keyName] = true
                M.holdDelays[keyName] = 0
            else
                -- Key has been held, increment delay
                M.holdDelays[keyName] = (M.holdDelays[keyName] or 0) + dt
                -- Check if enough time has passed for repeating
                if M.holdDelays[keyName] >= M.holdInitialDelay then
                    -- Time for another repeat
                    M.holdDelays[keyName] = M.holdDelays[keyName] - M.holdRepeatDelay
                    -- Trigger the action again
                    M.keypressed(keyName)
                end
            end
        else
            -- Key is not being held
            M.heldKeys[keyName] = nil
            M.holdDelays[keyName] = nil
        end
    end
end

--------------------------------------------------
-- KEY HANDLING
--------------------------------------------------

function M.keypressed(key)
    if not M.open then return end
    
    -- Handle message state
    if M.state == "message" then
        if key == "return" or key == "z" or key == "Z" or key == "space" then
            if M.messageCallback then
                M.messageCallback()
                M.messageCallback = nil
            else
                M.state = "main"
            end
        end
        return
    end
    
    -- Main menu
    if M.state == "main" then
        if key == "up" then
            M.mainSelected = M.mainSelected - 1
            if M.mainSelected < 1 then M.mainSelected = #M.mainOptions end
        elseif key == "down" then
            M.mainSelected = M.mainSelected + 1
            if M.mainSelected > #M.mainOptions then M.mainSelected = 1 end
        elseif key == "return" or key == "z" or key == "Z" then
            local choice = M.mainOptions[M.mainSelected]
            if choice == "Buy" then
                M.state = "buy"
                M.buySelected = 1
                M.buyQuantity = 1
                M.buyScrollOffset = 0
            elseif choice == "Sell" then
                refreshSellItems()
                M.state = "sell"
                M.sellSelected = 1
                M.sellQuantity = 1
                M.sellScrollOffset = 0
            elseif choice == "Exit" then
                M.close()
            end
        elseif key == "space" then
            M.close()
        end
        return
    end
    
    -- Buy menu
    if M.state == "buy" then
        local itemCount = #M.currentShop.inventory
        
        if key == "up" then
            M.buySelected = M.buySelected - 1
            if M.buySelected < 1 then M.buySelected = itemCount + 1 end  -- +1 for Cancel
            -- Adjust scroll
            if M.buySelected <= M.buyScrollOffset then
                M.buyScrollOffset = math.max(0, M.buySelected - 1)
            end
            -- Handle wrap-around to bottom
            if M.buySelected == itemCount + 1 and M.buySelected > M.maxVisibleItems then
                M.buyScrollOffset = M.buySelected - M.maxVisibleItems
            end
            M.buyQuantity = 1
        elseif key == "down" then
            M.buySelected = M.buySelected + 1
            if M.buySelected > itemCount + 1 then M.buySelected = 1 end
            -- Adjust scroll
            if M.buySelected > M.buyScrollOffset + M.maxVisibleItems then
                M.buyScrollOffset = M.buySelected - M.maxVisibleItems
            end
            -- Handle wrap-around to top
            if M.buySelected == 1 then
                M.buyScrollOffset = 0
            end
            M.buyQuantity = 1
        elseif key == "left" then
            if M.buySelected <= itemCount then
                M.buyQuantity = math.max(1, M.buyQuantity - 1)
            end
        elseif key == "right" then
            if M.buySelected <= itemCount then
                local item = M.currentShop.inventory[M.buySelected]
                local maxAfford = math.floor((M.player.money or 0) / item.price)
                local maxStock = item.stock == -1 and 99 or item.stock
                M.buyQuantity = math.min(99, math.min(maxAfford, maxStock), M.buyQuantity + 1)
            end
        elseif key == "return" or key == "z" or key == "Z" then
            if M.buySelected == itemCount + 1 then
                -- Cancel
                M.state = "main"
            else
                -- Try to buy
                local item = M.currentShop.inventory[M.buySelected]
                local totalCost = item.price * M.buyQuantity
                
                if not M.currentShop:isInStock(M.buySelected) then
                    M.message = "Sorry, we're sold out of that."
                    M.state = "message"
                    M.messageCallback = function() M.state = "buy" end
                elseif (M.player.money or 0) < totalCost then
                    M.message = "You don't have enough money."
                    M.state = "message"
                    M.messageCallback = function() M.state = "buy" end
                else
                    -- Confirm purchase
                    M.state = "buy_confirm"
                end
            end
        elseif key == "space" then
            M.state = "main"
        end
        return
    end
    
    -- Buy confirmation
    if M.state == "buy_confirm" then
        if key == "return" or key == "z" or key == "Z" then
            -- Complete purchase
            local item = M.currentShop.inventory[M.buySelected]
            local totalCost = item.price * M.buyQuantity
            
            M.player.money = (M.player.money or 0) - totalCost
            M.currentShop:purchase(M.buySelected, M.buyQuantity)
            
            -- Add to player's bag
            if M.player.bag then
                M.player.bag:add(item.itemId, M.buyQuantity)
            end
            
            M.message = "Here you go!\nThank you!"
            M.state = "message"
            M.messageCallback = function()
                M.state = "buy"
                M.buyQuantity = 1
            end
        elseif key == "space" then
            M.state = "buy"
        end
        return
    end
    
    -- Sell menu
    if M.state == "sell" then
        local itemCount = #M.sellItems
        
        if key == "up" then
            M.sellSelected = M.sellSelected - 1
            if M.sellSelected < 1 then M.sellSelected = itemCount + 1 end  -- +1 for Cancel
            -- Adjust scroll
            if M.sellSelected <= M.sellScrollOffset then
                M.sellScrollOffset = math.max(0, M.sellSelected - 1)
            end
            -- Handle wrap-around to bottom
            if M.sellSelected == itemCount + 1 and M.sellSelected > M.maxVisibleItems then
                M.sellScrollOffset = M.sellSelected - M.maxVisibleItems
            end
            M.sellQuantity = 1
        elseif key == "down" then
            M.sellSelected = M.sellSelected + 1
            if M.sellSelected > itemCount + 1 then M.sellSelected = 1 end
            -- Adjust scroll
            if M.sellSelected > M.sellScrollOffset + M.maxVisibleItems then
                M.sellScrollOffset = M.sellSelected - M.maxVisibleItems
            end
            -- Handle wrap-around to top
            if M.sellSelected == 1 then
                M.sellScrollOffset = 0
            end
            M.sellQuantity = 1
        elseif key == "left" then
            if M.sellSelected <= itemCount then
                M.sellQuantity = math.max(1, M.sellQuantity - 1)
            end
        elseif key == "right" then
            if M.sellSelected <= itemCount then
                local sellItem = M.sellItems[M.sellSelected]
                M.sellQuantity = math.min(sellItem.item.quantity, M.sellQuantity + 1)
            end
        elseif key == "return" or key == "z" or key == "Z" then
            if M.sellSelected == itemCount + 1 then
                -- Cancel
                M.state = "main"
            elseif itemCount > 0 then
                local sellItem = M.sellItems[M.sellSelected]
                if sellItem.sellPrice <= 0 then
                    M.message = "I can't buy that from you."
                    M.state = "message"
                    M.messageCallback = function() M.state = "sell" end
                else
                    -- Confirm sale
                    M.state = "sell_confirm"
                end
            end
        elseif key == "space" then
            M.state = "main"
        end
        return
    end
    
    -- Sell confirmation
    if M.state == "sell_confirm" then
        if key == "return" or key == "z" or key == "Z" then
            -- Complete sale
            local sellItem = M.sellItems[M.sellSelected]
            local totalValue = sellItem.sellPrice * M.sellQuantity
            
            M.player.money = (M.player.money or 0) + totalValue
            
            -- Remove from player's bag
            if M.player.bag then
                M.player.bag:remove(sellItem.item.id, M.sellQuantity)
            end
            
            M.message = "Sold for $" .. totalValue .. "!\nThank you!"
            M.state = "message"
            M.messageCallback = function()
                refreshSellItems()
                M.sellSelected = math.min(M.sellSelected, #M.sellItems + 1)
                if M.sellSelected < 1 then M.sellSelected = 1 end
                M.sellQuantity = 1
                M.state = "sell"
            end
        elseif key == "space" then
            M.state = "sell"
        end
        return
    end
end

--------------------------------------------------
-- DRAWING
--------------------------------------------------

function M.draw()
    if not M.open then return end
    
    local ww, wh = UI.getGameScreenDimensions()
    
    -- Draw semi-transparent overlay
    UI.drawOverlay(0.3)
    
    -- Draw shop name at top
    local titleH = 40
    UI.drawBox(10, 10, ww - 20, titleH)
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.printf(M.currentShop.name, 20, 22, ww - 40, "center")
    
    -- Handle different states
    if M.state == "message" then
        M.drawMessage()
    elseif M.state == "main" then
        M.drawMainMenu()
    elseif M.state == "buy" then
        M.drawBuyMenu()
    elseif M.state == "buy_confirm" then
        M.drawBuyMenu()
        M.drawBuyConfirm()
    elseif M.state == "sell" then
        M.drawSellMenu()
    elseif M.state == "sell_confirm" then
        M.drawSellMenu()
        M.drawSellConfirm()
    end
    
    -- Draw player money (draw last so it's always on top)
    local moneyBoxW = 120
    local moneyBoxH = 30
    UI.drawBox(ww - moneyBoxW - 10, titleH + 20, moneyBoxW, moneyBoxH)
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.printf("$" .. tostring(M.player.money or 0), ww - moneyBoxW - 5, titleH + 28, moneyBoxW - 10, "right")
    
    love.graphics.setColor(1, 1, 1, 1)
end

function M.drawMessage()
    local ww, wh = UI.getGameScreenDimensions()
    local boxW = ww - 40
    local boxH = 80
    local boxX = 20
    local boxY = wh - boxH - 20
    
    UI.drawBoxWithShadow(boxX, boxY, boxW, boxH)
    
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.printf(M.message, boxX + 15, boxY + 20, boxW - 30, "left")
    
    -- Draw continue prompt
    love.graphics.setColor(unpack(UI.colors.textGray))
    love.graphics.printf("Press A to continue", boxX + 15, boxY + boxH - 25, boxW - 30, "right")
end

function M.drawMainMenu()
    local ww, wh = UI.getGameScreenDimensions()
    local boxW = 120
    local boxH = 100
    local boxX = ww / 2 - boxW / 2
    local boxY = 100
    
    UI.drawBoxWithShadow(boxX, boxY, boxW, boxH)
    
    local startY = boxY + 15
    local lineH = 25
    
    for i, option in ipairs(M.mainOptions) do
        UI.drawOption(option, boxX + 25, startY + (i - 1) * lineH, i == M.mainSelected)
    end
end

function M.drawBuyMenu()
    local ww, wh = UI.getGameScreenDimensions()
    local boxX = 20
    local boxY = 60
    local boxW = ww - 40
    local boxH = wh - 100
    
    UI.drawBoxWithShadow(boxX, boxY, boxW, boxH)
    
    -- Title
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.printf("What would you like?", boxX + 10, boxY + 10, boxW - 20, "center")
    
    local startY = boxY + 35
    local lineH = 28
    local itemCount = #M.currentShop.inventory
    
    -- Draw visible items
    for i = 1, math.min(M.maxVisibleItems, itemCount + 1) do
        local index = i + M.buyScrollOffset
        local y = startY + (i - 1) * lineH
        
        if index <= itemCount then
            local item = M.currentShop.inventory[index]
            local selected = index == M.buySelected
            
            -- Item name
            UI.drawOption(item.data.name, boxX + 25, y, selected)
            
            -- Owned quantity
            local ownedQty = 0
            if M.player and M.player.bag then
                local category = item.data.category
                local pocket = M.player.bag[category]
                if pocket and pocket[item.itemId] then
                    ownedQty = pocket[item.itemId].quantity or 0
                end
            end
            love.graphics.setColor(unpack(UI.colors.textGray))
            love.graphics.print("Own: " .. ownedQty, boxX + 170, y)
            
            -- Stock indicator
            love.graphics.setColor(unpack(UI.colors.textGray))
            if item.stock == -1 then
                -- Unlimited stock - don't show anything
            elseif item.stock == 0 then
                love.graphics.setColor(unpack(UI.colors.hpRed))
                love.graphics.print("SOLD OUT", boxX + 240, y)
            else
                love.graphics.print("x" .. item.stock, boxX + 240, y)
            end
            
            -- Price
            love.graphics.setColor(unpack(UI.colors.textDark))
            love.graphics.printf("$" .. item.price, boxX, y, boxW - 25, "right")
            
            -- Quantity selector (if selected)
            if selected and item.stock ~= 0 then
                love.graphics.setColor(unpack(UI.colors.textHighlight))
                love.graphics.print("Qty: " .. M.buyQuantity, boxX + 310, y)
            end
        elseif index == itemCount + 1 then
            -- Cancel option
            UI.drawOption("Cancel", boxX + 25, y, index == M.buySelected)
        end
    end
    
    -- Draw scroll indicators
    if M.buyScrollOffset > 0 then
        love.graphics.setColor(unpack(UI.colors.textGray))
        love.graphics.print("^", boxX + boxW / 2, startY - 15)
    end
    if M.buyScrollOffset + M.maxVisibleItems < itemCount + 1 then
        love.graphics.setColor(unpack(UI.colors.textGray))
        love.graphics.print("v", boxX + boxW / 2, startY + M.maxVisibleItems * lineH)
    end
    
    -- Draw selected item description
    if M.buySelected <= itemCount then
        local item = M.currentShop.inventory[M.buySelected]
        local descBoxY = boxY + boxH - 50
        love.graphics.setColor(unpack(UI.colors.borderLight))
        love.graphics.line(boxX + 10, descBoxY - 5, boxX + boxW - 10, descBoxY - 5)
        love.graphics.setColor(unpack(UI.colors.textGray))
        love.graphics.printf(item.data.description or "", boxX + 15, descBoxY, boxW - 30, "left")
    end
    
    -- Draw total cost
    if M.buySelected <= itemCount then
        local item = M.currentShop.inventory[M.buySelected]
        local totalCost = item.price * M.buyQuantity
        love.graphics.setColor(unpack(UI.colors.textDark))
        love.graphics.printf("Total: $" .. totalCost, boxX + 15, boxY + boxH - 25, boxW - 30, "left")
    end
end

function M.drawBuyConfirm()
    local ww, wh = UI.getGameScreenDimensions()
    local item = M.currentShop.inventory[M.buySelected]
    local totalCost = item.price * M.buyQuantity
    
    local boxW = 250
    local boxH = 80
    local boxX = ww / 2 - boxW / 2
    local boxY = wh / 2 - boxH / 2
    
    UI.drawBoxWithShadow(boxX, boxY, boxW, boxH)
    
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.printf(item.data.name .. " x" .. M.buyQuantity .. "\nfor $" .. totalCost .. "?", 
        boxX + 15, boxY + 15, boxW - 30, "center")
    
    love.graphics.setColor(unpack(UI.colors.textGray))
    love.graphics.printf("A: Confirm  B: Cancel", boxX + 15, boxY + boxH - 25, boxW - 30, "center")
end

function M.drawSellMenu()
    local ww, wh = UI.getGameScreenDimensions()
    local boxX = 20
    local boxY = 60
    local boxW = ww - 40
    local boxH = wh - 100
    
    UI.drawBoxWithShadow(boxX, boxY, boxW, boxH)
    
    -- Title
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.printf("What would you like to sell?", boxX + 10, boxY + 10, boxW - 20, "center")
    
    local startY = boxY + 35
    local lineH = 28
    local itemCount = #M.sellItems
    
    if itemCount == 0 then
        love.graphics.setColor(unpack(UI.colors.textGray))
        love.graphics.printf("You don't have anything to sell.", boxX + 15, startY + 20, boxW - 30, "center")
        
        -- Just show Cancel
        UI.drawOption("Cancel", boxX + 25, startY + 60, true)
        return
    end
    
    -- Draw visible items
    for i = 1, math.min(M.maxVisibleItems, itemCount + 1) do
        local index = i + M.sellScrollOffset
        local y = startY + (i - 1) * lineH
        
        if index <= itemCount then
            local sellItem = M.sellItems[index]
            local selected = index == M.sellSelected
            
            -- Item name
            UI.drawOption(sellItem.item.data.name, boxX + 25, y, selected)
            
            -- Quantity owned
            love.graphics.setColor(unpack(UI.colors.textGray))
            love.graphics.print("x" .. sellItem.item.quantity, boxX + 180, y)
            
            -- Sell price
            love.graphics.setColor(unpack(UI.colors.textDark))
            love.graphics.printf("$" .. sellItem.sellPrice, boxX, y, boxW - 25, "right")
            
            -- Quantity selector (if selected)
            if selected then
                love.graphics.setColor(unpack(UI.colors.textHighlight))
                love.graphics.print("Sell: " .. M.sellQuantity, boxX + 220, y)
            end
        elseif index == itemCount + 1 then
            -- Cancel option
            UI.drawOption("Cancel", boxX + 25, y, index == M.sellSelected)
        end
    end
    
    -- Draw scroll indicators
    if M.sellScrollOffset > 0 then
        love.graphics.setColor(unpack(UI.colors.textGray))
        love.graphics.print("^", boxX + boxW / 2, startY - 15)
    end
    if M.sellScrollOffset + M.maxVisibleItems < itemCount + 1 then
        love.graphics.setColor(unpack(UI.colors.textGray))
        love.graphics.print("v", boxX + boxW / 2, startY + M.maxVisibleItems * lineH)
    end
    
    -- Draw total value
    if M.sellSelected <= itemCount then
        local sellItem = M.sellItems[M.sellSelected]
        local totalValue = sellItem.sellPrice * M.sellQuantity
        love.graphics.setColor(unpack(UI.colors.textDark))
        love.graphics.printf("Total: $" .. totalValue, boxX + 15, boxY + boxH - 25, boxW - 30, "left")
    end
end

function M.drawSellConfirm()
    local ww, wh = UI.getGameScreenDimensions()
    local sellItem = M.sellItems[M.sellSelected]
    local totalValue = sellItem.sellPrice * M.sellQuantity
    
    local boxW = 250
    local boxH = 80
    local boxX = ww / 2 - boxW / 2
    local boxY = wh / 2 - boxH / 2
    
    UI.drawBoxWithShadow(boxX, boxY, boxW, boxH)
    
    love.graphics.setColor(unpack(UI.colors.textDark))
    love.graphics.printf("Sell " .. sellItem.item.data.name .. " x" .. M.sellQuantity .. "\nfor $" .. totalValue .. "?", 
        boxX + 15, boxY + 15, boxW - 30, "center")
    
    love.graphics.setColor(unpack(UI.colors.textGray))
    love.graphics.printf("A: Confirm  B: Cancel", boxX + 15, boxY + boxH - 25, boxW - 30, "center")
end

--------------------------------------------------
-- Module Export
--------------------------------------------------

M.ShopData = ShopData
M.Shop = Shop

return M
