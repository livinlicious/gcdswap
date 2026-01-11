--[[
    GCDSwap: Event-Driven Equipment Swap for Turtle WoW

    Concept:
    1. ARM: User types /gcdswap <preset> to arm the trap (Queue = true)
    2. LISTEN: Addon listens for SPELLCAST_STOP event
    3. SWAP: On instant spell cast, swap equipment during GCD
    4. DISARM: Queue = false, stop listening

    Supports:
    - Weapons (MainHand, OffHand)
    - Shields (OffHand)
    - Relics (Ranged slot): Totems, Idols, Librams

    Why this works:
    - SPELLCAST_STOP fires when GCD starts (safe window)
    - No race conditions like "Cast + Equip in one button" methods
    - Server already confirmed GCD before we swap
--]]

------------------------------------------------------
-- SAVED VARIABLES
------------------------------------------------------

GCDSwapDB = GCDSwapDB or {
    bag = 0,
    slot = 1,
    debug = false,
    sound = true,
    presets = {}
}

------------------------------------------------------
-- STATE
------------------------------------------------------

local armed = false
local swapInProgress = false
local currentPreset = nil

------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------

local MAINHAND_SLOT = 16
local OFFHAND_SLOT = 17
local RANGED_SLOT = 18  -- Also used for relics (totems, idols, librams)

------------------------------------------------------
-- DEBUG UTILITIES
------------------------------------------------------

local function DebugMsg(msg)
    if GCDSwapDB.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaff[GCDSwap]|r " .. msg)
    end
end

local function PrintMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ccff[GCDSwap]|r " .. msg)
end

local function ErrorMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8888[GCDSwap]|r " .. msg)
end

------------------------------------------------------
-- UTILITY FUNCTIONS
------------------------------------------------------

-- Get item link from bag slot
local function GetBagItemLink(bag, slot)
    return GetContainerItemLink(bag, slot)
end

-- Get equipped item link from any slot
local function GetEquippedItemLink(slot)
    return GetInventoryItemLink("player", slot)
end

-- Get equipped mainhand item link (backwards compatibility)
local function GetMainHandLink()
    return GetEquippedItemLink(MAINHAND_SLOT)
end

-- Extract item name from item link
local function GetItemNameFromLink(link)
    if not link then return nil end
    local _, _, name = string.find(link, "%[(.+)%]")
    return name and string.lower(name) or nil
end

-- Find item in bags by name (case insensitive)
local function FindItemInBags(itemName)
    if not itemName then return nil, nil end
    itemName = string.lower(itemName)

    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetBagItemLink(bag, slot)
            if link then
                local bagItemName = GetItemNameFromLink(link)
                if bagItemName and bagItemName == itemName then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

-- Check if item is equipped in a specific slot
local function IsEquippedInSlot(itemName, slot)
    if not itemName then return false end
    local equippedLink = GetEquippedItemLink(slot)
    local equippedName = GetItemNameFromLink(equippedLink)
    return equippedName and string.lower(equippedName) == string.lower(itemName)
end

-- Check if item is equipped in mainhand (backwards compatibility)
local function IsEquippedInMainHand(itemName)
    return IsEquippedInSlot(itemName, MAINHAND_SLOT)
end

-- Find which slot an item is equipped in (returns slot number or nil)
local function FindEquippedSlot(itemName)
    if not itemName then return nil end
    itemName = string.lower(itemName)

    -- Check all three swappable slots
    for _, slot in ipairs({MAINHAND_SLOT, OFFHAND_SLOT, RANGED_SLOT}) do
        if IsEquippedInSlot(itemName, slot) then
            return slot
        end
    end

    return nil
end

------------------------------------------------------
-- PRESET MANAGEMENT
------------------------------------------------------

local function SavePreset(name, item1, item2)
    if not name or name == "" then
        ErrorMsg("Preset name cannot be empty")
        return false
    end

    if not item1 or not item2 then
        ErrorMsg("Both item names required")
        return false
    end

    item1 = string.lower(item1)
    item2 = string.lower(item2)

    GCDSwapDB.presets[string.lower(name)] = {
        weapon1 = item1,  -- Keep old field names for compatibility
        weapon2 = item2
    }

    PrintMsg("Preset '" .. name .. "' saved:")
    PrintMsg("  Item1 (normal): " .. item1)
    PrintMsg("  Item2 (GCD swap): " .. item2)
    DebugMsg("Saved as: [" .. item1 .. "] <-> [" .. item2 .. "]")
    return true
