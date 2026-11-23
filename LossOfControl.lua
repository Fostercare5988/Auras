-- The loss-of-control alert, like the modern client's: while you are stunned,
-- feared, silenced, disarmed or school-locked, one alert shows the icon, the text
-- and the time left of the effect with the highest priority, and hides when the
-- last one ends. C_LossOfControl is ClassicAPI's (the LossOfControl section);
-- displayType 0 (a root) is not shown. LOSS_OF_CONTROL_UPDATE fires once per frame
-- for every added, changed or ended effect (the events section), so it is the
-- only event listened to. The sweep and the countdown numbers are the Cooldown's.
-- The frame is made at the first effect (or the first Ctrl+Shift, to place it).
local _, A = ...
local db = AurasDB

-- UNVERIFIED: the art of the Kick icon; a school lockout has no icon of its own
-- ("" in iconTexture). Check: /run print(GetSpellInfo(1766))
local SCHOOL_ICON = "Interface\\Icons\\Ability_Kick"
local PLACEHOLDER = "Interface\\Icons\\INV_Misc_QuestionMark"
local alert
local events = CreateFrame("Frame")

local function Refresh()
    -- The highest priority wins; the same priority: the later end. One table per
    -- effect comes from the call (a few, once per change), none are kept.
    local priority, ends, kind, text, texture, school, start, duration = -1, -1
    for i = 1, C_LossOfControl.GetActiveLossOfControlDataCount() do
        local d = C_LossOfControl.GetActiveLossOfControlData(i)
        if d and d.displayType > 0 then
            local over = d.startTime and d.duration and d.startTime + d.duration or 0
            if d.priority > priority or d.priority == priority and over > ends then
                priority, ends, kind, text, texture, school, start, duration =
                    d.priority, over, d.locType, d.displayText, d.iconTexture, d.lockoutSchool, d.startTime, d.duration
            end
        end
    end
    if priority < 0 then
        if alert and not alert.handle.revealed then alert:Hide(); A.Timing(alert) end
        return
    end
    if not alert then A.BuildAlert() end
    if kind == "SCHOOL_INTERRUPT" then
        text = string.format(LOSS_OF_CONTROL_DISPLAY_INTERRUPT_SCHOOL, C_Spell.GetSchoolString(school))
    end
    A.Texture(alert.icon, texture and texture ~= "" and texture or SCHOOL_ICON)
    A.Text(alert.label, text)
    A.Timing(alert, duration, start and duration and start + duration)
    alert:Show()
end

-- Made once, and not before it is wanted.
function A.BuildAlert()
    if alert or not db.lossOfControl then return end
    alert = CreateFrame("Frame", "AurasLossOfControl", UIParent)
    alert:SetFrameStrata("HIGH")
    A.Icon(alert, 56, 22)
    alert.label = alert:CreateFontString(nil, "OVERLAY")
    alert.label:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE")
    alert.label:SetPoint("TOP", alert, "BOTTOM", 0, -4)
    if not alert:IsUserPlaced() then alert:SetPoint("CENTER", UIParent, "CENTER", 0, -100) end
    A.Texture(alert.icon, PLACEHOLDER)
    A.Text(alert.label, "Loss of control")
    alert.handle = A.Movable(alert, "Loss of control", Refresh)
    alert:Hide()
end

-- The option: no event while it is off.
function A.LossOfControl()
    if db.lossOfControl then
        events:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
        if alert then alert.handle.off = nil end
        Refresh()
    else
        events:UnregisterEvent("LOSS_OF_CONTROL_UPDATE")
        if alert then alert.handle.off = true; alert:Hide(); A.Timing(alert) end
    end
end

events:SetScript("OnEvent", Refresh)
A.LossOfControl()
