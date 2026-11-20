--[[
Confirm Buff Removal
====================

Right-clicking one of your buffs normally removes it at once. This addon asks
"Are you sure?" first. Only buffs are covered: debuffs and weapon enchants
behave as usual.

How it works
------------
1. An invisible "overlay" frame sits on top of each of your buff buttons. It
   catches the right-click, so the game's own instant removal never fires,
   and opens a confirmation dialog instead.

2. When you click Accept:
   - Out of combat, the addon removes the buff itself.
   - In combat, addons aren't allowed to remove buffs. So the addon unlocks
     that one buff instead: it hides the overlay for a few seconds, and your
     next right-click reaches the game's own button, which removes the buff.
   - Druid forms, Stealth and Shadowform can never be removed by addons, so
     they are always unlocked the same way.

3. Hovering a buff still shows its normal tooltip, because the overlay passes
   the hover on to the buff button underneath.

The file reads from top to bottom: settings and state, small helpers, looking
up auras, unlocking a buff, the dialog, the overlays, and finally the events
that start everything.
]]

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------
local TITLE = "Confirm Buff Removal"   -- addon name, used in chat messages
local DIALOG = "CONFIRM_BUFF_REMOVAL"  -- this addon's key in StaticPopupDialogs
local UNLOCK_SECONDS = 5               -- how long an unlocked buff stays unlocked
local CHECK_SECONDS = 2                -- time the server gets to confirm a removal
local MAX_BUFFS = 255                  -- upper limit when scanning your buff list
local OVERLAY_LEVEL = 5                -- frame levels the overlay sits above its button

local CHAT_COLOR = "|cff33ff99"        -- color of the addon name in chat
local NAME_COLOR = "|cffffd100"        -- color of the buff name in the dialog

----------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------
local overlays = {}       -- buff button -> the overlay frame on top of it
local containers = {}     -- Blizzard frames whose buff buttons get overlays

-- The one buff that is currently unlocked. It is remembered by its aura id
-- (armedID) when the game provides one, otherwise by its button (armedButton).
local armedID, armedButton
local armToken = 0        -- goes up on every lock and unlock, so old timers know they're stale

local serial = 0          -- goes up whenever buffs are gained or lost
local syncQueued = false  -- true while a Sync() is already waiting for the next frame

local Sync                -- defined in the overlays section, but needed before that

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

--- Prints a message to chat, prefixed with the addon's name.
local function Print(msg)
    print(CHAT_COLOR .. TITLE .. "|r: " .. msg)
end

