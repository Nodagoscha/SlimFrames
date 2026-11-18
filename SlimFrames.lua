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
local testMode = false
local pendingApply = false

-- Beispieldaten fuer den Testmodus (eigene Zahlen, daher keine secret values)
local TEST = {
    player       = { hp = 0.85, pp = 0.70, cast = 0.8 },
    target       = { name = "Trainingsattrappe", hp = 0.62, pp = 0.40, reaction = 2, cast = 0.6,
                     dots = { { "Interface\\Icons\\Ability_Hunter_Quickshot", 0.70 },     -- Schlangenbiss
                              { "Interface\\Icons\\Ability_Hunter_SniperShot", 0.35 } } }, -- Mal des Jaegers
    targettarget = { name = "Heiler", class = "PRIEST", hp = 0.93, pp = 0.80 },
    focus        = { name = "Fokus-Gegner", hp = 0.45, pp = 0.25, reaction = 4, cast = 0.3 },
    party1       = { name = "Tank", class = "WARRIOR", hp = 0.74, pp = 0.35, power = "RAGE" },
    party2       = { name = "Magierin", class = "MAGE", hp = 0.55, pp = 0.90 },
    party3       = { name = "Jaegerin", class = "HUNTER", hp = 1.00, pp = 0.60, power = "FOCUS" },
    party4       = { name = "Schurke", class = "ROGUE", hp = 0.31, pp = 0.75, power = "ENERGY" },
}

local ORDER = { "player", "target", "targettarget", "focus", "party1", "party2", "party3", "party4" }
local PARTY_GAP = 4
-- Player-Frame nur im Kampf, mit Ziel oder bei Mouseover sichtbar.
-- Er wird nie wirklich versteckt, nur auf Alpha 0 gesetzt: so bleibt er per Maus
-- erreichbar (Mouseover blendet ein), und Alpha darf man auch im Kampf aendern.
local FADE_IN, FADE_OUT = 0.3, 1 -- Sekunden fuer 0 -> 1 bzw. 1 -> 0
local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function(self, elapsed)
    local f = self.frame
    local a = f:GetAlpha() + self.step * elapsed
    if (self.step > 0 and a >= self.to) or (self.step < 0 and a <= self.to) then
        f:SetAlpha(self.to)
        self:Hide()
    else
        f:SetAlpha(a)
    end
end)

local function FadeTo(f, to, duration)
    fader:Hide()
    local from = f:GetAlpha()
    if math.abs(from - to) < 0.01 or duration <= 0 then
        f:SetAlpha(to)
        return
    end
    fader.frame, fader.to = f, to
    fader.step = (to > from and 1 or -1) / duration
    fader:Show()
end

local function UpdatePlayerVisibility(f, inCombat, instant)
    if not f or unlocked or testMode then return end
    if inCombat or UnitExists("target") then
        FadeTo(f, 1, 0)
    elseif f.hover then
        FadeTo(f, 1, FADE_IN)
    else
        FadeTo(f, 0, instant and 0 or FADE_OUT)
    end
end

-- Normale Sichtbarkeit: Player per Alpha-Logik, alle anderen per Unit Watch
local function WatchVisibility(f, instant)
    if f.unit == "player" then
        if not InCombatLockdown() then f:Show() end
        UpdatePlayerVisibility(f, InCombatLockdown(), instant)
    else
        RegisterUnitWatch(f)
    end
end

local function ForceShow(f)
    if f.unit == "player" then
        fader:Hide(); f:SetAlpha(1)
    else
        UnregisterUnitWatch(f)
    end
    f:Show()
