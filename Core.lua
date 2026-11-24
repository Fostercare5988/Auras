-- Auras: watched auras, a light WeakAuras. Your chosen buffs and your target's
-- debuffs, each its own icon with the time left. Doc headings are ClassicAPI's
-- docs/API.md.
if not CLASSIC_API_VERSION then error("Auras needs ClassicAPI.", 0) end

local _, A = ...
AurasDB = AurasDB or {} -- restored first: LoadSavedVariablesFirst
AurasDB.watched = AurasDB.watched or {}
if AurasDB.lossOfControl == nil then AurasDB.lossOfControl = true end
-- The groups, in list order: { name, where } (where: "all", "off", or the
-- instanceType of GetInstanceInfo it shows in). Each entry names its group.
AurasDB.groups = AurasDB.groups or { { name = "General", where = "all" } }

-- The countdown look (UnitFrames' too): red tenths under 5 s, yellow under
-- 10 s, then s/m/h/d. The client counts down (the Cooldown section).
local Up = Enum.NumericRuleFormatRounding.Up
local countdown = C_StringUtil.CreateNumericRuleFormatter()
countdown:SetBreakpoints({
    { threshold = 0, step = 0.1, rounding = Up, format = "|cffff4444%.1f|r" },
    { threshold = 5, step = 1, rounding = Up, format = "|cffffff33%d|r" },
    { threshold = 10, step = 1, rounding = Up, format = "|cffffffff%d|r" },
    { threshold = 60, format = "|cffffffff%dm|r", components = { { div = 60, step = 1, rounding = Up } } },
    { threshold = 3600, format = "|cffffffff%dh|r", components = { { div = 3600, step = 1, rounding = Up } } },
    { threshold = 86400, format = "|cffffffff%dd|r", components = { { div = 86400, step = 1, rounding = Up } } },
})

-- Glow and bar colours for the watched icons, in menu order: key, label, r, g, b.
A.COLORS = {
    { "gold", "Gold", 1, 0.82, 0.1 }, { "red", "Red", 1, 0.25, 0.25 }, { "green", "Green", 0.3, 1, 0.3 },
    { "blue", "Blue", 0.35, 0.65, 1 }, { "white", "White", 1, 1, 1 }, { "purple", "Purple", 0.8, 0.45, 1 },
}
function A.Color(key)
    for _, c in ipairs(A.COLORS) do if c[1] == key then return c end end
end

-- An icon on `b`: its picture, a native Cooldown with the countdown, and the
-- stacks above them.
function A.Icon(b, size, textSize)
    b:SetWidth(size); b:SetHeight(size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b)
    b.cd:SetReverse(true)
    b.cd:SetDrawBling(false)
    b.cd:SetCountdownFormatter(countdown)
    b.cd:GetCountdownFontString():SetFont(STANDARD_TEXT_FONT, textSize, "OUTLINE")
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints(b)
    over:SetFrameLevel(b:GetFrameLevel() + 5)
    b.count = over:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(STANDARD_TEXT_FONT, textSize, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
end

-- A font string's text and a texture's path, written only when they change.
function A.Text(fs, text)
    if fs.written ~= text then fs.written = text; fs:SetText(text) end
end
function A.Texture(tex, path)
    if tex.path ~= path then tex.path = path; tex:SetTexture(path) end
end
function A.Stacks(b, stacks) A.Text(b.count, stacks and stacks > 1 and stacks or "") end

-- The sweep of an aura (or a cooldown) ending at `expires`; restarted only when
-- its timing changes.
function A.Timing(b, duration, expires)
    local start = duration and duration > 0 and expires and expires > GetTime() and expires - duration or nil
    if b.start == start and b.duration == duration then return end
    b.start, b.duration = start, duration
    if start then b.cd:SetCooldown(start, duration) else b.cd:Clear() end
end

-- Ctrl+Shift shows a handle over each icon, the hidden ones too; dragging it moves
-- the icon (the client saves a named frame the player moved, layout-cache.txt).
-- `reveal` puts back an icon that was shown only to be moved.
local handles, held = {}, false
local keys = CreateFrame("Frame")
keys:RegisterEvent("MODIFIER_STATE_CHANGED")
keys:SetScript("OnEvent", function()
    -- The left and right reads: the merged state lags this event (ClassicAPI fires
    -- it from the key message, before the client's own state catches up).
    A.Place((IsLeftShiftKeyDown() or IsRightShiftKeyDown())
        and (IsLeftControlKeyDown() or IsRightControlKeyDown()) and true or false)
end)

-- Placing on or off: the handles over every icon, the ones of groups that are off
-- here too. Ctrl+Shift holds it; the list's Place icons button toggles it.
function A.Place(now)
    if now == nil then now = not held end
    if now == held then return end
    held = now
    if held then A.BuildAlert() end -- the loss-of-control alert, to place it
    for _, h in ipairs(handles) do
        if not h.off then
            if held then
                if not h.frame:IsShown() then h.revealed = true; h.frame:Show() end
                h:Show()
            else
                h:GetScript("OnMouseUp")() -- the keys let go while dragging
                h:Hide()
                if h.revealed then h.revealed = nil; h.reveal(h.frame) end
            end
        end
    end
end

-- `moved(frame)`, when given, runs when a drag ends (the icons save their spot).
function A.Movable(frame, label, reveal, moved)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    local h = CreateFrame("Frame", nil, frame)
    h:SetAllPoints(frame)
    h:SetFrameStrata("DIALOG")
    h:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    h:SetBackdropColor(0.2, 0.6, 1, 0.45)
    h:EnableMouse(true)
    h.label = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.label:SetPoint("CENTER", h, "CENTER", 0, 0)
    h.label:SetText(label)
    h.frame, h.reveal = frame, reveal
    h:SetScript("OnMouseDown", function() h.moving = true; frame:StartMoving() end)
    h:SetScript("OnMouseUp", function()
        if not h.moving then return end
        h.moving = nil
        frame:StopMovingOrSizing()
        if moved then moved(frame) end
    end)
    h:Hide()
    handles[#handles + 1] = h
    return h
end