end

local function DeletePreset(name)
    if not name or name == "" then
        ErrorMsg("Preset name required")
        return false
    end

    name = string.lower(name)
    if not GCDSwapDB.presets[name] then
        ErrorMsg("Preset '" .. name .. "' not found")
        return false
    end

    GCDSwapDB.presets[name] = nil
    PrintMsg("Preset '" .. name .. "' deleted")
    return true
end

local function ListPresets()
    PrintMsg("Saved Presets:")

    local count = 0
    for name, preset in pairs(GCDSwapDB.presets) do
        count = count + 1
        PrintMsg("  " .. name .. ": " .. preset.weapon1 .. " <-> " .. preset.weapon2)
    end

    if count == 0 then
        PrintMsg("  (no presets saved)")
    end
end

local function LoadPreset(name)
    if not name or name == "" then
        ErrorMsg("Preset name required")
        return false
    end

    name = string.lower(name)
    local preset = GCDSwapDB.presets[name]

    if not preset then
        ErrorMsg("Preset '" .. name .. "' not found")
        return false
    end

    currentPreset = preset
    DebugMsg("Loaded preset '" .. name .. "': " .. preset.weapon1 .. " <-> " .. preset.weapon2)
    return true
end

------------------------------------------------------
-- CORE SWAP LOGIC
------------------------------------------------------

-- Perform the swap using bag/slot method
local function SwapWeaponBySlot(bag, slot, equipSlot)
    if swapInProgress then
        DebugMsg("Swap already in progress, ignoring")
        return false
    end

    -- Default to mainhand if not specified
    equipSlot = equipSlot or MAINHAND_SLOT

    -- Validate bag/slot exists and has item
    local bagItemLink = GetBagItemLink(bag, slot)
    if not bagItemLink then
        ErrorMsg("No item in Bag " .. bag .. ", Slot " .. slot)
        return false
    end

    -- Get equipped item info
    local equippedLink = GetEquippedItemLink(equipSlot)
    if not equippedLink then
        DebugMsg("No item equipped in slot " .. equipSlot)
    end

    swapInProgress = true

    local slotName = equipSlot == MAINHAND_SLOT and "MainHand" or
                     equipSlot == OFFHAND_SLOT and "OffHand" or
                     equipSlot == RANGED_SLOT and "Ranged/Relic" or "Slot" .. equipSlot
    DebugMsg("Swapping " .. slotName .. " <-> Bag(" .. bag .. "," .. slot .. ")")

    -- Pick up item from bag
    PickupContainerItem(bag, slot)

    -- Equip to slot (this puts current equipped item into cursor if exists)
    PickupInventoryItem(equipSlot)

    -- Place cursor item (old equipped item) back to bag slot
    PickupContainerItem(bag, slot)

    swapInProgress = false

    DebugMsg("Item swapped!")

    if GCDSwapDB.sound then
        PlaySound("igMainMenuOptionCheckBoxOn")
    end

    return true
end

