local ADDON_NAME = ...
local PREFIX = "|cffffff00[Bougie's Auto Accept Popup]|r "
local COPPER_PER_GOLD = 10000
local MAX_SAFE_INTEGER = 9007199254740991

-- Only documented purchase dialogs. Selling and other warnings stay manual.
local AH_POPUPS = {
    BUYOUT_AUCTION = true,
    BID_AUCTION = true,
    CONFIRM_COMMODITY_PURCHASE = true,
}

local KEY_LABELS = {
    ALT = "|cff00ccffALT|r",
    CTRL = "|cff00ccffCTRL|r",
    SHIFT = "|cff00ccffSHIFT|r",
    NONE = "|cffff2020NONE (NO SAFETY KEY)|r",
}
local sessionNone = false
local initialized = false
local handlingPopup = false

local function IsSecret(value)
    if issecretvalue and issecretvalue(value) then return true end
    if canaccessvalue and not canaccessvalue(value) then return true end
    return false
end

local function IsPositiveInteger(value)
    return not IsSecret(value) and type(value) == "number" and value > 0
        and value <= MAX_SAFE_INTEGER and value == math.floor(value)
end

local function EnsureDB()
    if type(BougiesAutoAcceptPopupDB) ~= "table" then
        BougiesAutoAcceptPopupDB = {}
    end
    local db = BougiesAutoAcceptPopupDB
    if type(db.isEnabled) ~= "boolean" then db.isEnabled = false end
    -- NONE is now session-only; migrate previously saved NONE to ALT.
    if db.safetyKey ~= "ALT" and db.safetyKey ~= "CTRL" and db.safetyKey ~= "SHIFT" then
        db.safetyKey = "ALT"
    end
    if db.maxPriceCopper ~= false and not IsPositiveInteger(db.maxPriceCopper) then
        db.maxPriceCopper = false
    end
    if type(db.debug) ~= "boolean" then db.debug = false end
    return db
end

local function GetSafetyKey(db)
    return sessionNone and "NONE" or db.safetyKey
end

local function IsSafetyKeyHeld(key)
    if key == "NONE" then return true end
    local check = ({ ALT = IsAltKeyDown, CTRL = IsControlKeyDown, SHIFT = IsShiftKeyDown })[key]
    if type(check) ~= "function" then return false end
    local held = check()
    return not IsSecret(held) and (held == true or held == 1)
end

local function Debug(db, message)
    if db.debug then print(PREFIX .. message) end
end

local function PrintStatus(db)
    local status = db.isEnabled and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"
    local limit = db.maxPriceCopper and (tostring(db.maxPriceCopper / COPPER_PER_GOLD) .. " gold") or "OFF"
    print(PREFIX .. "Status: " .. status .. " | Key: " .. KEY_LABELS[GetSafetyKey(db)]
        .. " | Limit: " .. limit .. " | Debug: " .. (db.debug and "ON" or "OFF"))
end

local function IsForbidden(frame)
    return not frame or (frame.IsForbidden and frame:IsForbidden())
end

local function IsVisible(frame)
    if IsForbidden(frame) then return false end
    local check = frame.IsVisible or frame.IsShown
    if type(check) ~= "function" then return false end
    local visible = check(frame)
    return not IsSecret(visible) and (visible == true or visible == 1)
end

local function IsAuctionHouseOpen()
    return IsVisible(AuctionHouseFrame) or IsVisible(AuctionFrame)
end

-- Check both the identifier and the data passed to StaticPopup_Show.
local function MatchesPopup(dialog, which, data)
    if not IsVisible(dialog) or IsSecret(dialog.which) or dialog.which ~= which then
        return false
    end
    if IsSecret(dialog.data) or IsSecret(data) then return false end
    return rawequal(dialog.data, data)
