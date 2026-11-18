-- SlimFrames: minimale Unit Frames fuer WoW: Forever (Midnight-API, secret values)
-- Regel Nr. 1: Health/Power/Cast-Werte NIE verrechnen, nur direkt an StatusBars/FontStrings reichen.

local ADDON = ...
local FLAT = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT

local HP_H, PP_H = 24, 5

local defaults = { scale = 1, width = 220, classColor = true }

local DB
local frames = {}
local unlocked = false
local pendingApply = false

local ORDER = { "player", "target", "targettarget", "focus" }
local LAYOUT = {
    player       = { w = 1.0, cast = true,  pos = { "CENTER", "CENTER", -260, -170 } },
    target       = { w = 1.0, cast = true,  pos = { "CENTER", "CENTER",  260, -170 } },
    targettarget = { w = 0.55, cast = false, pos = { "CENTER", "CENTER",  260, -225 } },
    focus        = { w = 0.70, cast = true,  pos = { "CENTER", "CENTER", -260, -225 } },
}

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_EMPOWER_UPDATE",
}

------------------------------------------------------------------------
-- Farben (alles in pcall, falls ein Wert "secret" ist)
------------------------------------------------------------------------
local function HealthColor(u)
    local r, g, b = 0.2, 0.8, 0.25
    pcall(function()
        if DB.classColor and UnitIsPlayer(u) then
            local _, class = UnitClass(u)
            local c = class and RAID_CLASS_COLORS[class]
            if c then r, g, b = c.r, c.g, c.b end
        else
            local reaction = UnitReaction("player", u)
            if reaction then
                if reaction <= 2 then r, g, b = 0.8, 0.2, 0.2
                elseif reaction == 4 then r, g, b = 0.95, 0.8, 0.2 end
            end
        end
    end)
    return r, g, b
end

local function PowerColor(u)
    local r, g, b = 0.3, 0.4, 0.9
    pcall(function()
        local t, token = UnitPowerType(u)
        local c = PowerBarColor and (PowerBarColor[token] or PowerBarColor[t])
        if c then r, g, b = c.r, c.g, c.b end
    end)
    return r, g, b
end

------------------------------------------------------------------------
-- Update
------------------------------------------------------------------------
local function UpdateCast(f)
    if not f.cast then return end
    local u = f.unit
    local ok = pcall(function()
        local dur, dir
        if UnitCastingDuration then dur = UnitCastingDuration(u) end
        if dur then
            dir = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime
        elseif UnitChannelDuration then
            dur = UnitChannelDuration(u)
            dir = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
        end
        if dur and f.cast.SetTimerDuration then
            f.cast:SetTimerDuration(dur, Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate, dir)
            f.cast:Show()
        else
            f.cast:Hide()
        end
    end)
    if not ok then f.cast:Hide() end
end

local function Update(f)
    local u = f.unit
    if not UnitExists(u) then
        f.name:SetText(unlocked and u or "")
        f.hpText:SetText("")
        f.hp:SetMinMaxValues(0, 1); f.hp:SetValue(0)
        f.pp:SetMinMaxValues(0, 1); f.pp:SetValue(0)
        if f.cast then f.cast:Hide() end
        return
    end

    f.name:SetText(UnitName(u))

    pcall(function()
        f.hp:SetMinMaxValues(0, UnitHealthMax(u))
        f.hp:SetValue(UnitHealth(u))
    end)
    f.hp:SetStatusBarColor(HealthColor(u))

    pcall(function()
        f.pp:SetMinMaxValues(0, UnitPowerMax(u))
        f.pp:SetValue(UnitPower(u))
    end)
    f.pp:SetStatusBarColor(PowerColor(u))

    local ok = pcall(function()
        f.hpText:SetFormattedText("%.0f%%", UnitHealthPercent(u, true, CurveConstants.ScaleTo100))
    end)
    if not ok then f.hpText:SetText("") end

    UpdateCast(f)
end

------------------------------------------------------------------------
-- Frames bauen
------------------------------------------------------------------------
local function ApplyLayout(f)
    local cfg = LAYOUT[f.unit]
    f:SetScale(DB.scale)
    f:SetSize(DB.width * cfg.w, HP_H + PP_H + 3)
    local p = DB.pos and DB.pos[f.unit] or cfg.pos
    f:ClearAllPoints()
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function ApplyAll()
    if InCombatLockdown() then pendingApply = true return end
    pendingApply = false
    for _, f in pairs(frames) do ApplyLayout(f) end
end

