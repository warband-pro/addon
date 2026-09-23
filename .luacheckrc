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

  -- the vendor window's sell-all (UI.lua): Blizzard's own merchant frame, which
  -- the button parents itself to, and the confirm it puts under the click.
  "MerchantFrame", "StaticPopup_Show",

  -- /warband perf (Perf.lua)
  "debugprofilestop", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage",
  "UpdateAddOnCPUUsage", "GetAddOnCPUUsage", "GetCVar",

  -- the roster grid (Roster.lua, UI.lua): the client's own class palette, so
  -- a name in this window is the colour it is on the character's own frame.
  "RAID_CLASS_COLORS",
  -- Class icons beside the sidebar names: the client's own circle sheet, cut
  -- with its own coordinates. Static data, read like the palette above.
  "CLASS_ICON_TCOORDS",

  -- character
  "UnitGUID", "UnitName", "UnitClass", "UnitRace", "UnitLevel", "UnitXP", "UnitXPMax", "UnitFactionGroup",
  "GetXPExhaustion", "GetRealmName", "GetZoneText", "GetBindLocation",
  "GetAverageItemLevel", "GetGuildInfo", "GetMoney",

  -- inventory, currency, professions, mail, auctions
  "C_Container", "C_Item", "GetItemInfoInstant", "Enum", "C_Bank", "C_Spell",
  "C_CurrencyInfo", "GetProfessions", "GetProfessionInfo", "C_TradeSkillUI",
  "GetInboxNumItems", "GetInboxHeaderInfo", "C_AuctionHouse",

  -- the trading post (Scan.TradingPost). `C_PerksProgram` populates only while
  -- the shelf is open and `C_PerksActivities` is the Traveler's Log; both are
  -- read through `ns.safe`, which returns nil for a name the client does not
  -- have, so listing them here is what lets the lint pass without the code
  -- assuming they exist. `C_DateAndTime` is here for the realm's own month,
  -- which is the trading post's identity — see Scan.lua.
  "C_PerksProgram", "C_PerksActivities", "C_DateAndTime",

  -- housing decor (Scan.Decor). `C_HousingCatalog` is the only source in the
  -- world for what decor an account owns — Blizzard publishes the catalog and
  -- not the ownership, and this is the namespace the client answers it from.
  -- Listed for the same reason as the three above: the code reads every one of
  -- its functions through `ns.safe` rather than assuming the name exists, and
  -- the lint needs the namespace declared to let that read compile.
  "C_HousingCatalog",

  -- gear and talents
  "GetInventoryItemLink", "GetInventoryItemID", "ItemLocation",
  "C_ClassTalents", "C_Traits", "GetSpecialization", "GetSpecializationInfo",
  -- the gear-set apply (GearSet.lua): equip under the player's click, then
  -- snapshot the paperdoll into an Equipment Manager set
  "C_EquipmentSet", "EquipCursorItem", "ClearCursor",

  -- lockouts, keystone, vault
  "GetNumSavedInstances", "GetSavedInstanceInfo", "GetSavedInstanceEncounterInfo",
  "GetNumSavedWorldBosses", "GetSavedWorldBossInfo", "RequestRaidInfo",
  "C_MythicPlus", "C_ChallengeMode", "C_WeeklyRewards", "GetDifficultyInfo",
  -- Combat logging, on entering a raid. `GetInstanceInfo` names the instance
  -- TYPE, which is what makes "raids only" answerable; `LoggingCombat` reads
  -- the current state when called with no argument and sets it with one.
  "GetInstanceInfo", "LoggingCombat",
  -- The auction house, for the shopping list's one action.
  "C_AuctionHouse",
}

-- The confirm dialog. The table is the game's and stays read-only; the one key
-- in it is this addon's, named like everything else it owns. Spelling the field
-- out rather than declaring the whole table writable keeps the leak audit
-- honest: a typo'd second dialog name would be a warning rather than a shrug.
read_globals.StaticPopupDialogs = {
  fields = { WARBANDPRO_SELL_LIST = { read_only = false } },
}

ignore = {
  "212",  -- unused argument: event handlers take arguments they ignore
  "213",  -- unused loop variable
}
