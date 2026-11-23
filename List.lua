-- The watched-aura list: the addon's own window, since the Settings window cannot
-- draw a list editor (Settings pattern rule 6). /auras and the page open it. It
-- shows one group at a time; a new aura joins the group shown.
local _, A = ...
local db = AurasDB

local LINES, LINE = 10, 24
-- The columns: the entry's key, its header, its tip, the unit it is for (nil: both),
-- and whether UnitFrames draws what it changes.
local COLUMNS = {
    { "icon", "Icon", "Its own icon with the time left; Ctrl+Shift moves it." },
    { "topRight", "Top", "Also in the game's buffs at the top right.", "player", true },
    { "inRow", "Row", "Also in the row under its frame.", nil, true },
    { "mine", "Mine", "Only the one you cast; another player's stays in the row." },
    { "cooldown", "CD", "When it ends, its spell's cooldown, greyed.", "player" },
    { "grey", "Grey", "Stays on screen, greyed, while it is not active. Its picture shows once you have had it." },
}
-- Where a group shows (GetInstanceInfo's instanceType), in menu order.
local PLACES = {
    { "all", "Everywhere" }, { "raid", "Raids" }, { "party", "Dungeons" },
    { "pvp", "Battlegrounds" }, { "none", "Open world" }, { "off", "Off" },
}

local win = CreateFrame("Frame", "AurasList", UIParent)
win:SetWidth(500); win:SetHeight(128 + LINES * LINE + 84)
win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
win:SetFrameStrata("DIALOG")
win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 } })
win:EnableMouse(true)
win:SetMovable(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", function() win:StartMoving() end)
win:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
win:Hide()
table.insert(UISpecialFrames, "AurasList") -- Escape closes it
local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", win, "TOP", 0, -16)
title:SetText("Watched auras")
CreateFrame("Button", nil, win, "UIPanelCloseButton"):SetPoint("TOPRIGHT", win, "TOPRIGHT", -6, -6)

local box = CreateFrame("EditBox", "AurasListName", win, "InputBoxTemplate")
box:SetWidth(150); box:SetHeight(20)
box:SetPoint("TOPLEFT", win, "TOPLEFT", 24, -40)
box:SetAutoFocus(false)
box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
local function Typed()
    local text = string.match(box:GetText() or "", "^%s*(.-)%s*$")
    box:SetText(""); box:ClearFocus()
    return text
end

local offset, shown, Draw = 0, nil, nil -- shown: the group on screen
local function Changed() A.Rebuild(); Draw() end

-- A spell's name or ID; a new entry gets its own icon and, for a buff, its cooldown.
local function Add(unit)
    local text = Typed()
    local id = tonumber(text)
    local name = id and GetSpellInfo(id) or text
    if not name or name == "" then return end
    for _, entry in ipairs(db.watched) do if entry.unit == unit and entry.name == name then return end end
    table.insert(db.watched, { name = name, spellID = id, unit = unit, group = shown.name, icon = true,
        topRight = false, inRow = false, mine = unit == "target", cooldown = unit == "player", grey = false })
    Changed()
end

local function Tip(frame, text)
    frame.tip = text
    frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT"); GameTooltip:SetText(frame.tip, 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function Button(text, width, anchor, x, onClick, tip)
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(22)
    b:SetPoint("LEFT", anchor, "RIGHT", x, 0)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if tip then Tip(b, tip) end
    return b
end
local place = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
place:SetWidth(90); place:SetHeight(22)
place:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -12)
place:SetText("Place icons")
place:SetScript("OnClick", function() A.Place() end)
Tip(place, "Shows every icon, the hidden ones too, so you can drag them; click again when done. Ctrl+Shift does the same while held.")
Button("Add your buff", 110, box, 8, function() Add("player") end)
Button("Add target debuff", 120, box, 122, function() Add("target") end)
box:SetScript("OnEnterPressed", function() Add("player") end)

