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
local commodityDialog
local commodityPurchase

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
end

local function FindPopup(which, data)
    local found
    if type(StaticPopup_FindVisible) == "function" then
        local dialog = StaticPopup_FindVisible(which, data)
        if MatchesPopup(dialog, which, data) then found = dialog end
    end

    -- Legacy fallback; refuse ambiguous matches instead of guessing.
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local dialog = _G["StaticPopup" .. i]
        if MatchesPopup(dialog, which, data) then
            if found and found ~= dialog then return nil end
            found = dialog
        end
    end
    return found
end

local function GetAcceptButton(dialog)
    local button = dialog.GetButton and dialog:GetButton(1) or dialog.button1 or dialog.Button1
    if not button and dialog.GetName then
        local name = dialog:GetName()
        if name then button = _G[name .. "Button1"] end
    end
    return button
end

local function GetTransactionPrice(which, data)
    if IsSecret(data) or type(data) ~= "table" then return nil end
    local amount
    -- Verified on the Retail AuctionHouseFrame source. No speculative
    -- commodity price field: a configured cap requires a known total.
    if which == "BUYOUT_AUCTION" then
        amount = data.buyout
    elseif which == "BID_AUCTION" then
        amount = data.bid
    end
    if IsPositiveInteger(amount) then return amount end
    return nil
end

local function TryAccept(which, data, db)
    if not IsAuctionHouseOpen() then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not IsSafetyKeyHeld(GetSafetyKey(db)) then return end

    local dialog = FindPopup(which, data)
    if not dialog then
        Debug(db, "Manual confirmation: missing or ambiguous dialog (" .. which .. ").")
        return
    end
    local button = GetAcceptButton(dialog)
    if not IsVisible(button) or not button.IsEnabled or not button.Click then return end
    local enabled = button:IsEnabled()
    if IsSecret(enabled) or (enabled ~= true and enabled ~= 1) then return end
    if button.IsProtected and button:IsProtected() then
        Debug(db, "Manual confirmation: protected button.")
        return
    end

    if db.maxPriceCopper then
        local amount = GetTransactionPrice(which, data)
        if not amount then
            Debug(db, "Manual confirmation: transaction total unavailable.")
            return
        elseif amount > db.maxPriceCopper then
            Debug(db, "Manual confirmation: transaction exceeds the price limit.")
            return
        end
    end

    -- Use the visible button only. Never invoke the internal accept handler
    -- or retry if the client blocks this click.
    button:Click()
    Debug(db, "Confirmation click attempted: " .. which .. ".")
end

local function OnPopupShown(which, _, _, data)
    if not initialized or handlingPopup or IsSecret(which) or type(which) ~= "string" then return end
    if not AH_POPUPS[which] then return end
    -- The dedicated dialog has its own quote-based handler below.
    if which == "CONFIRM_COMMODITY_PURCHASE" and AuctionHouseFrame
        and IsVisible(AuctionHouseFrame.BuyDialog) then return end
    local db = EnsureDB()
    if not db.isEnabled then return end

    handlingPopup = true
    local ok = pcall(TryAccept, which, data, db)
    handlingPopup = false
    if not ok then
        -- Do not retry: the purchase might already have been submitted.
        print(PREFIX .. "|cffff2020Automatic confirmation could not be verified. Check the transaction before retrying.|r")
    end
end

