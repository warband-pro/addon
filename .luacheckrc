-- luacheck configuration — run `luacheck .` from the repo root, 0 warnings.
std = "lua51"
max_line_length = 100
exclude_files = { "Vendor/" }   -- upstream LibDeflate is vendored unlinted

-- Globals this addon is allowed to define. Everything else lives on the private
-- addon table, so this list is also the leak audit.
globals = {
  "WarbandPro",
  "WarbandProDB",
  "WarbandPro_OnAddonCompartmentClick",
  "SLASH_WARBANDPRO1",
  "SlashCmdList",
}

read_globals = {
  -- Lua aliases WoW exposes globally
  "format", "tinsert", "strsplit", "select", "unpack", "time", "date",

  -- addon + frame plumbing
  "C_AddOns", "GetAddOnMetadata", "CreateFrame", "UIParent", "UISpecialFrames",
  "ChatFontNormal", "DEFAULT_CHAT_FRAME", "C_Timer", "GetServerTime",
  "GetBuildInfo", "InCombatLockdown",

  -- character
  "UnitGUID", "UnitName", "UnitClass", "UnitLevel", "UnitXP", "UnitFactionGroup",
  "GetXPExhaustion", "GetRealmName", "GetZoneText", "GetBindLocation",
  "GetAverageItemLevel", "GetGuildInfo", "GetMoney",

  -- inventory, currency, professions, mail, auctions
  "C_Container", "C_Item", "GetItemInfoInstant", "Enum", "C_Bank",
  "C_CurrencyInfo", "GetProfessions", "GetProfessionInfo",
  "GetInboxNumItems", "GetInboxHeaderInfo", "C_AuctionHouse",

  -- lockouts, keystone, vault
  "GetNumSavedInstances", "GetSavedInstanceInfo", "GetSavedInstanceEncounterInfo",
  "GetNumSavedWorldBosses", "GetSavedWorldBossInfo", "RequestRaidInfo",
  "C_MythicPlus", "C_ChallengeMode", "C_WeeklyRewards",
}

ignore = {
  "212",  -- unused argument: event handlers take arguments they ignore
  "213",  -- unused loop variable
}