-- The group on screen, where it shows, a new group, its name, and delete.
-- A shown dropdown runs its menu at SetupMenu (DropdownButton.lua:254), before
-- any group is on screen or any line has its entry: the checks allow for that.
local function Dropdown(width, x)
    local dd = CreateFrame("DropdownButton", nil, win, "WowStyle1DropdownTemplate")
    dd:SetWidth(width)
    dd:SetPoint("TOPLEFT", win, "TOPLEFT", x, -68)
    return dd
end
local groupMenu, placeMenu = Dropdown(150, 20), Dropdown(120, 178)
A.menus = { group = groupMenu, place = placeMenu }
groupMenu:SetupMenu(function(_, root)
    for _, group in ipairs(db.groups) do
        local label = group.name .. (A.Active(group) and "" or "  |cff888888(not here)|r")
        root:CreateRadio(label, function(g) return g == shown end,
            function(g) shown, offset = g, 0; Draw() end, group)
    end
end)
placeMenu:SetupMenu(function(_, root)
    for _, place in ipairs(PLACES) do
        root:CreateRadio(place[2], function(p) return shown ~= nil and shown.where == p end,
            function(p) shown.where = p; Changed() end, place[1])
    end
end)
Tip(placeMenu, "Where this group's auras are watched. Elsewhere they stay in the game's own buffs and rows.")

-- New group and Rename type the name over the group dropdown: Enter keeps it,
-- Escape (or a click elsewhere) lets it go. A name already used is not taken.
local naming -- nil, "new" or "rename"
local nameBox = CreateFrame("EditBox", "AurasListGroupName", win, "InputBoxTemplate")
nameBox:SetWidth(140); nameBox:SetHeight(20)
nameBox:SetPoint("TOPLEFT", win, "TOPLEFT", 28, -71)
nameBox:SetAutoFocus(false)
nameBox:SetMaxLetters(24)
nameBox:Hide()
local function EndNaming()
    naming = nil
    nameBox:ClearFocus(); nameBox:Hide()
    groupMenu:Show()
end
local function Name(mode)
    naming = mode
    groupMenu:Hide()
    nameBox:SetText(mode == "rename" and shown.name or "")
    nameBox:Show(); nameBox:SetFocus(); nameBox:HighlightText()
end
nameBox:SetScript("OnEnterPressed", function()
    local name = string.match(nameBox:GetText() or "", "^%s*(.-)%s*$")
    local used = A.GroupNamed(name)
    if name == "" or used and (naming == "new" or used ~= shown) then return end
    if naming == "new" then
        shown = { name = name, where = "all" }
        table.insert(db.groups, shown)
        offset = 0
    else
        for _, entry in ipairs(db.watched) do if entry.group == shown.name then entry.group = name end end
        shown.name = name
    end
    EndNaming()
    Changed()
end)
nameBox:SetScript("OnEscapePressed", EndNaming)
nameBox:SetScript("OnEditFocusLost", function() if naming then EndNaming() end end)
Button("New", 50, placeMenu, 6, function() Name("new") end, "A new group: type its name, then Enter.")
Button("Rename", 64, placeMenu, 60, function() Name("rename") end, "Rename this group: type its name, then Enter.")
local delete = Button("Delete", 56, placeMenu, 128, function()
    for n, group in ipairs(db.groups) do
        if group == shown then table.remove(db.groups, n); break end
    end
    shown = db.groups[1]
    for _, entry in ipairs(db.watched) do A.Group(entry) end -- the deleted group's auras join it
    Changed()
end)

for c, column in ipairs(COLUMNS) do
    local head = CreateFrame("Frame", nil, win)
    head:SetWidth(34); head:SetHeight(16)
    head:SetPoint("TOPLEFT", win, "TOPLEFT", 196 + (c - 1) * 34, -100)
    head:EnableMouse(true)
    local label = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints(head)
    label:SetText(column[2])
    Tip(head, column[3])
end


