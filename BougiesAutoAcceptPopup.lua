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
    ALT = "ALT",
    CTRL = "CTRL",
    SHIFT = "SHIFT",
    NONE = "/!\ NONE /!\",
}

-- Vérifie si la touche de sécurité configurée est maintenue
local function IsSafetyKeyHeld()
    local key = (BougiesAutoAcceptPopupDB and BougiesAutoAcceptPopupDB.safetyKey) or "ALT"
    if key == "NONE" then
        return true
    elseif key == "CTRL" then
        return IsControlKeyDown()
    elseif key == "SHIFT" then
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
        if type(BougiesAutoAcceptPopupDB) ~= "table" then
            BougiesAutoAcceptPopupDB = {}
        end
        if BougiesAutoAcceptPopupDB.isEnabled == nil then
            BougiesAutoAcceptPopupDB.isEnabled = false
        end
        if not BougiesAutoAcceptPopupDB.safetyKey then
            BougiesAutoAcceptPopupDB.safetyKey = "ALT"
        end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        local status = BougiesAutoAcceptPopupDB.isEnabled and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"
        local keyLabel = KEY_LABELS[BougiesAutoAcceptPopupDB.safetyKey] or "Alt"
        print("|cffffff00[Bougie's Auto Accept Popup]|r Status : " .. status .. " | Key : |cff00ccff" .. keyLabel .. "|r")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Gestion des commandes /baap
SLASH_BOUGIESAUTOACCEPTPOPUP1 = "/baap"
SlashCmdList["BOUGIESAUTOACCEPTPOPUP"] = function(msg)
    local cmd = string.lower(strtrim(msg or ""))
    
    if cmd == "on" then
        BougiesAutoAcceptPopupDB.isEnabled = true
        local keyLabel = KEY_LABELS[BougiesAutoAcceptPopupDB.safetyKey] or "Alt"
        print("|cff00ff00[Bougie's Auto Accept Popup]|r : ENABLED (Key : |cff00ccff" .. keyLabel .. "|r).")

    elseif cmd == "off" then
        BougiesAutoAcceptPopupDB.isEnabled = false
        print("|cffff0000[Bougie's Auto Accept Popup]|r : DISABLED.")

    elseif cmd == "alt" or cmd == "ctrl" or cmd == "maj" or cmd == "shift" or cmd == "none" then
        local normalized = (cmd == "maj") and "SHIFT" or string.upper(cmd)
        BougiesAutoAcceptPopupDB.safetyKey = normalized
        local keyLabel = KEY_LABELS[normalized]
        print("|cffffff00[Bougie's Auto Accept Popup]|r Security key setup on : |cff00ccff" .. keyLabel .. "|r.")

    else
        local isEnabled = BougiesAutoAcceptPopupDB and BougiesAutoAcceptPopupDB.isEnabled
        local status = isEnabled and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"
        local keyLabel = KEY_LABELS[(BougiesAutoAcceptPopupDB and BougiesAutoAcceptPopupDB.safetyKey) or "ALT"]
        print("|cffffff00[Bougie's Auto Accept Popup]|r Status : " .. status .. " | Key : |cff00ccff" .. keyLabel .. "|r")
        print("Commands : |cff00ccff/baap on|r | |cff00ccffoff|r | |cff00ccffctrl|r | |cff00ccffalt|r | |cff00ccffmaj|r | |cff00ccffnone|r")
    end
end

-- Validation automatique des popups sur AuctionHouseFrame
hooksecurefunc("StaticPopup_Show", function(which)
    local isEnabled = BougiesAutoAcceptPopupDB and BougiesAutoAcceptPopupDB.isEnabled
    local isAHOpen = (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown())
    
    if isEnabled and isAHOpen and AH_POPUPS[which] and IsSafetyKeyHeld() then
        for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
            local dialog = _G["StaticPopup" .. i]
            if dialog and dialog:IsShown() and dialog.which == which then
                local button1 = dialog.button1 or _G["StaticPopup" .. i .. "Button1"]
                if button1 and button1:IsEnabled() then
                    button1:Click()
                end
                break
            end
        end
    end
end)
