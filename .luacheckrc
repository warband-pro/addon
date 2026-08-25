-- luacheck configuration — run `luacheck .` from the repo root, 0 warnings.
std = "lua51"
exclude_files = { "Vendor/" }   -- upstream LibDeflate is vendored unlinted

-- Length limits apply to code, not to prose. luacheck measures bytes, so the
-- box-drawing section rules read as 200+ bytes while occupying ~70 columns;
-- holding comments to a byte budget would mean writing worse comments.
max_line_length = 120
max_comment_line_length = false

-- Globals this addon is allowed to define. Everything else lives on the private
-- addon table, so this list is also the leak audit.
globals = {
  "WarbandPro",
  "WarbandProDB",
  "WarbandPro_OnAddonCompartmentClick",
  -- Bindings.xml names an action and a header; these are what the Key Bindings
  -- panel reads to print them as words rather than as tokens.
  "BINDING_HEADER_WARBANDPRO",
  "BINDING_NAME_WARBANDPRO_TOGGLE",
  "SLASH_WARBANDPRO1",
  "SlashCmdList",
}

read_globals = {
  -- Lua aliases WoW exposes globally
  "format", "tinsert", "strsplit", "select", "unpack", "time", "date",

  -- addon + frame plumbing. LibStub is read, never created: this addon ships no
  -- LibStub and registers nothing with it, but other addons put it in _G and we
  -- fall back to their LibDeflate when upstream's early return skips ours.
  "LibStub",
  "C_AddOns", "GetAddOnMetadata", "CreateFrame", "UIParent", "UISpecialFrames",
  -- the minimap button: the ring it is anchored to, the tooltip it fills, and
  -- the cursor position it reads while being dragged round the ring.
  "Minimap", "GameTooltip", "GetCursorPosition",
  "ChatFontNormal", "DEFAULT_CHAT_FRAME", "C_Timer", "GetServerTime",
  "GetBuildInfo", "InCombatLockdown",
  -- The export box watches for a real Ctrl+C so the copy can be acknowledged:
  -- WoW exposes no clipboard to read back, but it does say which modifier is
  -- held, and that is enough to stamp `lastExport` on the copy rather than on
  -- the render. See UI.lua's OnKeyDown.
  "IsControlKeyDown",

  -- the tabbed window (UI.lua)
  "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab", "PanelTemplates_TabResize",
  "PlaySound", "SOUNDKIT",

  -- /warband perf (Perf.lua)
  "debugprofilestop", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage",
  "UpdateAddOnCPUUsage", "GetAddOnCPUUsage", "GetCVar",

  -- character
  "UnitGUID", "UnitName", "UnitClass", "UnitRace", "UnitLevel", "UnitXP", "UnitFactionGroup",
  "GetXPExhaustion", "GetRealmName", "GetZoneText", "GetBindLocation",
  "GetAverageItemLevel", "GetGuildInfo", "GetMoney",

  -- inventory, currency, professions, mail, auctions
  "C_Container", "C_Item", "GetItemInfoInstant", "Enum", "C_Bank", "C_Spell",
  "C_CurrencyInfo", "GetProfessions", "GetProfessionInfo",
  "GetInboxNumItems", "GetInboxHeaderInfo", "C_AuctionHouse",

  -- gear and talents
  "GetInventoryItemLink", "GetInventoryItemID", "ItemLocation",
  "C_ClassTalents", "C_Traits", "GetSpecialization", "GetSpecializationInfo",

  -- lockouts, keystone, vault
  "GetNumSavedInstances", "GetSavedInstanceInfo", "GetSavedInstanceEncounterInfo",
  "GetNumSavedWorldBosses", "GetSavedWorldBossInfo", "RequestRaidInfo",
  "C_MythicPlus", "C_ChallengeMode", "C_WeeklyRewards", "GetDifficultyInfo",
}

ignore = {
  "212",  -- unused argument: event handlers take arguments they ignore
  "213",  -- unused loop variable
}
