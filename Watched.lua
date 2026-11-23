-- Watched auras. AurasDB.watched lists your buffs (unit "player")
-- and your target's debuffs (unit "target") by name, and by spell ID where known:
-- { name, spellID, unit, group, icon, topRight, inRow, mine, cooldown, grey, glow, warn, size, bar,
-- x, y, texture }. Each shows as its
-- own icon with the time left (icon), and only when asked also at the top right
-- (topRight) and in the row under its frame (inRow). Only mine shows the one you
-- cast. A buff of yours that ends shows its spell's own cooldown, greyed (cooldown).
-- With grey, an aura that is not up stays on screen as a greyed icon (consumables).
-- The icon's spot is saved here (x, y from the screen's centre), not left to the
-- client's layout cache, which drops a frame that was not created in a session
-- (a group that is off where you were). texture: the picture seen last.
-- glow: a colour key (A.COLORS) while the aura is up; warn: seconds left under which
-- the icon pulses; size: the icon's side (default 36); bar: a bar of the time left.
-- The top right and the rows are UnitFrames': it asks Auras.Hidden. An entry
-- whose group does not show where you are is left alone, as if it were not listed.
local _, A = ...
local db = AurasDB

local SIZE, GAP = 36, 6
local FILTER = { player = "HELPFUL", target = "HARMFUL" }
local icons = {}               -- frame name -> icon, kept when an entry goes
local iconOf = {}              -- entry -> its icon
local slots, found = {}, {}
local hidden = { top = {}, player = {}, target = {} }
local watching = {}            -- unit -> a watched entry is on it
local byName = { player = {}, target = {} } -- unit -> aura name -> entry
local byID = { player = {}, target = {} }   -- unit -> spell ID -> entry
local spells = {}              -- name -> { slot, book } of your spell with a cooldown, or false
local place = "none"           -- GetInstanceInfo's instanceType, read at each loading screen

function A.GroupNamed(name)
    for _, group in ipairs(db.groups) do if group.name == name then return group end end
end
-- An entry's group; one with none (or a deleted one) joins the first.
function A.Group(entry)
    local group = A.GroupNamed(entry.group)
    if not group then group = db.groups[1]; entry.group = group.name end
    return group
end
function A.Active(group) return group.where == "all" or group.where == place end

-- For UnitFrames' rows and top right: whether an aura shows here instead.
-- place "top" is the top right, else the unit's row; source is the caster's token.
function A.Hidden(name, unit, place, source)
    local rule = name and (place == "top" and hidden.top or hidden[unit])[name]
    if rule == "mine" then return source ~= nil and UnitIsUnit(source, "player") and true or false end
    return rule or false
end

-- The spell's icon (a name-only entry: your own spell of that name).
function A.SpellIcon(entry)
    if entry.texture then return entry.texture end
    local _, _, texture = GetSpellInfo(entry.spellID or entry.name)
    return texture or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Your spell of that name: its book slot, for its cooldown; false for a spell
-- with none of its own (Slice and Dice), so a cast reads nothing for it.
local function Spell(name)
    local known = spells[name]
    if known == nil then
        local id = select(10, GetSpellInfo(name))
        local base = id and GetSpellBaseCooldown(id)
        local slot, book
        if base and base > 0 then slot, book = FindSpellBookSlotByID(id) end
        known = slot and { slot, book } or false
        spells[name] = known
    end
    return known
end

-- For the list: whether a buff's CD switch can show anything.
function A.HasCooldown(name) return Spell(name) and true or false end

-- Where the icon sits now, kept in its entry.
local function Save(icon)
    local x, y = icon:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if x and ux then icon.entry.x, icon.entry.y = math.floor(x - ux + 0.5), math.floor(y - uy + 0.5) end
end