-- The details of the picked line: what only its icon has. A pick is made by clicking
-- the line's name.
local picked
local WARNS = { { nil, "Off" }, { 3, "3 s" }, { 5, "5 s" }, { 10, "10 s" }, { 30, "30 s" }, { 60, "1 min" } }
local SIZES = { { 28, "Small" }, { 36, "Normal" }, { 48, "Large" }, { 64, "Huge" } }
local panel = CreateFrame("Frame", nil, win)
panel:SetWidth(460); panel:SetHeight(46)
panel:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -116 - LINES * LINE - 14)
local function Heading(text, x)
    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, 0)
    fs:SetText(text)
end
local function Detail(x, width, text, tip)
    Heading(text, x + 4)
    local dd = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    dd:SetWidth(width)
    dd:SetPoint("TOPLEFT", panel, "TOPLEFT", x - 14, -12)
    Tip(dd, tip)
    return dd
end
-- A menu of choices for one key of the picked entry; `none` is the key's off value.
local function Choices(dd, key, rows)
    dd:SetupMenu(function(_, root)
        for _, row in ipairs(rows) do
            root:CreateRadio(row[2], function(v) return picked ~= nil and picked[key] == v end,
                function(v) picked[key] = v; Changed() end, row[1])
        end
    end)
end
local glowRows = { { nil, "Off" } }
for _, c in ipairs(A.COLORS) do glowRows[#glowRows + 1] = { c[1], c[2] } end
local glowMenu = Detail(20, 110, "Glow", "A glowing border while it is active.")
local warnMenu = Detail(150, 110, "Pulse under", "The icon pulses when this little time is left.")
local sizeMenu = Detail(280, 110, "Size", "How big its icon is.")
A.menus.glow, A.menus.warn, A.menus.size = glowMenu, warnMenu, sizeMenu
Choices(glowMenu, "glow", glowRows)
Choices(warnMenu, "warn", WARNS)
Choices(sizeMenu, "size", SIZES)
local barCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
barCheck:SetWidth(22); barCheck:SetHeight(22)
barCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 394, -12)
barCheck:SetScript("OnClick", function() picked.bar = barCheck:GetChecked() and true or false; Changed() end)
Tip(barCheck, "A bar of the time left beside its icon, in the glow's colour.")
local barLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
barLabel:SetPoint("LEFT", barCheck, "RIGHT", 0, 0)
barLabel:SetText("Bar")
local panelTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
panelTitle:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 4, 4)

-- One line per entry of the group: icon, name ("on you" or "on target"), the
-- switches, its group, remove.
local lines = {}
A.lines = lines
for i = 1, LINES do
    local line = CreateFrame("Frame", nil, win)
    line:SetWidth(440); line:SetHeight(LINE)
    line:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -116 - (i - 1) * LINE)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetWidth(18); line.icon:SetHeight(18)
    line.icon:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    line.name = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.name:SetPoint("LEFT", line, "LEFT", 24, 0)
    line.name:SetWidth(150); line.name:SetJustifyH("LEFT")
    line.hl = line:CreateTexture(nil, "BACKGROUND")
    line.hl:SetAllPoints(line)
    line.hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    line.hl:SetVertexColor(0.2, 0.6, 1, 0.25)
    local pick = CreateFrame("Button", nil, line)
    pick:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
    pick:SetPoint("BOTTOMRIGHT", line, "BOTTOMLEFT", 178, 0)
    pick:SetScript("OnClick", function() picked = line.entry; Draw() end)
    Tip(pick, "Click to set its glow, warning, size and bar below.")
    line.checks = {}
    for c, column in ipairs(COLUMNS) do
        local check = CreateFrame("CheckButton", nil, line, "UICheckButtonTemplate")
        check:SetWidth(22); check:SetHeight(22)
        check:SetPoint("LEFT", line, "LEFT", 182 + (c - 1) * 34, 0)
        check:SetScript("OnClick", function()
            line.entry[column[1]] = check:GetChecked() and true or false
            A.Rebuild()
        end)
        Tip(check, column[3])
        line.checks[c] = check
    end
    local move = CreateFrame("DropdownButton", nil, line, "WowStyle1ArrowDropdownTemplate")
    move:SetPoint("LEFT", line, "LEFT", 380, 0)
    move:SetupMenu(function(_, root)
        root:CreateTitle("Move to")
        for _, group in ipairs(db.groups) do
            root:CreateRadio(group.name, function(name) return line.entry ~= nil and line.entry.group == name end,
                function(name) line.entry.group = name; Changed() end, group.name)
        end
    end)
    Tip(move, "Move it to another group.")
    local remove = CreateFrame("Button", nil, line, "UIPanelCloseButton")
    remove:SetWidth(24); remove:SetHeight(24)
    remove:SetPoint("RIGHT", line, "RIGHT", 6, 0)
    remove:SetScript("OnClick", function()
        for n, entry in ipairs(db.watched) do
            if entry == line.entry then table.remove(db.watched, n); break end
        end
        Changed()
    end)
    Tip(remove, "Stop watching it.")
    line.move, line.remove, lines[i] = move, remove, line