local function CreateUnitFrame(unit)
    local cfg = LAYOUT[unit]
    local f = CreateFrame("Button", "SlimFrames_" .. unit, UIParent, "SecureUnitButtonTemplate")
    f.unit = unit
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("LOW")

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.65)

    f.hp = CreateFrame("StatusBar", nil, f)
    f.hp:SetStatusBarTexture(FLAT)
    f.hp:SetPoint("TOPLEFT", 1, -1)
    f.hp:SetPoint("TOPRIGHT", -1, -1)
    f.hp:SetHeight(HP_H)

    f.pp = CreateFrame("StatusBar", nil, f)
    f.pp:SetStatusBarTexture(FLAT)
    f.pp:SetPoint("TOPLEFT", f.hp, "BOTTOMLEFT", 0, -1)
    f.pp:SetPoint("TOPRIGHT", f.hp, "BOTTOMRIGHT", 0, -1)
    f.pp:SetHeight(PP_H)

    f.name = f.hp:CreateFontString(nil, "OVERLAY")
    f.name:SetFont(FONT, 12, "OUTLINE")
    f.name:SetPoint("LEFT", 4, 0)
    f.name:SetPoint("RIGHT", -40, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)

    f.hpText = f.hp:CreateFontString(nil, "OVERLAY")
    f.hpText:SetFont(FONT, 11, "OUTLINE")
    f.hpText:SetPoint("RIGHT", -4, 0)
    if cfg.w < 0.6 then f.hpText:Hide() end

    if cfg.cast then
        f.cast = CreateFrame("StatusBar", nil, f)
        f.cast:SetStatusBarTexture(FLAT)
        f.cast:SetStatusBarColor(0.95, 0.75, 0.2)
        f.cast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
        f.cast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
        f.cast:SetHeight(8)
        f.cast.bg = f.cast:CreateTexture(nil, "BACKGROUND")
        f.cast.bg:SetAllPoints()
        f.cast.bg:SetColorTexture(0, 0, 0, 0.65)
        f.cast:Hide()
    end

    -- Events
    local function reg(ev, u)
        pcall(f.RegisterUnitEvent, f, ev, u)
    end
    reg("UNIT_HEALTH", unit)
    reg("UNIT_MAXHEALTH", unit)
    reg("UNIT_POWER_UPDATE", unit)
    reg("UNIT_MAXPOWER", unit)
    reg("UNIT_DISPLAYPOWER", unit)
    reg("UNIT_NAME_UPDATE", unit)
    reg("UNIT_FACTION", unit)
    if cfg.cast then
        for _, ev in ipairs(CAST_EVENTS) do reg(ev, unit) end
    end
    if unit == "target" then f:RegisterEvent("PLAYER_TARGET_CHANGED") end
    if unit == "focus" then f:RegisterEvent("PLAYER_FOCUS_CHANGED") end
    if unit == "targettarget" then
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        reg("UNIT_TARGET", "target")
    end
    f:SetScript("OnEvent", Update)
    f:SetScript("OnShow", Update)

    -- Mover (nur sichtbar bei "Frames verschieben")
    f.mover = CreateFrame("Frame", nil, UIParent)
    f.mover:SetAllPoints(f)
    f.mover:SetFrameStrata("DIALOG")
    f.mover:EnableMouse(true)
    f.mover:RegisterForDrag("LeftButton")
    f.mover.tex = f.mover:CreateTexture(nil, "OVERLAY")
    f.mover.tex:SetAllPoints()
    f.mover.tex:SetColorTexture(0.2, 0.5, 1, 0.45)
    f.mover:SetScript("OnDragStart", function() if not InCombatLockdown() then f:StartMoving() end end)
    f.mover:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint()
        DB.pos = DB.pos or {}
        DB.pos[unit] = { p, rp, x, y }
    end)
    f.mover:Hide()

    if unit ~= "player" then RegisterUnitWatch(f) end
    frames[unit] = f
    return f
end

local function SetUnlocked(flag)
    if InCombatLockdown() then
        print("|cffffd200SlimFrames:|r Nicht im Kampf.")
        return false
    end
    unlocked = flag
    for _, unit in ipairs(ORDER) do
        local f = frames[unit]
        if f then
            f.mover:SetShown(flag)
            if unit ~= "player" then
                if flag then
                    UnregisterUnitWatch(f)
                    f:Show()
                else
                    RegisterUnitWatch(f)
                end
            end
            Update(f)
        end
    end
    return true
end

------------------------------------------------------------------------
-- Blizzard-Frames loswerden
------------------------------------------------------------------------
local hider = CreateFrame("Frame")
hider:Hide()

local function HideBlizzard()
    if InCombatLockdown() then return end
    for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame" }) do
        local b = _G[name]
        if b then
            pcall(b.UnregisterAllEvents, b)
            pcall(b.SetParent, b, hider)
        end
    end
end

------------------------------------------------------------------------
-- Config-Fenster (absichtlich winzig)
------------------------------------------------------------------------
local panel