-- Commodity purchases use a dedicated BuyDialog, not StaticPopup_Show.
-- Wait for the actual quote; never confirm a price increase automatically.
local function InstallCommodityHook()
    local db = EnsureDB()
    local dialog = AuctionHouseFrame and AuctionHouseFrame.BuyDialog
    if dialog and dialog == commodityDialog then return end
    if IsForbidden(dialog) or type(dialog.SetItemID) ~= "function"
        or type(dialog.HookScript) ~= "function" or not dialog.BuyNowButton
        or type(hooksecurefunc) ~= "function" then
        Debug(db, "Commodity BuyDialog or required methods unavailable.")
        return
    end
    commodityDialog = dialog
    hooksecurefunc(dialog, "SetItemID", function(self, itemID, quantity, unitPrice, totalPrice)
        -- Capture a new purchase only while the dialog is closed. A subsequent
        -- update to a visible dialog must not replace the original price.
        if self ~= commodityDialog or IsVisible(self) then return end
        commodityPurchase = nil
        if not IsPositiveInteger(itemID) or not IsPositiveInteger(quantity)
            or not IsPositiveInteger(unitPrice) or not IsPositiveInteger(totalPrice) then
            Debug(EnsureDB(), "Commodity purchase: initial quote unavailable; manual confirmation.")
            return
        end
        local settings = EnsureDB()
        if not settings.isEnabled or not IsSafetyKeyHeld(GetSafetyKey(settings)) then return end
        commodityPurchase = { dialog = self, unitPrice = unitPrice, totalPrice = totalPrice }
        Debug(settings, "Commodity purchase detected; waiting for server quote.")
    end)
    dialog:HookScript("OnHide", function(self)
        if self == commodityDialog then commodityPurchase = nil end
    end)
    Debug(db, "Commodity BuyDialog hook installed.")
end

local function OnCommodityQuote(unitPrice, totalPrice)
    local db = EnsureDB()
    local purchase = commodityPurchase
    if not purchase then
        Debug(db, "Commodity quote received without eligible initial purchase.")
        return
    end
    if purchase.quoted then
        -- Ignore duplicate quote notifications, but invalidate a changed quote.
        if not IsPositiveInteger(unitPrice) or not IsPositiveInteger(totalPrice)
            or unitPrice ~= purchase.quotedUnit or totalPrice ~= purchase.quotedTotal then
            commodityPurchase = nil
            Debug(db, "Commodity quote changed again; manual confirmation.")
        end
        return
    end
    if not IsPositiveInteger(unitPrice) or not IsPositiveInteger(totalPrice)
        or unitPrice > purchase.unitPrice or totalPrice > purchase.totalPrice then
        commodityPurchase = nil
        Debug(db, "Commodity price increased or quote invalid; manual confirmation.")
        return
    end
    purchase.quoted = true
    purchase.quotedUnit, purchase.quotedTotal = unitPrice, totalPrice
    if not C_Timer or type(C_Timer.After) ~= "function" then
        commodityPurchase = nil
        Debug(db, "Commodity timer unavailable; manual confirmation.")
        return
    end
    -- Let Blizzard process COMMODITY_PRICE_UPDATED before checking the button.
    C_Timer.After(0, function()
        if commodityPurchase ~= purchase then return end
        commodityPurchase = nil -- One attempt per purchase, no retries.
        local settings = EnsureDB()
        local dialog = purchase.dialog
        if handlingPopup or not settings.isEnabled or not IsAuctionHouseOpen()
            or (InCombatLockdown and InCombatLockdown())
            or not IsSafetyKeyHeld(GetSafetyKey(settings))
            or not AuctionHouseFrame or AuctionHouseFrame.BuyDialog ~= dialog
            or not IsVisible(dialog) then
            Debug(settings, "Commodity purchase no longer eligible; manual confirmation.")
            return
        end
        if settings.maxPriceCopper and totalPrice > settings.maxPriceCopper then
            Debug(settings, "Commodity purchase exceeds the price limit; manual confirmation.")
            return
        end
        local button = dialog.BuyNowButton
        if not IsVisible(button) or type(button.IsEnabled) ~= "function"
            or type(button.Click) ~= "function" then
            Debug(settings, "Commodity BuyNowButton unavailable; manual confirmation.")
            return
        end
        local enabled = button:IsEnabled()
        if IsSecret(enabled) or (enabled ~= true and enabled ~= 1) then
            Debug(settings, "Commodity BuyNowButton disabled; manual confirmation.")
            return
        end
        if button.IsProtected and button:IsProtected() then
            Debug(settings, "Commodity BuyNowButton protected; manual confirmation.")
            return
        end
        handlingPopup = true
        local ok, err = pcall(button.Click, button)
        handlingPopup = false
        if ok then
            Debug(settings, "Commodity BuyNowButton click attempted.")
        else
            print(PREFIX .. "Commodity confirmation blocked or failed; check the transaction before retrying.")
            if type(err) == "string" and not IsSecret(err) then Debug(settings, err) end
        end
    end)
