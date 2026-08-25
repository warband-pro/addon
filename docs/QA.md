# QA Checklist — 5 min manual pass before any release

Copy into sticky + run per alt.

Preflight
- [ ] Fully quit WoW then launch (TOC change detection) not /reload only
- [ ] Only WarbandPro + BugSack/BugGrabber enabled
- [ ] /console taintLog 1
- [ ] Delete WarbandProDB.lua from WTF to test fresh install (optional full wipe pass) — backup first if testing warbank shared)

Pass 1 — single char fresh
- [ ] Log Vocnar — chat silent (no load print)
- [ ] /warband — panel opens 400x500 single list shows Vocnar row 🟢 fresh
- [ ] /dump WarbandProDB.chars — count 1 guid entry
- [ ] Move item between bags — wait .5s — /dump seenAt.bag increments vs earlier (write previous timestamp down)
- [ ] Open bank formerly null after — bank items appear in dump and panel secondary line shows "Bank 2m ago"
- [ ] Open Warband Bank — panel Warband Bank line updates shared SeenBy Vocnar
- [ ] /dump WarbandProDB.chars[guid].gear — one entry per equipped slot, each with a non-empty s and a plausible ilvl
- [ ] Spot-check one s string against the item's tooltip — bonus IDs differ between two copies of the same base item at different difficulties
- [ ] Equip a different item — wait 1s — /dump seenAt.gear moved
- [ ] Switch spec then switch back — /dump WarbandProDB.chars[guid].talents.specs has 2 entries, not 1 replaced
- [ ] /warband copy — big EditBox appears wb1! prefix, len ~600-4000, Ctrl-A Ctrl-C highlights all
- [ ] Paste into /app import preview → 1 char green dot, gold matches, bags count, currencies >=1, consumables numbers, vault matches in-game Weekly Rewards UI visual comparison (1/3 etc)
- [ ] /console taintLog 0 — /reload — check Logs/taint.log no line WarbandPro

## Clear-out — /warband junk (1.4.0)

The taint line above is the one that matters most for this panel: it is the
only place this addon puts a secure button on screen. Run the taint check again
after using it, not only after the export pass.

- [ ] /warband junk on a character with no list — panel opens, says "paste the cleanup string from warband.pro/gear above"
- [ ] Paste your own export string (wb1!) into the paste box — red line names it as an export string, does NOT say invalid
- [ ] Paste rubbish — red line, panel does not close, nothing stored
- [ ] warband.pro /gear → [ cleanup ] → [copy addon string] → paste here — list renders, paste box clears
- [ ] /dump WarbandProDB.junk — one entry keyed by your guid, generatedAt a plausible unix time
- [ ] Rows show item name in quality colour, item level, and a reason ("30 behind" / "cannot wear")
- [ ] Sell buttons are disabled away from a merchant, footer says "open a merchant to sell"
- [ ] Open a merchant — Sell enables, footer changes; click one — item sells, row disappears, header count drops
- [ ] Non-enchanter: no Disenchant buttons at all, verdict column reads sell
- [ ] Enchanter: Disenchant buttons present; click one — cast starts (it is your click, not the addon's)
- [ ] Move a listed item to the bank, reopen the panel — it leaves the list and "N no longer in your bags" counts it
- [ ] Two identical items in bags — both appear as rows, one verdict covered both
- [ ] Grey vendor trash appears without being on the pasted list at all
- [ ] Paste a string from a DIFFERENT account — panel says the list is for characters this account has not scanned
- [ ] Enter combat with the panel open — it closes; leave combat — it reopens by itself
- [ ] /warband junk while in combat — chat says it will open when you drop out, and it does
- [ ] /console taintLog 1 — repeat the merchant + disenchant pass — /reload — Logs/taint.log has no WarbandPro line

## The window and the ways in (1.5.0)

Nothing in CI touches a frame, and there is no Lua interpreter on the
maintainer's machine either — `luacheck` runs on push and the first thing to
meet a live client is this list. So run it, do not skim it.

- [ ] Minimap icon on the ring at login, inside the stock tracking border
- [ ] Click it — window opens on the export tab, string already selected
- [ ] Click it again — window closes
- [ ] Right-click — Options tab; right-click again — closes
- [ ] Hover — tooltip names the addon, the character count and the freshest age
- [ ] Drag it round the ring — it follows the cursor and stays where dropped
- [ ] /reload — still where you dropped it
- [ ] Full logout and back — still there (WarbandProDB.opts.minimapAngle persisted)
- [ ] Options > Show the minimap button, uncheck — icon goes; check — it returns to the same spot
- [ ] /warband minimap off, then on — same result, and chat says which
- [ ] Enter combat and click the icon — chat says it will open when you drop out, and it does
- [ ] Key Bindings has a section "Warband.pro Companion" with one row, "Open the export window", unbound
- [ ] Bind it and press — window opens on the export tab; press again — closes
- [ ] No LUA_WARNING about Bindings.xml at login, and BugSack is empty

Pass 2 — multi-char bundle
- [ ] Log Voctara alt without opening warbank — /warband copy bundle len 2
- [ ] Verify bundle still contains Warbank from Vocnar snapshot (seenAt not reset, seenBy still Vocnar)
- [ ] Web import now 2 chars — Voctara 🟢, Vocnar 🟡 (<3d ideal), 3rd missing = never vs not deleted
- [ ] Log 6 all — bundle 6 = count 6

Pass 3 — edge + combat
- [ ] Enter combat (dunnie target dummy punch) /warband copy — button should be disabled or "cannot export in combat" red bar per Midnight secure rule — must not taint/error
- [ ] Close banker reopen warbank — see warbankSeenAt updated now
- [ ] Auctions — if have active, auctions.count >0 and panel line up
- [ ] Mail — if have mail and you opened mailbox, count etc
- [ ] /warband gear off — /warband copy — gear absent from bundle, byte count drops. /warband gear on — /warband copy — gear back, no rescan needed
- [ ] Memory — /script print mem: after `UpdateAddOnMemoryUsage(); print(GetAddOnMemoryUsage("WarbandPro"))` should be <2MB for 6 chars
- [ ] Export round-trip size: /script print string length of export box — <7KB bundle 6 target, 20KB hard cap

Result paste back format (pasteable to AI loop):

```
PASS BugSack empty
PASS taint 0
PASS single count 1
PASS multi count 6
PASS warbank shared valid
PASS combat lockdown safe
PASS copy prefix wb1! len 6420
PASS dots 6 green
PASS web preview 6 green 0 stale
PASS mem 1240 KB
PASS vault matches (4/8 vs 4/8)
PASS gear 18 pieces, bonus IDs distinct
PASS talents 2 specs known, loadout non-empty
PASS gear toggle off/on
FAIL? notes...
```

If any FAIL, copy screenshot/text dump + /dump WarbandProDB minimal redacted for AI.

Notes to AI if fail:

- Copy taint.log line containing WarbandPro exact
- Copy BugSack error frame with stack if not empty
- Show export box screenshot of prefix string truncated first 20 chars