-- The icon's side, and what follows it: the text, the glow and the bar.
local function Layout(icon, size)
    if icon.size == size then return end
    icon.size = size
    icon:SetWidth(size); icon:SetHeight(size)
    local font = math.max(10, math.floor(size * 0.4))
    icon.cd:GetCountdownFontString():SetFont(STANDARD_TEXT_FONT, font, "OUTLINE")
    icon.count:SetFont(STANDARD_TEXT_FONT, font, "OUTLINE")
    if icon.glow then icon.glow:SetWidth(size * 1.75); icon.glow:SetHeight(size * 1.75) end
    if icon.bar then icon.bar:SetHeight(math.max(8, size * 0.3)) end
end

-- The glow while the aura is up: the game's own button border, tinted, pulsing.
local function Glow(icon, on)
    local color = on and A.Color(icon.entry.glow)
    if not color then
        if icon.lit then icon.lit = nil; icon.glow:Hide(); icon.glowPulse:Stop() end
        return
    end
    if not icon.glow then
        local g = icon:CreateTexture(nil, "OVERLAY")
        g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        g:SetBlendMode("ADD")
        g:SetPoint("CENTER", icon, "CENTER", 0, 0)
        g:SetWidth(icon.size * 1.75); g:SetHeight(icon.size * 1.75)
        icon.glow = g
        icon.glowPulse = g:CreateAnimationGroup()
        icon.glowPulse:SetLooping("BOUNCE")
        local a = icon.glowPulse:CreateAnimation("Alpha")
        a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.7)
    end
    if icon.lit == color then return end
    icon.lit = color
    icon.glow:SetVertexColor(color[3], color[4], color[5])
    icon.glow:Show()
    icon.glowPulse:Play()
end

-- The warning: the whole icon pulses.
local function Pulse(icon, on)
    if icon.pulsing == on then return end
    icon.pulsing = on
    if on then
        if not icon.pulse then
            icon.pulse = icon:CreateAnimationGroup()
            icon.pulse:SetLooping("BOUNCE")
            local a = icon.pulse:CreateAnimation("Alpha")
            a:SetFromAlpha(1); a:SetToAlpha(0.3); a:SetDuration(0.35)
        end
        icon.pulse:Play()
    elseif icon.pulse then
        icon.pulse:Stop()
    end
end