end

local hookInstalled = false
local function InstallHook()
    if not hookInstalled and type(StaticPopup_Show) == "function" and type(hooksecurefunc) == "function" then
        hooksecurefunc("StaticPopup_Show", OnPopupShown)
        hookInstalled = true
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
eventFrame:RegisterEvent("COMMODITY_PRICE_UPDATED")
eventFrame:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE")
eventFrame:RegisterEvent("COMMODITY_PURCHASE_FAILED")
eventFrame:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            EnsureDB()
            initialized = true
        end
        InstallHook()
        if initialized and hookInstalled then self:UnregisterEvent("ADDON_LOADED") end
    elseif event == "PLAYER_LOGIN" then
        local db = EnsureDB()
        initialized = true
        InstallHook()
        if hookInstalled then self:UnregisterEvent("ADDON_LOADED") end
        PrintStatus(db)
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "AUCTION_HOUSE_SHOW" then
        InstallCommodityHook()
        -- Also cover a frame initialized after this event handler.
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                if IsAuctionHouseOpen() then InstallCommodityHook() end
            end)
        end
    elseif event == "COMMODITY_PRICE_UPDATED" then
        OnCommodityQuote(arg1, arg2)
    elseif event == "AUCTION_HOUSE_CLOSED" or event == "COMMODITY_PRICE_UNAVAILABLE"
        or event == "COMMODITY_PURCHASE_FAILED" or event == "COMMODITY_PURCHASE_SUCCEEDED" then
        commodityPurchase = nil
    end
end)
InstallHook()

SLASH_BOUGIESAUTOACCEPTPOPUP1 = "/baap"
SlashCmdList["BOUGIESAUTOACCEPTPOPUP"] = function(message)
    local db = EnsureDB()
    local input = (message or ""):match("^%s*(.-)%s*$"):lower()
    local cmd, arg = input:match("^(%S+)%s*(.-)$")
    cmd, arg = cmd or "", arg or ""

    if cmd == "on" and arg == "" then
        db.isEnabled = true
        PrintStatus(db)
    elseif cmd == "off" and arg == "" then
        db.isEnabled = false
        commodityPurchase = nil
        sessionNone = false
        PrintStatus(db)
    elseif (cmd == "alt" or cmd == "ctrl" or cmd == "shift" or cmd == "maj") and arg == "" then
        sessionNone = false
        db.safetyKey = cmd == "maj" and "SHIFT" or cmd:upper()
        PrintStatus(db)
    elseif cmd == "none" and arg == "" then
        sessionNone = true
        print(PREFIX .. "|cffff2020WARNING: eligible purchase dialogs can be accepted without a key until reload, logout or /baap off.|r")
        PrintStatus(db)
    elseif cmd == "limit" then
        if arg == "off" then
            db.maxPriceCopper = false
            print(PREFIX .. "|cffff2020WARNING: no transaction price limit.|r")
        elseif arg:match("^%d+$") then
            local gold = tonumber(arg)
            if not IsPositiveInteger(gold) or gold > math.floor(MAX_SAFE_INTEGER / COPPER_PER_GOLD) then
                print(PREFIX .. "Invalid limit. Enter a positive whole number of gold.")
                return
            end
            db.maxPriceCopper = gold * COPPER_PER_GOLD
        else
            print(PREFIX .. "Usage: /baap limit <whole gold> | off")
            return
        end
        PrintStatus(db)
    elseif cmd == "debug" and (arg == "on" or arg == "off") then
        db.debug = arg == "on"
        PrintStatus(db)
    else
        PrintStatus(db)
        print("Commands: /baap on | off | alt | ctrl | shift | maj | none")
        print("/baap limit <whole gold> | off ; /baap debug on | off")
    end
end
