--[[
    GCDSwap: Event-Driven Weapon Swap for Turtle WoW

    Concept:
    1. ARM: User types /gcdswap to arm the trap (Queue = true)
    2. LISTEN: Addon listens for SPELLCAST_STOP event
    3. SWAP: On instant spell cast, swap MainHand <-> Bag(0,1) during GCD
    4. DISARM: Queue = false, stop listening

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

-- Get equipped mainhand item link
local function GetMainHandLink()
    return GetInventoryItemLink("player", MAINHAND_SLOT)
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

-- Check if item is equipped in mainhand
local function IsEquippedInMainHand(itemName)
    if not itemName then return false end
    local mainHandLink = GetMainHandLink()
    local equippedName = GetItemNameFromLink(mainHandLink)
    return equippedName and string.lower(equippedName) == string.lower(itemName)
end

------------------------------------------------------
-- PRESET MANAGEMENT
------------------------------------------------------

local function SavePreset(name, weapon1, weapon2)
    if not name or name == "" then
        ErrorMsg("Preset name cannot be empty")
        return false
    end

    if not weapon1 or not weapon2 then
        ErrorMsg("Both weapon names required")
        return false
    end

    weapon1 = string.lower(weapon1)
    weapon2 = string.lower(weapon2)

    GCDSwapDB.presets[string.lower(name)] = {
        weapon1 = weapon1,
        weapon2 = weapon2
    }

    PrintMsg("Preset '" .. name .. "' saved:")
    PrintMsg("  Weapon1 (normal): " .. weapon1)
    PrintMsg("  Weapon2 (GCD swap): " .. weapon2)
    DebugMsg("Saved as: [" .. weapon1 .. "] <-> [" .. weapon2 .. "]")
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
local function SwapWeaponBySlot(bag, slot)
    if swapInProgress then
        DebugMsg("Swap already in progress, ignoring")
        return false
    end

    -- Validate bag/slot exists and has item
    local bagItemLink = GetBagItemLink(bag, slot)
    if not bagItemLink then
        ErrorMsg("No item in Bag " .. bag .. ", Slot " .. slot)
        return false
    end

    -- Get mainhand info
    local mainHandLink = GetMainHandLink()
    if not mainHandLink then
        DebugMsg("No weapon equipped in mainhand")
    end

    swapInProgress = true

    DebugMsg("Swapping MainHand <-> Bag(" .. bag .. "," .. slot .. ")")

    -- Pick up item from bag
    PickupContainerItem(bag, slot)

    -- Equip to mainhand (this puts current mainhand into cursor if exists)
    PickupInventoryItem(MAINHAND_SLOT)

    -- Place cursor item (old mainhand) back to bag slot
    PickupContainerItem(bag, slot)

    swapInProgress = false

    DebugMsg("Weapon swapped!")

    if GCDSwapDB.sound then
        PlaySound("igMainMenuOptionCheckBoxOn")
    end

    return true
end

-- Perform the swap using preset (weapon names)
local function SwapWeaponByPreset()
    if swapInProgress then
        DebugMsg("Swap already in progress, ignoring")
        return false
    end

    if not currentPreset then
        ErrorMsg("No preset loaded")
        return false
    end

    local weapon1 = currentPreset.weapon1
    local weapon2 = currentPreset.weapon2

    -- Check which weapon is currently equipped
    local mainHandLink = GetMainHandLink()
    local equippedName = GetItemNameFromLink(mainHandLink)

    DebugMsg("Currently equipped: [" .. (equippedName or "nothing") .. "]")
    DebugMsg("Looking for weapon1: [" .. weapon1 .. "]")
    DebugMsg("Looking for weapon2: [" .. weapon2 .. "]")

    local weapon1Equipped = IsEquippedInMainHand(weapon1)
    local weapon2Equipped = IsEquippedInMainHand(weapon2)

    DebugMsg("Weapon1 match: " .. tostring(weapon1Equipped))
    DebugMsg("Weapon2 match: " .. tostring(weapon2Equipped))

    local targetWeapon = nil
    if weapon1Equipped then
        -- Weapon1 is equipped, swap to Weapon2
        targetWeapon = weapon2
    elseif weapon2Equipped then
        -- Weapon2 is equipped, swap back to Weapon1
        targetWeapon = weapon1
    else
        ErrorMsg("Neither preset weapon is equipped!")
        return false
    end

    -- Find target weapon in bags
    local bag, slot = FindItemInBags(targetWeapon)
    if not bag then
        ErrorMsg("Cannot find '" .. targetWeapon .. "' in bags!")
        return false
    end

    swapInProgress = true

    DebugMsg("Swapping to: " .. targetWeapon .. " from Bag(" .. bag .. "," .. slot .. ")")

    -- Pick up item from bag
    PickupContainerItem(bag, slot)

    -- Equip to mainhand (this puts current mainhand into cursor)
    PickupInventoryItem(MAINHAND_SLOT)

    -- Place cursor item (old mainhand) back to bag slot
    PickupContainerItem(bag, slot)

    swapInProgress = false

    DebugMsg("Swapped to: " .. targetWeapon)

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
        -- /gcdswap save <name> [Weapon1] [Weapon2]
        local name = args[2]
        local weapon1 = CleanItemName(args[3])
        local weapon2 = CleanItemName(args[4])

        if not name or not weapon1 or not weapon2 then
            ErrorMsg("Usage: /gcdswap save <name> [Weapon1] [Weapon2]")
            ErrorMsg("Example: /gcdswap save abc [Aurastone Hammer] [Mace of Unending Life]")
            return
        end

        SavePreset(name, weapon1, weapon2)

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
        PrintMsg("  /gcdswap save <name> [Weapon1] [Weapon2]")
        PrintMsg("  /gcdswap delete <name>")
        PrintMsg("  /gcdswap list")
        PrintMsg("  /gcdswap status")
        PrintMsg("  /gcdswap debug - Toggle debug")
        PrintMsg("  /gcdswap sound - Toggle sound")

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