local function MakeCheck(parent, label, y, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(200, 20)
    b:SetPoint("TOPLEFT", 14, y)
    local box = b:CreateTexture(nil, "ARTWORK")
    box:SetSize(16, 16); box:SetPoint("LEFT"); box:SetColorTexture(0.15, 0.15, 0.15, 1)
    local tick = b:CreateTexture(nil, "OVERLAY")
    tick:SetSize(10, 10); tick:SetPoint("CENTER", box); tick:SetColorTexture(0.2, 0.8, 0.3, 1)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, 12, "")
    fs:SetPoint("LEFT", box, "RIGHT", 6, 0)
    fs:SetText(label)
    b.Refresh = function() tick:SetShown(get()) end
    b:SetScript("OnClick", function() set(not get()); b.Refresh() end)
    b.Refresh()
    return b
end

local function MakeSlider(parent, label, y, min, max, step, get, set)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, 12, "")
    fs:SetPoint("TOPLEFT", 14, y)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", 14, y - 20)
    s:SetSize(192, 12)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(); track:SetColorTexture(0.15, 0.15, 0.15, 1)
    s:SetThumbTexture(FLAT)
    local th = s:GetThumbTexture()
    th:SetSize(8, 16); th:SetVertexColor(0.85, 0.85, 0.85)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local function txt(v)
        fs:SetText(label .. ": " .. (step < 1 and string.format("%.2f", v) or string.format("%d", v)))
    end
    s:SetValue(get()); txt(get())
    s:SetScript("OnValueChanged", function(_, v) txt(v); set(v) end)
    return s
end

local function BuildPanel()
    panel = CreateFrame("Frame", "SlimFramesConfig", UIParent, "BackdropTemplate")
    panel:SetSize(230, 210)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true); panel:EnableMouse(true); panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    panel:SetBackdropBorderColor(0, 0, 0, 1)

    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 13, "OUTLINE")
    title:SetPoint("TOPLEFT", 14, -10)
    title:SetText("SlimFrames")

    local close = CreateFrame("Button", nil, panel)
    close:SetSize(20, 20); close:SetPoint("TOPRIGHT", -6, -6)
    local cx = close:CreateFontString(nil, "OVERLAY")
    cx:SetFont(FONT, 14, "OUTLINE"); cx:SetPoint("CENTER"); cx:SetText("x")
    close:SetScript("OnClick", function() panel:Hide() end)

    local unlock = MakeCheck(panel, "Frames verschieben", -34,
        function() return unlocked end,
        function(v) SetUnlocked(v) end)
    MakeCheck(panel, "Klassenfarben", -58,
        function() return DB.classColor end,
        function(v) DB.classColor = v; for _, f in pairs(frames) do Update(f) end end)
    MakeSlider(panel, "Groesse", -84, 0.6, 1.6, 0.05,
        function() return DB.scale end,
        function(v) DB.scale = v; ApplyAll() end)
    MakeSlider(panel, "Breite", -122, 140, 320, 10,
        function() return DB.width end,
        function(v) DB.width = v; ApplyAll() end)

    local reset = CreateFrame("Button", nil, panel)
    reset:SetSize(100, 20); reset:SetPoint("BOTTOMLEFT", 14, 10)
    local rbg = reset:CreateTexture(nil, "BACKGROUND")
    rbg:SetAllPoints(); rbg:SetColorTexture(0.2, 0.2, 0.2, 1)
    local rfs = reset:CreateFontString(nil, "OVERLAY")
    rfs:SetFont(FONT, 12, ""); rfs:SetPoint("CENTER"); rfs:SetText("Positionen reset")
    reset:SetScript("OnClick", function() DB.pos = {}; ApplyAll() end)

    panel:SetScript("OnHide", function() if unlocked then SetUnlocked(false) end end)
    panel:Hide()
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        SlimFramesDB = SlimFramesDB or {}
        DB = SlimFramesDB
        for k, v in pairs(defaults) do if DB[k] == nil then DB[k] = v end end
        DB.pos = DB.pos or {}
    elseif event == "PLAYER_LOGIN" then
        for _, unit in ipairs(ORDER) do CreateUnitFrame(unit) end
        ApplyAll()
        HideBlizzard()
        for _, f in pairs(frames) do Update(f) end
        BuildPanel()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingApply then ApplyAll() end
        HideBlizzard()
    end
end)

SLASH_SLIMFRAMES1 = "/slim"
SLASH_SLIMFRAMES2 = "/slimframes"
SlashCmdList["SLIMFRAMES"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "reset" then
        DB.pos = {}; ApplyAll()
    elseif panel then
        panel:SetShown(not panel:IsShown())
    end
end
