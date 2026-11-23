-- The Auras page in ClassicAPI's Settings window (AddOn Options): one button to
-- the list, which the window cannot draw itself. /auras opens the list directly.
local _, A = ...

SettingsRegistrar:AddRegistrant(function()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Auras")
    local alert = Settings.RegisterAddOnSetting(category, "Auras_lossOfControl", "lossOfControl", AurasDB,
        Settings.VarType.Boolean, "Loss of control alert", true)
    alert:SetValueChangedCallback(A.LossOfControl)
    Settings.CreateCheckbox(category, alert,
        "While you are stunned, feared, silenced or school-locked, shows what it is and the time left near the center "
        .. "of the screen. Ctrl+Shift moves it. Turn it off if another addon does this.")
    layout:AddInitializer(CreateSettingsButtonInitializer("Watched auras", "Open the list", A.List,
        "Your buffs and your target's debuffs, each with its own icon and the time left, in groups "
        .. "that show everywhere or only in raids, dungeons, battlegrounds or the open world. "
        .. "Ctrl+Shift or Place icons moves the icons. Also: /auras", false))
    Settings.RegisterAddOnCategory(category)
end)

SLASH_AURAS1 = "/auras"
SlashCmdList.AURAS = function() A.List() end

A.Rebuild() -- the icons from the saved list