end

local list = {} -- the shown group's entries, in the saved order
Draw = function()
    if not shown or not A.GroupNamed(shown.name) then shown = db.groups[1] end
    table.wipe(list)
    for _, entry in ipairs(db.watched) do if A.Group(entry) == shown then list[#list + 1] = entry end end
    offset = math.max(0, math.min(offset, #list - LINES))
    groupMenu:GenerateMenu(); placeMenu:GenerateMenu()
    delete:SetEnabled(#db.groups > 1)
    Tip(delete, #db.groups > 1 and "Delete this group; its auras join " .. (db.groups[1] == shown
        and db.groups[2] or db.groups[1]).name .. "." or "The last group stays.")
    local found
    for _, entry in ipairs(list) do if entry == picked then found = true end end
    if not found then picked = list[1] end
    panel:SetShown(picked ~= nil)
    if picked then
        panelTitle:SetText("Details: " .. picked.name)
        glowMenu:GenerateMenu(); warnMenu:GenerateMenu(); sizeMenu:GenerateMenu()
        barCheck:SetChecked(picked.bar)
        panel:SetAlpha(picked.icon and 1 or 0.4) -- they belong to its own icon
    end
    for i, line in ipairs(lines) do
        local entry = list[offset + i]
        line.entry = entry
        line:SetShown(entry ~= nil)
        line.hl:SetShown(entry ~= nil and entry == picked)
        if entry then
            local _, _, texture = GetSpellInfo(entry.spellID or entry.name)
            line.icon:SetTexture(entry.texture or texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            line.name:SetText(entry.name .. (entry.unit == "player" and "  |cff888888on you|r" or "  |cff888888on target|r"))
            line.move:SetShown(#db.groups > 1)
            for c, column in ipairs(COLUMNS) do
                local check = line.checks[c]
                check:SetShown(column[4] == nil or column[4] == entry.unit)
                check:SetChecked(entry[column[1]])
                -- Dimmed where it can show nothing: a spell with no cooldown of its own
                -- (Slice and Dice), or the top right and rows without UnitFrames.
                local tip = column[1] == "cooldown" and not A.HasCooldown(entry.name)
                    and entry.name .. " has no cooldown of its own."
                    or column[5] and not UnitFrames and "Needs UnitFrames." -- vanillaforge-ignore: K1
                check:SetEnabled(not tip)
                check:SetAlpha(tip and 0.35 or 1)
                check.tip = tip or column[3]
            end
        end
    end
end
-- The wheel scrolls a group longer than the window.
win:EnableMouseWheel(true)
win:SetScript("OnMouseWheel", function(_, delta) offset = offset - (delta or arg1); Draw() end)

function A.List()
    if win:IsShown() then win:Hide() else Draw(); win:Show() end
end