-- Perform the swap using preset (item names)
local function SwapWeaponByPreset()
    if swapInProgress then
        DebugMsg("Swap already in progress, ignoring")
        return false
    end

    if not currentPreset then
        ErrorMsg("No preset loaded")
        return false
    end

    local item1 = currentPreset.weapon1  -- Keep old field names for compatibility
    local item2 = currentPreset.weapon2

    -- Find which slot item1 or item2 is equipped in
    local equippedSlot = FindEquippedSlot(item1)
    if not equippedSlot then
        equippedSlot = FindEquippedSlot(item2)
    end

    if not equippedSlot then
        ErrorMsg("Neither preset item is equipped in any slot!")
        DebugMsg("Looking for: [" .. item1 .. "] or [" .. item2 .. "]")
        return false
    end

    local equippedLink = GetEquippedItemLink(equippedSlot)
    local equippedName = GetItemNameFromLink(equippedLink)

    local slotName = equippedSlot == MAINHAND_SLOT and "MainHand" or
                     equippedSlot == OFFHAND_SLOT and "OffHand" or
                     equippedSlot == RANGED_SLOT and "Ranged/Relic" or "Slot" .. equippedSlot
    DebugMsg("Found equipped in " .. slotName .. ": [" .. (equippedName or "nothing") .. "]")
    DebugMsg("Looking for item1: [" .. item1 .. "]")
    DebugMsg("Looking for item2: [" .. item2 .. "]")

    local item1Equipped = IsEquippedInSlot(item1, equippedSlot)
    local item2Equipped = IsEquippedInSlot(item2, equippedSlot)

    DebugMsg("Item1 match: " .. tostring(item1Equipped))
    DebugMsg("Item2 match: " .. tostring(item2Equipped))

    local targetItem = nil
    if item1Equipped then
        -- Item1 is equipped, swap to Item2
        targetItem = item2
    elseif item2Equipped then
        -- Item2 is equipped, swap back to Item1
        targetItem = item1
    else
        ErrorMsg("Neither preset item is equipped!")
        return false
    end

    -- Find target item in bags
    local bag, slot = FindItemInBags(targetItem)
    if not bag then
        ErrorMsg("Cannot find '" .. targetItem .. "' in bags!")
        return false
    end

    swapInProgress = true

    DebugMsg("Swapping to: " .. targetItem .. " from Bag(" .. bag .. "," .. slot .. ")")

    -- Pick up item from bag
    PickupContainerItem(bag, slot)

    -- Equip to the same slot (this puts current equipped item into cursor)
    PickupInventoryItem(equippedSlot)

    -- Place cursor item (old equipped item) back to bag slot
    PickupContainerItem(bag, slot)

    swapInProgress = false

    DebugMsg("Swapped to: " .. targetItem)

    if GCDSwapDB.sound then
        PlaySound("igMainMenuOptionCheckBoxOn")
    end

    return true
end

-- Main swap dispatcher
local function SwapWeapon()
    if currentPreset then
        return SwapWeaponByPreset()
    else
        return SwapWeaponBySlot(GCDSwapDB.bag, GCDSwapDB.slot)
    end
end

------------------------------------------------------
-- ARM/DISARM LOGIC
------------------------------------------------------

local function ArmSwap(presetName)
    -- If preset name provided, load it
    if presetName and presetName ~= "" then
        if not LoadPreset(presetName) then
            return
        end
        DebugMsg("ARMED with preset '" .. presetName .. "'")
    else
        -- Clear preset to use manual bag/slot mode
        currentPreset = nil
        DebugMsg("ARMED - Cast any instant spell to trigger swap")
    end

    armed = true

    if GCDSwapDB.sound then
        PlaySound("igMainMenuOpen")
    end

    DebugMsg("Queue = true, listening for SPELLCAST_STOP")
end

local function DisarmSwap(reason)
    if not armed then return end

    armed = false
    DebugMsg("Queue = false (" .. (reason or "manual") .. ")")
end

------------------------------------------------------
-- EVENT HANDLERS
------------------------------------------------------

-- Handle spell cast events
local function OnSpellCastStop()
    if not armed then return end

    DebugMsg("SPELLCAST_STOP detected while armed!")

    -- Swap weapon
    local success = SwapWeapon()

    if success then
        -- Disarm after successful swap
        DisarmSwap("swap completed")
    else
        -- Keep armed if swap failed (user can fix and try again)
        ErrorMsg("Swap failed - still armed, fix issue and try again")
    end
end

------------------------------------------------------
-- SLASH COMMANDS
------------------------------------------------------

-- Parse command arguments, handling [Item Name] format
local function ParseArgs(msg)
    local args = {}
    local current = ""
    local inBrackets = false

    for i = 1, string.len(msg) do
        local char = string.sub(msg, i, i)

        if char == "[" then
            inBrackets = true
            current = current .. char
        elseif char == "]" then
            inBrackets = false
            current = current .. char
        elseif char == " " and not inBrackets then
            if current ~= "" then
                table.insert(args, current)
                current = ""
            end
        else
            current = current .. char
        end
    end

    if current ~= "" then
        table.insert(args, current)
    end

    return args
end

-- Extract item name from WoW item link or [Item Name] format
local function CleanItemName(input)
    if not input then return nil end

    local itemName = nil

    -- Handle full WoW item link: |cff9d9d9d|Hitem:2140:0:0:0|h[Aurastone Hammer]|h|r
    local _, _, name = string.find(input, "|h%[(.-)%]|h")
    if name then
        itemName = name
    end

    -- If not a full link, try simple bracket format: [Aurastone Hammer]
    if not itemName then
        local _, _, name2 = string.find(input, "%[(.-)%]")
        if name2 then
            itemName = name2
        end
    end

    -- If still nothing, use as-is
    if not itemName then
        itemName = input
    end

    return string.lower(itemName)
