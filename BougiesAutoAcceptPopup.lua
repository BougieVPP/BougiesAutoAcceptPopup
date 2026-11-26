local ADDON_NAME = ...

-- Liste des popups de l'hôtel des ventes moderne (Midnight / Retail)
local AH_POPUPS = {
    ["BUYOUT_AUCTION"] = true,
    ["BID_AUCTION"] = true,
    ["CONFIRM_COMMODITY_PURCHASE"] = true,
    ["AUCTION_HOUSE_POST_WARNING"] = true,
}

-- Libellés lisibles pour l'affichage dans le chat
local KEY_LABELS = {
    ALT = "|cff00ccffALT|r",
    CTRL = "|cff00ccffCTRL|r",
    SHIFT = "|cff00ccffSHIFT|r",
    NONE = "|cffff2020/!\\ NONE (NO SAFETY KEY) /!\\|r",
}

-- Garantit que la base de données existe et contient des valeurs valides
local function EnsureDB()
    if type(BougiesAutoAcceptPopupDB) ~= "table" then
        BougiesAutoAcceptPopupDB = {}
    end
    if type(BougiesAutoAcceptPopupDB.isEnabled) ~= "boolean" then
        BougiesAutoAcceptPopupDB.isEnabled = false
    end
    if not KEY_LABELS[BougiesAutoAcceptPopupDB.safetyKey] then
        BougiesAutoAcceptPopupDB.safetyKey = "ALT"
    end
    return BougiesAutoAcceptPopupDB
end

-- Vérifie si la touche de sécurité configurée est maintenue
local function IsSafetyKeyHeld()
    local db = EnsureDB()
    if db.safetyKey == "NONE" then
        return true
    elseif db.safetyKey == "CTRL" then
        return IsControlKeyDown()
    elseif db.safetyKey == "SHIFT" then
        return IsShiftKeyDown()
    else
        return IsAltKeyDown()
    end
end

-- Initialisation des SavedVariables et rappel à la connexion
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        EnsureDB()
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        local db = EnsureDB()
        local status = db.isEnabled and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"
        local keyLabel = KEY_LABELS[db.safetyKey]
        print("|cffffff00[Bougie's Auto Accept Popup]|r Status: " .. status .. " | Key: " .. keyLabel)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Gestion des commandes /baap
SLASH_BOUGIESAUTOACCEPTPOPUP1 = "/baap"
SlashCmdList["BOUGIESAUTOACCEPTPOPUP"] = function(msg)
    local db = EnsureDB()
    local cmd = string.lower(strtrim(msg or ""))
    
    if cmd == "on" then
        db.isEnabled = true
        print("|cff00ff00[Bougie's Auto Accept Popup]|r: ENABLED (Key: " .. KEY_LABELS[db.safetyKey] .. ").")

    elseif cmd == "off" then
        db.isEnabled = false
        print("|cffff0000[Bougie's Auto Accept Popup]|r: DISABLED.")

    elseif cmd == "alt" or cmd == "ctrl" or cmd == "maj" or cmd == "shift" or cmd == "none" then
        local normalized = (cmd == "maj") and "SHIFT" or string.upper(cmd)
        db.safetyKey = normalized
        print("|cffffff00[Bougie's Auto Accept Popup]|r Security key set to: " .. KEY_LABELS[normalized])
        if normalized == "NONE" then
            print("|cffff2020[WARNING] All Auction House popups will be auto-accepted immediately without holding any key!|r")
        end

    else
        local status = db.isEnabled and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"
        print("|cffffff00[Bougie's Auto Accept Popup]|r Status: " .. status .. " | Key: " .. KEY_LABELS[db.safetyKey])
        print("Commands: |cff00ccff/baap on|r | |cff00ccffoff|r | |cff00ccffctrl|r | |cff00ccffalt|r | |cff00ccffshift|r | |cff00ccffnone|r")
    end
end

-- Validation automatique des popups sur AuctionHouseFrame
hooksecurefunc("StaticPopup_Show", function(which)
    if type(which) ~= "string" or (issecretvalue and issecretvalue(which)) then return end
    if not AH_POPUPS[which] then return end

    local db = EnsureDB()
    local isAHOpen = (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown())
    
    if db.isEnabled and isAHOpen and IsSafetyKeyHeld() then
        for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
            local dialog = _G["StaticPopup" .. i]
            if dialog and dialog:IsShown() and dialog.which == which then
                local button1 = dialog.button1 or _G["StaticPopup" .. i .. "Button1"]
                if button1 and button1:IsEnabled() then
                    if type(StaticPopup_OnClick) == "function" then
                        StaticPopup_OnClick(dialog, 1)
                    else
                        button1:Click()
                    end
                end
                break
            end
        end
    end
end)
