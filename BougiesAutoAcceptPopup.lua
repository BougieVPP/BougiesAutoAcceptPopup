local ADDON_NAME = ...

-- Liste des popups de l'hôtel des ventes moderne (Midnight / Retail)
local AH_POPUPS = {
    ["BUYOUT_AUCTION"] = true,
    ["BID_AUCTION"] = true,
    ["CONFIRM_COMMODITY_PURCHASE"] = true,
    ["AUCTION_HOUSE_POST_WARNING"] = true,
}

-- Touche de sécurité : Alt
local function IsSafetyKeyHeld()
    return IsAltKeyDown()
end

-- Initialisation de la sauvegarde au chargement de l'addon
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == ADDON_NAME then
        if type(BougiesAutoAcceptPopupDB) ~= "table" then
            BougiesAutoAcceptPopupDB = { isEnabled = false }
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Gestion des commandes /baap on et /baap off
SLASH_BOUGIESAUTOACCEPTPOPUP1 = "/baap"
SlashCmdList["BOUGIESAUTOACCEPTPOPUP"] = function(msg)
    local cmd = string.lower(strtrim(msg or ""))
    
    if cmd == "on" then
        BougiesAutoAcceptPopupDB.isEnabled = true
        print("|cff00ff00[Bougie's Auto Accept Popup]|r : ACTIVÉ (maintenez Alt pour valider).")
    elseif cmd == "off" then
        BougiesAutoAcceptPopupDB.isEnabled = false
        print("|cffff0000[Bougie's Auto Accept Popup]|r : DÉSACTIVÉ.")
    else
        local isEnabled = BougiesAutoAcceptPopupDB and BougiesAutoAcceptPopupDB.isEnabled
        local status = isEnabled and "|cff00ff00ACTIVÉ|r" or "|cffff0000DÉSACTIVÉ|r"
        print("|cffffff00[Bougie's Auto Accept Popup]|r Statut actuel : " .. status)
        print("Utilisation : |cff00ccff/baap on|r ou |cff00ccff/baap off|r")
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