end

SLASH_GCDSWAP1 = "/gcdswap"
SlashCmdList["GCDSWAP"] = function(msg)
    if not msg or msg == "" then
        ErrorMsg("Usage: /gcdswap <preset> or /gcdswap help")
        return
    end

    local args = ParseArgs(msg)
    local cmd = string.lower(args[1] or "")

    if cmd == "save" then
        -- /gcdswap save <name> [Item1] [Item2]
        local name = args[2]
        local item1 = CleanItemName(args[3])
        local item2 = CleanItemName(args[4])

        if not name or not item1 or not item2 then
            ErrorMsg("Usage: /gcdswap save <name> [Item1] [Item2]")
            ErrorMsg("Example: /gcdswap save weps [Aurastone Hammer] [Mace of Unending Life]")
            ErrorMsg("Example: /gcdswap save totems [Totem of Sustaining] [Totem of Rage]")
            return
        end

        SavePreset(name, item1, item2)

    elseif cmd == "delete" then
        local name = args[2]
        if not name then
            ErrorMsg("Usage: /gcdswap delete <name>")
            return
        end
        DeletePreset(name)

    elseif cmd == "list" then
        ListPresets()

    elseif cmd == "debug" then
        GCDSwapDB.debug = not GCDSwapDB.debug
        PrintMsg("Debug mode: " .. (GCDSwapDB.debug and "ON" or "OFF"))

    elseif cmd == "sound" then
        GCDSwapDB.sound = not GCDSwapDB.sound
        PrintMsg("Sound: " .. (GCDSwapDB.sound and "ON" or "OFF"))

    elseif cmd == "status" then
        PrintMsg("Status:")
        PrintMsg("  Armed: " .. (armed and "YES" or "NO"))

        if currentPreset then
            PrintMsg("  Preset Active:")
            PrintMsg("    Weapon1: " .. currentPreset.weapon1)
            PrintMsg("    Weapon2: " .. currentPreset.weapon2)
        else
            PrintMsg("  No preset active")
        end

        local mainHandLink = GetMainHandLink()
        if mainHandLink then
            local mainHandName = GetItemNameFromLink(mainHandLink)
            PrintMsg("  MainHand: " .. (mainHandName or "unknown"))
        else
            PrintMsg("  MainHand: (empty)")
        end

        PrintMsg("  Debug: " .. (GCDSwapDB.debug and "ON" or "OFF"))
        PrintMsg("  Sound: " .. (GCDSwapDB.sound and "ON" or "OFF"))

    elseif cmd == "help" then
        PrintMsg("GCDSwap Commands:")
        PrintMsg("  /gcdswap <preset> - Arm swap with preset")
        PrintMsg("  /gcdswap save <name> [Item1] [Item2]")
        PrintMsg("  /gcdswap delete <name>")
        PrintMsg("  /gcdswap list")
        PrintMsg("  /gcdswap status")
        PrintMsg("  /gcdswap debug - Toggle debug")
        PrintMsg("  /gcdswap sound - Toggle sound")
        PrintMsg("")
        PrintMsg("Works with: Weapons, Shields, Totems, Idols, Librams")

    else
        -- Treat as preset name
        ArmSwap(cmd)
    end
end

------------------------------------------------------
-- EVENT FRAME
------------------------------------------------------

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("SPELLCAST_STOP")

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "gcdswap" then
        -- Initialize presets table if it doesn't exist
        if not GCDSwapDB.presets then
            GCDSwapDB.presets = {}
        end

        PrintMsg("Loaded! Type /gcdswap help for commands")
        DebugMsg("Default swap target: Bag " .. GCDSwapDB.bag .. ", Slot " .. GCDSwapDB.slot)

        -- Show preset count
        local presetCount = 0
        for _ in pairs(GCDSwapDB.presets) do
            presetCount = presetCount + 1
        end
        if presetCount > 0 then
            DebugMsg("Loaded " .. presetCount .. " preset(s)")
        end

    elseif event == "SPELLCAST_STOP" then
        OnSpellCastStop()
    end
end)
