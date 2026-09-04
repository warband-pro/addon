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
- [ ] Hover on an account with a vault slot earned, a keystone, a live lockout and a capped currency — one line each, labels coloured green / white / gold / red, names in class colour
- [ ] Hover on a fresh install with one unscanned character — the four lines are ABSENT, not zero. This is the check the glance exists to fail
- [ ] Hover with four or more characters holding keystones — three named, then `+N`, and the tooltip does not cover the minimap
- [ ] Hover after a weekly reset, before logging the saved alt in — `saved` does not name them. Their stored lockout has expired and the glance will not claim it
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

## The roster grid (1.9.0)

`tools/roster-test.lua` holds every rule about WHAT a cell says — 36
assertions, and the load-bearing one is that an unread section draws an empty
cell rather than a `0`. What it cannot check is whether the grid DRAWS: the
model is a table of strings and tones, and alignment, class colour and paging
only exist once a frame does. So this pass is about the picture, not the
numbers.

- [ ] `/warband roster` opens the window on the Roster tab; the tab is
      leftmost and `/warband` on its own still opens Export with the string
      already highlighted
- [ ] Column headers line up over their cells, and stay put when the rows are
      scrolled — they are outside the scroll frame for exactly this
- [ ] Your current character is the first column
- [ ] Names carry class colour; a level and an item level sit under each
- [ ] A character you have not played in days shows a red dot, and the same
      character shows the same dot on the Export tab — one freshness rule
- [ ] A row where you know a value is missing is BLANK, not `0` — the easiest
      way to see one is a character whose bank you have never opened
- [ ] With seven or more characters, `[ < ]` and `[ > ]` appear and page the
      columns; the row labels do not change as you page
- [ ] A lockout row reads `killed/total` and matches the Raid Info panel
- [ ] Reopening the window comes back on page 1 rather than where you left it
- [ ] Nothing in BugSack after opening the tab on an account with one
      character and again with a full warband
- [ ] Hover a lockout cell — the tooltip names every boss dead and alive and
      says how long until it resets, and its title names the character
- [ ] Hover a vault cell — each slot's threshold, and which are earned
- [ ] Hover a currency with a weekly cap — "this week 320/1,500"
- [ ] Hover a column header — realm, guild, level, item level, gold, last zone,
      when it was scanned
- [ ] Move the mouse from a cell that has a tooltip to a blank one — the old
      tooltip disappears rather than following the cursor
- [ ] Page the columns with `>` while a tooltip is up, then hover the same
      screen position — it describes the NEW character, not the old one
- [ ] A character whose lockout expired while you were logged out shows a blank
      cell there, not last week's `2/8`
- [ ] After pasting a `wbc1!` string, the `from warband.pro` rows fill in for
      the characters it covered and stay blank for the ones it did not

## The gear set — equip and save (1.6.0)

**This is the first thing this addon has ever done that moves gear on your
character**, and like the merchant pass above, nothing in CI can reach it: the
equip path calls `PickupContainerItem`, `EquipCursorItem` and
`C_EquipmentSet.SaveEquipmentSet`, none of which exist outside a live client.
`tools/gearset-test.lua` pins the decode, the three-bucket resolve, the
equips-before-save order and the combat refusals against a fake client — the
order especially, because saving in the same frame as the equips snapshots the
kit you were wearing before. What it cannot check is whether the real API
behaves the way the fake one does. Run this on a character whose kit you do not
mind rearranging, and take the backup line seriously.

- [ ] Back up WTF/.../SavedVariables/WarbandPro.lua before the first pass —
      the set this writes is a real Equipment Manager set
- [ ] Note your existing Equipment Manager sets first; none of them is called
      "warband.pro" unless a previous pass made it
- [ ] Export from `/warband`, paste into warband.pro, open `/gear` → `[ slots ]`
- [ ] Select your character — the inspector lists every slot that changes, with
      item names, and `copy equip string` sits under the list
- [ ] Press it, paste into the addon's Import tab — the gear-set row appears
      above the junk list and names the same slots the website listed
- [ ] The counts agree with the site: `N to equip`, `already worn`, `missing`
- [ ] An item the site named that you have since moved to the bank reads as
      missing, and says it is in your bank rather than vanishing
- [ ] Press `Equip N & save set` — the items equip, one receipt line prints,
      and it names the same numbers the row did
- [ ] `/dump C_EquipmentSet.GetEquipmentSetID("warband.pro")` — a real id
- [ ] Open the Equipment Manager — the set exists and its icon is the addon's;
      switching to it re-equips what you are wearing now
- [ ] Press it a second time with nothing left to change — the button reads
      `Save set` and the receipt says everything was already worn
- [ ] **The order check**: equip something different by hand first, then apply
      a set — the saved set must contain what the site chose, NOT what you were
      wearing when you pressed the button
- [ ] A ring the site aimed at finger 2 lands in finger 2, not finger 1
- [ ] Paste a `wbc1!` cleanup string into the same box — it still reads as a
      cleanup list; paste `wbg1!` — it reads as a gear set. Neither says
      "invalid"
- [ ] Paste a `wbg1!` string from a DIFFERENT account — the panel says the set
      is for characters this account has not scanned
- [ ] Enter combat with a set pending — the panel closes; the receipt says to
      press equip again after the fight, and nothing equips mid-fight
- [ ] Start an apply, then immediately move one of the named items in your bags
      — after three seconds the receipt says how many did not equip, and the
      set saved is what you are actually wearing
- [ ] `/console taintLog 1` — repeat the whole equip pass — `/reload` —
      `Logs/taint.log` has no WarbandPro line
- [ ] BugSack empty after all of the above

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
PASS gear set equipped 4, saved, order correct
FAIL? notes...
```

If any FAIL, copy screenshot/text dump + /dump WarbandProDB minimal redacted for AI.

Notes to AI if fail:

- Copy taint.log line containing WarbandPro exact
- Copy BugSack error frame with stack if not empty
- Show export box screenshot of prefix string truncated first 20 chars