end
local LAYOUT = {
    player       = { w = 1.0, cast = true,  pos = { "CENTER", "CENTER", -260, -170 } },
    target       = { w = 1.0, cast = true,  pos = { "CENTER", "CENTER",  260, -170 } },
    targettarget = { w = 0.55, cast = false, pos = { "CENTER", "CENTER",  260, -225 } },
    -- (target bekommt zusaetzlich die My-DoT-Balken, siehe CreateDots)
    focus        = { w = 0.70, cast = true,  pos = { "CENTER", "CENTER", -260, -225 } },
    -- Gruppe: party1 traegt die Position, party2-4 haengen jeweils darunter
    party1       = { w = 0.80, cast = false, pos = { "TOPLEFT", "TOPLEFT", 40, -220 } },
    party2       = { w = 0.80, cast = false, below = "party1" },
    party3       = { w = 0.80, cast = false, below = "party2" },
    party4       = { w = 0.80, cast = false, below = "party3" },
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
-- Schriften (LibSharedMedia, falls ein anderes Addon es mitbringt)
------------------------------------------------------------------------
local BUILTIN_FONTS = {
    { "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" },
    { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\skurri.ttf" },
    { "Morpheus", "Fonts\\MORPHEUS.ttf" },
}

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function FontList()
    local list = { "Standard" }
    local lsm = LSM()
    if lsm then
        for _, n in ipairs(lsm:List("font")) do list[#list + 1] = n end
    else
        for _, e in ipairs(BUILTIN_FONTS) do list[#list + 1] = e[1] end
    end
    return list
end

local function FontPath(name)
    if not name or name == "Standard" then return STANDARD_TEXT_FONT end
    local lsm = LSM()
    local p = lsm and lsm:Fetch("font", name, true)
    if p then return p end
    for _, e in ipairs(BUILTIN_FONTS) do
        if e[1] == name then return e[2] end
    end
    return STANDARD_TEXT_FONT
end

local function ApplyFonts()
    local path = FontPath(DB.font)
    for _, f in pairs(frames) do
        f.hpText:SetFont(path, 11, "")
    end
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

local function TestHealthColor(unit, d)
    local class = d.class
    if unit == "player" then class = select(2, UnitClass("player")) end
    local c = DB.classColor and class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    if d.reaction and d.reaction <= 2 then return 0.8, 0.2, 0.2 end
    if d.reaction == 4 then return 0.95, 0.8, 0.2 end
    return 0.2, 0.8, 0.25
end

local function UpdateTest(f)
    local d = TEST[f.unit]
    f.hp:SetMinMaxValues(0, 1); f.hp:SetValue(d.hp)
    f.hp:SetStatusBarColor(TestHealthColor(f.unit, d))
    f.pp:SetMinMaxValues(0, 1); f.pp:SetValue(d.pp)
    local pc = d.power and PowerBarColor and PowerBarColor[d.power]
    if f.unit == "player" then
        f.pp:SetStatusBarColor(PowerColor("player"))
    elseif pc then
        f.pp:SetStatusBarColor(pc.r, pc.g, pc.b)
    else
        f.pp:SetStatusBarColor(0.3, 0.4, 0.9)
    end
    f.hpText:SetFormattedText("%d%%", d.hp * 100)
    if f.cast then
        if d.cast then
            f.cast:SetMinMaxValues(0, 1); f.cast:SetValue(d.cast); f.cast:Show()
        else
            f.cast:Hide()
        end
    end
    if f.dots then
        for i, bar in ipairs(f.dots) do
            local t = d.dots and d.dots[i]
            if t then
                bar.icon:SetTexture(t[1])
                bar:SetMinMaxValues(0, 1); bar:SetValue(t[2])
                bar:Show()
            else
                bar:Hide()
            end
        end
    end
end

------------------------------------------------------------------------
-- My-DoTs: eigene Debuffs auf dem Ziel als Balken (z.B. Schlangenbiss)
-- Die Aura-API ist im Kampf fuer Addons gesperrt ("Auras cannot be accessed
-- when secret while tainted"). Deshalb zeichnet Blizzards AuraContainer
-- (Blizzard_AuraContainer) die Balken: er liest die Auren selbst, wir geben
-- nur Icon-Textur und StatusBar vor. Gleicher Weg wie MSUF.
-- Die Fake-Balken in f.dots gibt es nur fuer den Testmodus.
------------------------------------------------------------------------
local MAX_DOTS, DOT_H, DOT_GAP = 4, 10, 2
local DOT_GROUP = "slimMyDots"
local dotStatus = "nicht gestartet"

local function DotBarOptions()
    local i, d = Enum.StatusBarInterpolation, Enum.StatusBarTimerDirection
    return { interpolation = i and i.Immediate, direction = d and d.RemainingTime }
end

-- Wird von Blizzard fuer jeden neuen Balken aufgerufen: Icon links, Balken rechts
local function StyleDotButtonRaw(button)
    -- Blizzards Rohlinge haben keine Groesse/Alpha: wie MSUF selbst setzen
    button:SetSize(DB.width * LAYOUT.target.w, DOT_H)
    button:SetAlpha(1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(DOT_H, DOT_H)
    icon:SetPoint("LEFT")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetAlpha(1)
    icon:Show()
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetStatusBarTexture(FLAT)
    bar:SetStatusBarColor(0.55, 0.85, 0.3)
    bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", DOT_GAP, 0)
    bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.65)
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    bar:Show()
    -- erst alles selbst einstellen, dann an Blizzard uebergeben
    button:SetIcon(icon)
    button:SetDurationBar(bar, DotBarOptions())
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
end

local styleCalls = 0
local function StyleDotButton(button)
    styleCalls = styleCalls + 1
    button.slimStyled = true
    local ok, err = pcall(StyleDotButtonRaw, button)
    if not ok then dotStatus = "Fehler beim Balken-Styling: " .. tostring(err) end
end

local function DotWidth(f)
    return DB.width * LAYOUT[f.unit].w
end

-- Breite folgt der Frame-Breite; Balken stapeln sich nach oben
local function LayoutNativeDots(f)
    local c = f.dotContainer
    if not c then return end
    local w = DotWidth(f)
    c:SetSize(w, DOT_H)
    c:SetAuraGroupLayout(DOT_GROUP, {
        elementWidth = w, elementHeight = DOT_H,
        elementSpacing = DOT_GAP, lineSpacing = DOT_GAP,
    })
    c:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
    local fd = AnchorUtil and AnchorUtil.FlowDirection
    c:SetFlowLayoutGrowthDirection(fd and fd.Right or 1, fd and fd.Up or 1)
    c:SetFlowLayoutMaximumLineSize(w)
end

local function CreateNativeDots(f)
    local addon = "Blizzard_AuraContainer"
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if isLoaded and not isLoaded(addon) and load then pcall(load, addon) end

    local ok, c = pcall(CreateFrame, "AuraContainer", nil, f, "CustomAuraContainerTemplate")
    if not ok or not c then
        dotStatus = "AuraContainer nicht verfuegbar: " .. tostring(c)
        return
    end
    local okSetup, err = pcall(function()
        c:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, DOT_GAP)
        c:SetUnit("target")
        if c.SetEditModePreviewEnabled then c:SetEditModePreviewEnabled(false) end
        c:SetEnabled(true)
        c:AddAuraGroup(DOT_GROUP, "HARMFUL|PLAYER", {
            maxFrameCount = MAX_DOTS,
            initializeFrame = StyleDotButton,
        })
        f.dotContainer = c
        LayoutNativeDots(f)
        c:Show()
    end)
    if okSetup then
        dotStatus = "aktiv (Blizzard AuraContainer)"
    else
        f.dotContainer = nil
        c:Hide()
        dotStatus = "Fehler beim Einrichten: " .. tostring(err)
    end
end

-- Blizzard soll den Container neu befuellen (Zielwechsel, neue Aura, Frame sichtbar)
local function RefreshNativeDots(f)
    local c = f.dotContainer
    if c and c.UpdateAllAuras then
        local ok, err = pcall(c.UpdateAllAuras, c)
        if not ok then dotStatus = "UpdateAllAuras Fehler: " .. tostring(err) end
    end
end

-- /slim dots
local function DebugDots()
    -- Ausgabe in den Chat und nach SlimFramesDB.dotLog (landet beim /reload in WTF\...\SavedVariables)
    DB.dotLog = { date("%Y-%m-%d %H:%M:%S") .. " Kampf=" .. tostring(InCombatLockdown()) }
    local function p(...)
        local parts = { ... }
        local okJ, line = pcall(function()
            for i = 1, #parts do parts[i] = tostring(parts[i]) end
            return table.concat(parts, " ")
        end)
        if not okJ or (issecretvalue and issecretvalue(line)) then line = "(secret, nicht speicherbar)" end
        table.insert(DB.dotLog, line)
        print("|cffffd200SlimFrames:|r", line)
    end
    p("My-DoTs: " .. dotStatus)
    local f = frames.target
    local c = f and f.dotContainer
    if not c then return end
    RefreshNativeDots(f)
    -- alles inkl. Ausgabe in pcall: secret values koennen schon beim Verketten/Drucken werfen
    local function try(label, fn)
        local ok, a, b = pcall(fn)
        local okP = pcall(function()
            p(label .. ": " .. (ok and (tostring(a) .. (b ~= nil and (" " .. tostring(b)) or "")) or ("Fehler " .. tostring(a))))
        end)
        if not okP then p(label .. ": (nicht druckbar, vermutlich secret)") end
    end
    p("Styling-Aufrufe durch Blizzard: " .. styleCalls)
    try("Ziel", function() return UnitExists("target") end)
    try("Container shown/visible", function() return c:IsShown(), c:IsVisible() end)
    try("Container Groesse", function()
        local w, h = c:GetSize()
        return string.format("%.0f x %.0f", w, h)
    end)
    try("Container Unit", function() return c.GetUnit and c:GetUnit() or "(kein GetUnit)" end)
    try("Container Alpha", function() return c:GetEffectiveAlpha() end)
    try("Balken-Anzahl", function()
        return c.GetAuraGroupFrameCount and c:GetAuraGroupFrameCount(DOT_GROUP) or "(kein GetAuraGroupFrameCount)"
    end)
    for i = 1, MAX_DOTS do
        try("Balken " .. i, function()
            local b = c.GetAuraGroupFrame and c:GetAuraGroupFrame(DOT_GROUP, i)
            if not b then return "nil" end
            local s = "styled=" .. tostring(b.slimStyled == true)
                .. " shown=" .. tostring(b:IsShown()) .. " visible=" .. tostring(b:IsVisible())
            local okS, size = pcall(function()
                local w, h = b:GetSize()
                return string.format("%.0fx%.0f", w, h)
            end)
            return s, "size=" .. (okS and size or "?") .. " punkte=" .. tostring(b:GetNumPoints())
        end)
    end
end

-- Testmodus-Balken (eigene Frames mit Beispielwerten), gleiche Position wie die echten
local function CreateTestDots(f)
    f.dots = {}
    for i = 1, MAX_DOTS do
        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetStatusBarTexture(FLAT)
        bar:SetStatusBarColor(0.55, 0.85, 0.3)
        bar:SetHeight(DOT_H)
        local y = DOT_GAP + (i - 1) * (DOT_H + DOT_GAP)
        bar:SetPoint("BOTTOMLEFT", f, "TOPLEFT", DOT_H + DOT_GAP, y)
        bar:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, y)
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints(); bar.bg:SetColorTexture(0, 0, 0, 0.65)
        bar.icon = bar:CreateTexture(nil, "ARTWORK")
        bar.icon:SetSize(DOT_H, DOT_H)
        bar.icon:SetPoint("RIGHT", bar, "LEFT", -DOT_GAP, 0)
        bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bar:Hide()
        f.dots[i] = bar
    end
end

local function CreateDots(f)
    CreateTestDots(f)
    CreateNativeDots(f)
end

local function Update(f, event)
    if testMode then UpdateTest(f) return end
    local u = f.unit
    if not UnitExists(u) then
        f.hpText:SetText("")
        f.hp:SetMinMaxValues(0, 1); f.hp:SetValue(0)
        f.pp:SetMinMaxValues(0, 1); f.pp:SetValue(0)
        if f.cast then f.cast:Hide() end
        if f.dots then for _, bar in ipairs(f.dots) do bar:Hide() end end
        return
    end

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
    -- echte DoTs zeichnet der AuraContainer; Testbalken weg
    if f.dots then for _, bar in ipairs(f.dots) do bar:Hide() end end
    if f.dotContainer and (event == nil or event == "PLAYER_TARGET_CHANGED" or event == "UNIT_AURA") then
        RefreshNativeDots(f)
    end
end

------------------------------------------------------------------------
-- Frames bauen
------------------------------------------------------------------------
local function ApplyLayout(f)
    local cfg = LAYOUT[f.unit]
    f:SetScale(DB.scale)
    f:SetSize(DB.width * cfg.w, HP_H + PP_H + 3)
    f:ClearAllPoints()
    if cfg.below then
        f:SetPoint("TOPLEFT", frames[cfg.below], "BOTTOMLEFT", 0, -PARTY_GAP)
        return
    end
    local p = DB.pos and DB.pos[f.unit] or cfg.pos
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    if f.dotContainer then pcall(LayoutNativeDots, f) end
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

    -- Kein Namenstext (dafuer Tooltip); HP-Text ohne Outline, nur mit Schatten
    f.hpText = f.hp:CreateFontString(nil, "OVERLAY")
    f.hpText:SetFont(FontPath(DB.font), 11, "")
    f.hpText:SetShadowColor(0, 0, 0, 1)
    f.hpText:SetShadowOffset(1, -1)
    f.hpText:SetPoint("RIGHT", -4, 0)
    if cfg.w < 0.6 then f.hpText:Hide() end

    -- Tooltip beim Drueberfahren (im Testmodus mit den Beispielnamen)
    f:SetScript("OnEnter", function(self)
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        if testMode then
            local d = TEST[self.unit]
            GameTooltip:SetText(self.unit == "player" and UnitName("player") or d.name)
            GameTooltip:AddLine("Testdaten", 0.6, 0.6, 0.6)
        elseif UnitExists(self.unit) then
            GameTooltip:SetUnit(self.unit)
        else
            return
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if unit == "player" then
        f:HookScript("OnEnter", function(self)
            self.hover = true
            UpdatePlayerVisibility(self, InCombatLockdown())
        end)
        f:HookScript("OnLeave", function(self)
            self.hover = false
            UpdatePlayerVisibility(self, InCombatLockdown())
        end)
    end

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
    if unit:find("^party") then
        reg("UNIT_CONNECTION", unit)
        f:RegisterEvent("GROUP_ROSTER_UPDATE")
    end
    if cfg.cast then
        for _, ev in ipairs(CAST_EVENTS) do reg(ev, unit) end
    end
    if unit == "target" then
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        CreateDots(f)
        reg("UNIT_AURA", unit)
    end
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
    f.mover.label = f.mover:CreateFontString(nil, "OVERLAY")
    f.mover.label:SetFont(FONT, 11, "")
    f.mover.label:SetShadowOffset(1, -1)
    f.mover.label:SetPoint("CENTER")
    f.mover.label:SetText(unit)
    -- Gruppenframes werden als Block bewegt: jeder Mover zieht party1
    local function root()
        return unit:find("^party") and frames.party1 or f
    end
    f.mover:SetScript("OnDragStart", function() if not InCombatLockdown() then root():StartMoving() end end)
    f.mover:SetScript("OnDragStop", function()
        local r = root()
        r:StopMovingOrSizing()
        local p, _, rp, x, y = r:GetPoint()
        DB.pos = DB.pos or {}
        DB.pos[r.unit] = { p, rp, x, y }
    end)
    f.mover:Hide()

    WatchVisibility(f, true)
    frames[unit] = f
    return f
end

-- Frames dauerhaft zeigen, solange verschoben oder getestet wird; sonst wieder per Unit Watch
local function ApplyVisibility()
    local forceShow = unlocked or testMode
    for _, unit in ipairs(ORDER) do
        local f = frames[unit]
        if f then
            f.mover:SetShown(unlocked)
            if forceShow then ForceShow(f) else WatchVisibility(f) end
            -- Testmodus zeigt Fake-DoTs, sonst der echte AuraContainer
            if f.dotContainer then f.dotContainer:SetShown(not testMode) end
            Update(f)
        end
    end
end

local function NotInCombat()
    if InCombatLockdown() then
        print("|cffffd200SlimFrames:|r Nicht im Kampf.")
        return false
    end
    return true
end

local function SetUnlocked(flag)
    if not NotInCombat() then return false end
    unlocked = flag
    ApplyVisibility()
    return true
end

local function SetTestMode(flag)
    if not NotInCombat() then return false end
    testMode = flag
    ApplyVisibility()
    return true
end

------------------------------------------------------------------------
-- Blizzard-Frames loswerden
------------------------------------------------------------------------
local hider = CreateFrame("Frame")
hider:Hide()

local function HideBlizzard()
    if InCombatLockdown() then return end
    for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PartyFrame", "CompactPartyFrame" }) do
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

-- Schriftauswahl: Knopf + Liste rechts neben dem Panel, jeder Eintrag in seiner eigenen Schrift
local function MakeFontPicker(parent, y)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 12, "")
    label:SetPoint("TOPLEFT", 14, y)
    label:SetText("Schrift")

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(192, 20)
    btn:SetPoint("TOPLEFT", 14, y - 18)
    local bbg = btn:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints(); bbg:SetColorTexture(0.15, 0.15, 0.15, 1)
    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetPoint("LEFT", 6, 0); btn.text:SetPoint("RIGHT", -18, 0)
    btn.text:SetJustifyH("LEFT"); btn.text:SetWordWrap(false)
    local arrow = btn:CreateFontString(nil, "OVERLAY")
    arrow:SetFont(FONT, 12, ""); arrow:SetPoint("RIGHT", -6, 0); arrow:SetText("v")

    local function refresh()
        local n = DB.font or "Standard"
        btn.text:SetFont(FontPath(n), 12, "")
        btn.text:SetText(n)
    end

    local ROWS, ROW_H = 16, 20
    local list = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    list:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
    list:SetWidth(200)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    list:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    list:SetBackdropBorderColor(0, 0, 0, 1)
    list:EnableMouseWheel(true)
    list:Hide()

    local names, offset, rows = {}, 0, {}
    local function render()
        local current = DB.font or "Standard"
        for i = 1, ROWS do
            local r, n = rows[i], names[i + offset]
            if n then
                r.name = n
                r.text:SetFont(FontPath(n), 12, "")
                r.text:SetText(n)
                r.sel:SetShown(n == current)
                r:Show()
            else
                r:Hide()
            end
        end
    end

    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetSize(192, ROW_H)
        r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
        r.sel = r:CreateTexture(nil, "BACKGROUND")
        r.sel:SetAllPoints(); r.sel:SetColorTexture(0.2, 0.5, 1, 0.35)
        r:SetHighlightTexture(FLAT)
        r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.1)
        r.text = r:CreateFontString(nil, "OVERLAY")
        r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -6, 0)
        r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r:SetScript("OnClick", function()
            DB.font = (r.name ~= "Standard") and r.name or nil
            ApplyFonts()
            refresh()
            list:Hide()
        end)
        rows[i] = r
    end

    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(#names - ROWS, offset - delta))
        render()
    end)
    btn:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() return end
        names, offset = FontList(), 0
        list:SetHeight(math.min(#names, ROWS) * ROW_H + 8)
        render()
        list:Show()
    end)

    refresh()
    return btn
end

local function BuildPanel()
    panel = CreateFrame("Frame", "SlimFramesConfig", UIParent, "BackdropTemplate")
    panel:SetSize(230, 276)
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

    panel.checks = {
        MakeCheck(panel, "Frames verschieben", -34,
            function() return unlocked end,
            function(v) SetUnlocked(v) end),
        MakeCheck(panel, "Testmodus (Beispieldaten)", -58,
            function() return testMode end,
            function(v) SetTestMode(v) end),
        MakeCheck(panel, "Klassenfarben", -82,
            function() return DB.classColor end,
            function(v) DB.classColor = v; for _, f in pairs(frames) do Update(f) end end),
    }
    MakeSlider(panel, "Groesse", -108, 0.6, 1.6, 0.05,
        function() return DB.scale end,
        function(v) DB.scale = v; ApplyAll() end)
    MakeSlider(panel, "Breite", -146, 140, 320, 10,
        function() return DB.width end,
        function(v) DB.width = v; ApplyAll() end)
    MakeFontPicker(panel, -186)

    local reset = CreateFrame("Button", nil, panel)
    reset:SetSize(100, 20); reset:SetPoint("BOTTOMLEFT", 14, 10)
    local rbg = reset:CreateTexture(nil, "BACKGROUND")
    rbg:SetAllPoints(); rbg:SetColorTexture(0.2, 0.2, 0.2, 1)
    local rfs = reset:CreateFontString(nil, "OVERLAY")
    rfs:SetFont(FONT, 12, ""); rfs:SetPoint("CENTER"); rfs:SetText("Positionen reset")
    reset:SetScript("OnClick", function() DB.pos = {}; ApplyAll() end)

    panel.Refresh = function() for _, c in ipairs(panel.checks) do c.Refresh() end end
    panel:SetScript("OnHide", function()
        if (unlocked or testMode) and not InCombatLockdown() then
            unlocked, testMode = false, false
            ApplyVisibility()
        end
        panel.Refresh()
    end)
    panel:Hide()
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
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
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Kampf beginnt: im Handler ist noch kein Lockdown aktiv, also echte Anzeige wiederherstellen
        if unlocked or testMode then
            unlocked, testMode = false, false
            ApplyVisibility()
            if panel then panel.Refresh() end
            print("|cffffd200SlimFrames:|r Kampf - Test-/Verschiebemodus beendet.")
        end
        UpdatePlayerVisibility(frames.player, true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingApply then ApplyAll() end
        HideBlizzard()
        UpdatePlayerVisibility(frames.player, false)
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdatePlayerVisibility(frames.player, InCombatLockdown())
    end
end)

SLASH_SLIMFRAMES1 = "/slim"
SLASH_SLIMFRAMES2 = "/slimframes"
SlashCmdList["SLIMFRAMES"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "reset" then
        DB.pos = {}; ApplyAll()
    elseif msg == "dots" then
        DebugDots()
    elseif msg == "test" then
        SetTestMode(not testMode)
        if panel then panel.Refresh() end
    elseif panel then
        panel:SetShown(not panel:IsShown())
    end
end