-- The bar of the time left beside the icon; the client empties it by itself.
local function Bar(icon)
    local entry = icon.entry
    if not (entry.bar and icon.up and icon.start) then
        if icon.barOn then icon.barOn = nil; icon.bar:Hide() end
        return
    end
    if not icon.bar then
        local bar = CreateFrame("StatusBar", nil, icon)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        bar:SetWidth(100); bar:SetHeight(math.max(8, icon.size * 0.3))
        local back = bar:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(bar)
        back:SetTexture("Interface\\Buttons\\WHITE8X8")
        back:SetVertexColor(0, 0, 0, 0.6)
        icon.bar, icon.span = bar, C_DurationUtil.CreateDuration()
        bar:SetTimerDuration(icon.span, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
    end
    local color = A.Color(entry.glow) or A.COLORS[1]
    if icon.barColor ~= color then icon.barColor = color; icon.bar:SetStatusBarColor(color[3], color[4], color[5]) end
    if icon.barStart ~= icon.start or icon.barLength ~= icon.duration then
        icon.barStart, icon.barLength = icon.start, icon.duration
        icon.span:SetTimeFromStart(icon.start, icon.duration)
    end
    if not icon.barOn then icon.barOn = true; icon.bar:Show() end
end

-- The aura is up: glow, bar, and the warning at `warn` seconds left (a timer for
-- the moment it comes, set again only when the aura's end changes).
local function Alive(icon, duration, expires)
    local warn = icon.entry.warn
    Glow(icon, true)
    Bar(icon)
    if not (warn and duration and duration > 0 and expires) then
        if icon.warnTimer then icon.warnTimer:Cancel(); icon.warnTimer = nil end
        icon.warnFor = nil
        Pulse(icon, false)
        return
    end
    if icon.warnFor == expires then return end
    icon.warnFor = expires
    if icon.warnTimer then icon.warnTimer:Cancel(); icon.warnTimer = nil end
    local left = expires - GetTime()
    Pulse(icon, left <= warn)
    if left > warn then
        icon.warnTimer = C_Timer.NewTimer(left - warn, function()
            icon.warnTimer = nil
            if icon.up then Pulse(icon, true) end
        end)
    end
end

-- The aura is not up: no glow, bar or warning.
local function Calm(icon)
    if icon.warnTimer then icon.warnTimer:Cancel(); icon.warnTimer = nil end
    icon.warnFor = nil
    Pulse(icon, false)
    Glow(icon, false)
    Bar(icon)
end

local function Icon(entry, index)
    local name = "AurasWatch_" .. entry.unit .. "_" .. string.gsub(entry.name, "[^%w]", "")
    local icon = icons[name]
    if not icon then
        icon = CreateFrame("Frame", name, UIParent)
        icon:SetFrameLevel(10)
        A.Icon(icon, SIZE, 14)
        icon.cd:SetScript("OnCooldownDone", function() if icon.cooling then A.WatchMissing("player") end end)
        icon.handle = A.Movable(icon, entry.name, function()
            if not iconOf[icon.entry] then icon:Hide() end -- a group that is off here: shown only to be moved
            A.Watch(icon.entry.unit)
        end, Save)
        icon:Hide()
        icons[name] = icon
    end
    icon.entry, icon.handle.off = entry, nil
    Layout(icon, entry.size or SIZE)
    -- Its saved spot; a spot the client kept (moved before this was saved here) is
    -- taken over; until the player moves it, above the screen's centre, eight to a row.
    if not entry.x and icon:IsUserPlaced() then Save(icon) end
    if entry.x then
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", UIParent, "CENTER", entry.x, entry.y)
    elseif not icon:IsUserPlaced() then
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", UIParent, "CENTER", ((index - 1) % 8 - 3.5) * (SIZE + GAP),
            150 + math.floor((index - 1) / 8) * (SIZE + GAP))
    end -- else the client puts it back a moment later (layout-cache.txt)
    return icon
end

local function Show(icon, texture, count, duration, expires)
    if icon.cooling then
        icon.cooling = nil
        icon.icon.greyed = nil
        icon.icon:SetDesaturated(false)
        icon.cd:SetReverse(true)
    end
    icon.up = true
    A.Texture(icon.icon, texture)
    A.Stacks(icon, count)
    A.Timing(icon, duration, expires)
    icon:Show()
    Alive(icon, duration, expires)
end

-- The picture of an icon that is not up, greyed. The client drops the grey when a
-- texture is set, so it is set first and the grey written after, whenever either
-- is new (a grey written before the texture was lost whenever the picture changed).
local function Greyed(icon, texture)
    local tex = icon.icon
    if tex.path ~= texture or not tex.greyed then
        A.Texture(tex, texture)
        tex.greyed = true
        tex:SetDesaturated(true)
    end
end

-- One of your buffs has ended: its spell's own cooldown, greyed with a filling
-- sweep, until it is ready. A cooldown of 1.5 s or less is the global one (a
-- rogue's 1 s too); C_Spell.GetSpellCooldown's isOnGCD would say so, but in a new
-- table at every read.
local function ShowCooldown(icon, entry)
    if entry.unit ~= "player" or not entry.cooldown then return false end
    local spell = Spell(entry.name)
    if not spell then return false end
    local start, duration = GetSpellCooldown(spell[1], spell[2])
    if not start or duration <= 1.5 or start + duration <= GetTime() then return false end
    if not icon.cooling then
        icon.cooling = true
        icon.cd:SetReverse(false)
        A.Stacks(icon, nil)
    end
    Greyed(icon, A.SpellIcon(entry))
    A.Timing(icon, duration, start + duration)
    icon:Show()
    return true
end

-- An aura that is not up, kept as a greyed icon (grey).
local function ShowGrey(icon, entry)
    if not entry.grey then return false end
    if not icon.cooling then
        icon.cooling = true
        icon.cd:SetReverse(false)
    end
    Greyed(icon, A.SpellIcon(entry))
    A.Stacks(icon, nil)
    A.Timing(icon, nil, nil)
    icon:Show()
    return true
end

-- The entries of `unit` whose aura is not up: a cooldown, greyed, or hidden.
function A.WatchMissing(unit)
    for entry, icon in pairs(iconOf) do
        if entry.unit == unit and not icon.up then
            Calm(icon)
            if not ShowCooldown(icon, entry) and not ShowGrey(icon, entry) and not icon.handle.revealed then
                if icon.cooling then
                    icon.cooling = nil; icon.icon.greyed = nil
                    icon.icon:SetDesaturated(false); icon.cd:SetReverse(true)
                end
                icon:Hide()
            end
        end
    end
end

-- The first aura that matches an entry (Only mine: one you cast) shows on its icon.
local function Found(entry, texture, count, duration, expires, source)
    if not entry or found[entry] or entry.mine and not (source and UnitIsUnit(source, "player")) then return end
    found[entry] = true
    entry.texture = texture
    if iconOf[entry] then Show(iconOf[entry], texture, count, duration, expires) end
end

-- Reads the unit's auras of its kind once; each finds its entry by name and by
-- spell ID (the name keeps a higher rank matching).
function A.Watch(unit)
    if not watching[unit] then return end
    for _, icon in pairs(iconOf) do if icon.entry.unit == unit then icon.up = nil end end
    table.wipe(found)
    if UnitExists(unit) then
        local names, ids = byName[unit], byID[unit]
        local _, n = C_UnitAuras.GetAuraSlots(unit, FILTER[unit], nil, nil, slots)
        for i = 1, n do
            local name, texture, count, _, duration, expires, source, _, _, spellID =
                C_UnitAuras.UnitAuraBySlot(unit, slots[i])
            Found(name and names[name], texture, count, duration, expires, source)
            Found(spellID and ids[spellID], texture, count, duration, expires, source)
        end
    end
    A.WatchMissing(unit)
end

-- After a change to the list: icons for the entries that want one; UnitFrames
-- redraws its rows and top right, which leave out what shows here.
function A.Rebuild()
    for _, set in pairs(hidden) do table.wipe(set) end
    for _, set in pairs(byName) do table.wipe(set) end
    for _, set in pairs(byID) do table.wipe(set) end
    table.wipe(iconOf)
    watching.player, watching.target = nil, nil
    for _, icon in pairs(icons) do
        icon.handle.off = true; icon.up = nil; Calm(icon); icon:Hide(); icon.handle:Hide()
    end
    local index = 0
    for _, entry in ipairs(db.watched) do
        if not A.Active(A.Group(entry)) then
            if entry.icon then Icon(entry, 0) end -- built so Place icons can move it; never watched
        else
            if entry.icon then
                index = index + 1
                iconOf[entry] = Icon(entry, index)
            end
            watching[entry.unit] = true
            byName[entry.unit][entry.name] = entry
            if entry.spellID then byID[entry.unit][entry.spellID] = entry end
            if entry.unit == "player" and not entry.topRight then hidden.top[entry.name] = true end
            if not entry.inRow then hidden[entry.unit][entry.name] = entry.mine and "mine" or true end
        end
    end
    A.Watch("player")
    A.Watch("target")
    if UnitFrames then UnitFrames.Refresh() end -- vanillaforge-ignore: K1
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterUnitEvent("UNIT_AURA_DELTA", "player", "target") -- not the target's raid or plate copies
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("SPELLS_CHANGED")
events:SetScript("OnEvent", function(_, e, unit)
    if e == "UNIT_AURA_DELTA" then A.Watch(unit)
    elseif e == "PLAYER_TARGET_CHANGED" then A.Watch("target")
    elseif e == "PLAYER_ENTERING_WORLD" then
        local _, kind = GetInstanceInfo()
        if kind ~= place then place = kind; A.Rebuild() else A.Watch("player"); A.Watch("target") end
    elseif e == "SPELLS_CHANGED" then table.wipe(spells)
    else A.WatchMissing("player") end
end)

-- The one public function: UnitFrames asks it (narrow, read-only).
Auras = { Hidden = A.Hidden }