--- WoW Forever hides some aura values from addons ("secret values"), and
--- those can't be compared like normal values. Plain() turns them into nil,
--- so whatever it returns is safe to compare.
local function Plain(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    return v
end

----------------------------------------------------------------------------
-- Looking up auras
----------------------------------------------------------------------------

--- Returns the id of the aura a buff button is showing. Unlike the button's
--- position, the id stays the same when the buttons are reshuffled.
--- Returns nil if the game won't say.
local function AuraID(button)
    local info = button.buttonInfo
    if type(info) ~= "table" then return nil end

    local id = Plain(info.auraInstanceID)
    if id then return id end

    -- The default buff frame only stores the buff's position in your buff
    -- list (the same number its own right-click hands to CancelUnitBuff),
    -- so look the aura up by that position.
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local index = Plain(info.index)
    if not (get and type(index) == "number") then return nil end
    local ok, aura = pcall(get, "player", index, "HELPFUL")
    if ok and type(aura) == "table" then return Plain(aura.auraInstanceID) end
    return nil
end

--- True if a button is showing one of your own buffs. Edit Mode's example
--- icons are skipped, and so are a vehicle's buffs: in a vehicle the buff
--- frame shows those instead of yours, and they are left to the game.
local function IsPlayerBuff(button)
    local unit = button.unit
    return button.auraType == "Buff" and not button.isExample
        and (unit == nil or unit == "player")
end

--- Returns the aura with this id from your buffs, or nil if it's gone.
local function GetAura(id)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    if not (id and get) then return nil end
    local ok, aura = pcall(get, "player", id)
    if ok and type(aura) == "table" then return aura end
    return nil
end

--- Returns the aura's position in your buff list, which is what
--- CancelUnitBuff expects, or nil if it isn't there.
local function IndexFor(id)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then return nil end
    for i = 1, MAX_BUFFS do
        local ok, aura = pcall(get, "player", i, "HELPFUL")
        if not ok or type(aura) ~= "table" then return nil end -- reached the end
        if Plain(aura.auraInstanceID) == id then return i end
    end
    return nil
end

--- True for druid forms, Stealth, Shadowform and anything else on your
--- stance bar. The game never lets addons remove those, even out of combat.
local function IsForm(aura)
    local spellID = aura and Plain(aura.spellId)
    if not (spellID and GetNumShapeshiftForms and GetShapeshiftFormInfo) then return false end
    for i = 1, GetNumShapeshiftForms() or 0 do
        local _, _, _, formSpellID = GetShapeshiftFormInfo(i)
        if Plain(formSpellID) == spellID then return true end
    end
    return false
end

----------------------------------------------------------------------------
-- Unlocking one buff so the game's own right-click can remove it
----------------------------------------------------------------------------

--- Locks the unlocked buff again, if there is one.
local function Disarm()
    if not (armedID or armedButton) then return end
    armedID, armedButton = nil, nil
    armToken = armToken + 1
    Sync()
end

--- Unlocks one buff for UNLOCK_SECONDS and tells the player to right-click
--- it again. `why` is an optional reason shown in front of that message.
local function Arm(id, button, why)
    -- Remember the buff by its aura id if there is one, since that survives
    -- the buttons being reshuffled. Otherwise remember the button.
    if id then
        armedID, armedButton = id, nil
    else
        armedID, armedButton = nil, button
    end

    -- Lock it again after UNLOCK_SECONDS, unless a buff has been locked or
    -- unlocked in the meantime (then the token no longer matches).
    armToken = armToken + 1
    local token = armToken
    C_Timer.After(UNLOCK_SECONDS, function()
        if token == armToken then Disarm() end
    end)

    Sync()
    Print((why or "") .. "Right-click the buff again within " .. UNLOCK_SECONDS .. " seconds to remove it.")
end

--- True if this button is showing the unlocked buff.
local function IsArmed(button)
    if armedID then return AuraID(button) == armedID end
    return armedButton ~= nil and armedButton == button
end

----------------------------------------------------------------------------
-- The confirmation dialog
----------------------------------------------------------------------------

--- Runs when you click Accept. `data` is the table Ask() gave the dialog.
local function Remove(data)
    local id, button = data.id, data.button

    -- Make sure the buff is still there, and still the one you were asked about.
    if id then
        if not GetAura(id) then return end -- it ran out while the dialog was open
    elseif data.serial ~= serial then
        -- Without an aura id only the button is known, and your buffs have
        -- changed since, so that button may now show a different buff.
        Print("Your buffs changed, so nothing was removed. Right-click the buff again.")
        return
    end

    -- When the addon isn't allowed to remove the buff, unlock it instead.
    if InCombatLockdown() then
        Arm(id, button, "Addons can't remove buffs in combat. ")
        return
    end
    if IsForm(GetAura(id)) then
        Arm(id, button, "Addons can't remove forms or stances. ")
        return
    end
    local index = id and CancelUnitBuff and IndexFor(id)
    if not index then
        Arm(id, button)
        return
    end

    -- Remove it. If it's still there a moment later, the game refused, so
    -- fall back to unlocking it.
    pcall(CancelUnitBuff, "player", index, "HELPFUL")
    C_Timer.After(CHECK_SECONDS, function()
        if GetAura(id) then Arm(id, button, "Couldn't remove it directly. ") end
    end)
end

StaticPopupDialogs[DIALOG] = {
    text = "Are you sure you want to remove %s?",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(_, data)
        if data then Remove(data) end
    end,
    -- There is deliberately no enterClicksFirstButton: Enter does nothing
    -- and Escape cancels, so only a click on Accept removes the buff.
    hideOnEscape = true,
    whileDead = true,
    timeout = 0,          -- never close on its own
    preferredIndex = 3,   -- a slot Blizzard rarely uses, to avoid tainting its own dialogs
}

--- Opens the confirmation dialog for the buff on this button.
local function Ask(button)
    local id = AuraID(button)
    local aura = GetAura(id)
    local name = aura and Plain(aura.name)

    local label = "this buff"
    if type(name) == "string" and name ~= "" then
        label = NAME_COLOR .. name .. "|r"
    end

    -- The table is handed to OnAccept, and from there to Remove().
    StaticPopup_Show(DIALOG, label, nil, { id = id, button = button, serial = serial })
end

----------------------------------------------------------------------------
-- Overlays on the buff buttons
----------------------------------------------------------------------------

-- The overlay covers the buff, so the game thinks the mouse is over the
-- overlay, not the buff, and the buff never shows its tooltip. The next two
-- functions pass the hover on to the buff so its normal tooltip appears.

--- Shows the buff's tooltip.
local function ShowTooltip(button)
    local onEnter = button:GetScript("OnEnter")
    if onEnter then pcall(onEnter, button, true) end
    if GameTooltip:IsOwned(button) then return end

    -- The buff's own code showed nothing, so build the tooltip here instead.
    local id = AuraID(button)
    if not id then return end
    local ok = pcall(function()
        GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetUnitBuffByAuraInstanceID("player", id, "HELPFUL")
        GameTooltip:Show()
    end)
    if not ok and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

--- Hides the buff's tooltip.
local function HideTooltip(button)
    local onLeave = button:GetScript("OnLeave")
    if onLeave then pcall(onLeave, button, true) end
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

--- Creates the invisible overlay that catches clicks on one buff button.
local function MakeOverlay(button)
    local ok, overlay = pcall(CreateFrame, "Frame", nil, button)
    if not ok or not overlay then return nil end

    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + OVERLAY_LEVEL)
    overlay:EnableMouse(true)
    overlay:SetScript("OnEnter", function() ShowTooltip(button) end)
    overlay:SetScript("OnLeave", function() HideTooltip(button) end)
    overlay:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "RightButton" then Ask(button) end
    end)

    overlays[button] = overlay
    return overlay
end

--- Gives every buff button an overlay, and shows each overlay only where it
--- should block clicks: on your own buffs, except the one that's unlocked.
function Sync()
    syncQueued = false
    for _, container in ipairs(containers) do
        local buttons = container.auraFrames
        if type(buttons) == "table" then
            for _, button in ipairs(buttons) do
                local overlay = overlays[button] or MakeOverlay(button)
                if overlay then
                    overlay:SetShown(IsPlayerBuff(button) and not IsArmed(button))
                end
            end
        end
    end
end

--- Starts covering a Blizzard frame's buff buttons, and re-checks them each
--- time that frame redraws them. hooksecurefunc runs Sync after Blizzard's
--- own function without changing it, so the buff buttons keep working in
--- combat.
local function Watch(container)
    if type(container) ~= "table" then return end
    containers[#containers + 1] = container
    if type(container.UpdateAuraButtons) == "function" then
        hooksecurefunc(container, "UpdateAuraButtons", Sync)
    end
end

--- Runs Sync() on the next frame. Several events in a row still cause only
--- one Sync().
local function QueueSync()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0, Sync)
end

----------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------

--- True if a UNIT_AURA update gained or lost auras, rather than only
--- refreshing ones you already had.
local function BuffsGainedOrLost(info)
    if not info or info.isFullUpdate then return true end
    local added, removed = info.addedAuras, info.removedAuraInstanceIDs
    return (added ~= nil and #added > 0) or (removed ~= nil and #removed > 0)
end

--- Runs once, after the game has loaded its own interface.
local function OnLogin(frame)
    -- Re-check after every loading screen and whenever your buffs change.
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterUnitEvent("UNIT_AURA", "player")
    -- Registering an event the game doesn't have is an error, and this one
    -- may not exist in every version of the game.
    pcall(frame.RegisterEvent, frame, "WEAPON_ENCHANT_CHANGED")

    Watch(BuffFrame)
    -- With the consolidateBuffs setting, long buffs move to a pop-out list
    -- whose buttons also remove a buff on right-click.
    local consolidated = BuffFrame and BuffFrame.ConsolidatedBuffs
    Watch(consolidated and consolidated.Tooltip and consolidated.Tooltip.Auras)

    Sync()
end

--- Runs whenever your buffs or weapon enchants may have changed.
local function OnBuffsChanged(event, info)
    -- Parts of the update can be secret values (see Plain). If reading it
    -- fails, assume something changed.
    local ok, changed = true, true
    if event == "UNIT_AURA" then ok, changed = pcall(BuffsGainedOrLost, info) end

    if not ok or changed then
        serial = serial + 1
        -- An unlock tied to a button (not an aura id) can't survive the
        -- buttons shuffling; one tied to an aura ends when that aura is gone.
        if armedButton or (armedID and not GetAura(armedID)) then Disarm() end
    end
    QueueSync()
end

-- For UNIT_AURA the event arguments are (unit, updateInfo).
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, _, info)
    if event == "PLAYER_LOGIN" then
        OnLogin(self)
    else
        OnBuffsChanged(event, info)
    end
end)
