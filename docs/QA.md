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

The hover grid (1.18.0). The panel under the summary band is the Roster tab's
own model, so what it says has to match the tab exactly — open both and read
them against each other rather than reading the panel alone.

- [ ] Hover — the grid is in the tooltip: a column per character with the name in its class colour, group headings in orange, rows for the vault, lockouts, world bosses and currencies, currency rows carrying their icon
- [ ] Every value matches the Roster tab for the same character and row. A disagreement is a second source of truth and the one thing this cannot be
- [ ] Move the mouse off the button and onto the panel — it stays open. Move off the panel — it closes, and so does any cell tooltip
- [ ] Hover a lockout cell — a second tooltip opens beside the panel, titled with the character in class colour over the row label in orange, listing resets-in and each boss alive or dead
- [ ] Hover a currency cell — the same, with the weekly figure and whether it is at cap
- [ ] Hover a cell nobody has a value in — nothing opens, and the cell is EMPTY rather than `0`
- [ ] Click the button while the panel is open — the panel goes and the window opens. Drag the button — the panel goes and the button follows the cursor
- [ ] Hover on a warband wider than the screen — the leading columns are drawn, the character at the keyboard among them, and the footer says `+N characters did not fit`
- [ ] Hover on an account with more rows than the screen — the grid is cut from the bottom, the footer counts the rows, and the last line is never a group heading with nothing under it
- [ ] Hover on a fresh install with no characters — the panel says nothing has been scanned yet and still offers the click hints
- [ ] Raise the UI scale to maximum and hover — the panel is still on screen and still does not cover the minimap
- [ ] Drag it round the ring — it follows the cursor and stays where dropped
- [ ] /reload — still where you dropped it
- [ ] Full logout and back — still there (WarbandProDB.opts.minimapAngle persisted)
- [ ] Options > Show the minimap button, uncheck — icon goes; check — it returns to the same spot
- [ ] /warband minimap off, then on — same result, and chat says which
- [ ] Enter combat and click the icon — chat says it will open when you drop out, and it does
- [ ] Key Bindings has a section "Warband.pro" with one row, "Open the export window", unbound
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

## The slice row on the export tab (1.19.0)

The scope and the pager are controls now rather than slash commands. Nothing
here is testable off-client — `refreshScope` reads a bundle and sets widget
state — so this is the pass that says the row draws and the clicks land.

- [ ] `/warband` opens Export on `[ Whole warband ]`, and that button is the
      greyed one — the enabled button is always the scope you are NOT on
- [ ] Click `[ This character ]` — the string rebuilds, the header gains "this
      character only", the rows drop to one, and the byte count falls
- [ ] Click `[ Whole warband ]` back — the full bundle returns, same string as
      the tab opened with
- [ ] Close the window and reopen it — it is back on `[ Whole warband ]`. The
      scope does NOT survive a close, deliberately; the camp flow must never
      inherit a gear flow's one-character bundle
- [ ] `/warband copy current` still opens straight into the smaller scope, and
      `/warband copy 2` still opens on page 2
- [ ] With fewer characters than `ns.MAX_CHARS`: no pager, no `page N of M`
- [ ] With more: `page 1 of 3` and `[ < ] [ > ]` beside it, `<` greyed on page
      1 and `>` greyed on the last; the header reads "20 of 41 — the rest go
      out a page at a time" and names no slash command
- [ ] Switch to `[ This character ]` while paged — the pager disappears (one
      character never pages), and switching back lands on page 1
- [ ] Past 20KB, `[ Just this character ]` appears beside `[ Select all ]` and
      the footer says "large"; clicking it does the same thing the slice row's
      second button does, and it vanishes once the bundle is small
- [ ] Widen the window to 1600 and shrink it to the 560 minimum — the row does
      not overlap the footer, `[ Select all ]`, or the pager

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
- [ ] `[ < ]` and `[ > ]` appear only when the warband is wider than the window
      can be dragged; the row labels do not change as you page
- [ ] A lockout row reads `killed/total` and matches the Raid Info panel
- [ ] Reopening the window comes back on page 1 rather than where you left it
- [ ] Nothing in BugSack after opening the tab on an account with one
      character and again with a full warband
- [ ] Hover a lockout cell — the tooltip names every boss dead and alive and
      says how long until it resets, and its title names the character
- [ ] Hover a vault cell — each slot's threshold, and which are earned
- [ ] With a Great Vault slot earned: export, paste, and the site's vault panel
      names the item that slot is offering (`rows[].r`; needs the vault frame
      opened at least once this session so the client has the links)
- [ ] `/warband equip raid` with a raid setup pasted — the gear equips AND the
      talent build assigned to raid loads, and the receipt names it
- [ ] `/warband equip delve` with no delve setup — says so, equips nothing, and
      does NOT put on the raid set
- [ ] `/warband equip nonsense` — lists the nights that exist
- [ ] A shopping list on the From warband.pro tab: one row per gem/enchant,
      under the gear, saying how many and which slots
- [ ] Open the auction house and left-click a shopping row — it searches for
      that item by name. Click one with the auction house shut — nothing
      happens, and no error
- [ ] Options → combat logging on, then zone into a raid: logging starts and
      says so. Leave: it stops. Zone into a DUNGEON with it on: nothing happens
- [ ] Turn it on while already standing in a raid — it starts immediately
      rather than waiting for the next loading screen
- [ ] Hover a currency with a weekly cap — "this week 320/1,500"
- [ ] Hover a column header — realm, guild, level, item level, gold, last zone,
      when it was scanned
- [ ] Move the mouse from a cell that has a tooltip to a blank one — the old
      tooltip disappears rather than following the cursor

### Shutting a group (unreleased)

The rules are in `tools/roster-test.lua`; what a test cannot see is that the
click lands on the header rather than on the row under it, and that a widget
that used to be a header stops being clickable when it becomes a data row.

- [ ] Click a group's label — its rows fold away, the header stays with a `+`
      in front of it and the count of rows it is holding
- [ ] Click it again — the same rows come back, in the same order
- [ ] Hover a header — it highlights and says which way the click goes; hover a
      data row — it highlights and says nothing
- [ ] Click a data row — nothing happens, and no group shuts
- [ ] Shut a group, `/reload`, reopen — it is still shut. Shut every group,
      `/reload` — the window opens on seven headers and no rows, and each one
      opens again
- [ ] Shut a group whose rows all belong to one character, then page past that
      character — the header goes too, count and all
- [ ] Shut the tallest group and scroll — the scroll bar shortens to the rows
      that are left rather than scrolling into empty space

### The resizable window (unreleased)

The grid now measures itself, so the picture depends on the window and on the
size of the warband looking at it. The two failures worth hunting are a column
count that does not follow the width, and a pool that grows but never shrinks —
a widget left over from a wider window still drawing last render's cell.

- [ ] The window opens at eight columns wide with nothing configured
- [ ] Drag the corner grip wider — columns APPEAR as it grows, and the headers
      stay over their cells the whole way
- [ ] Drag it narrower — columns disappear and no orphaned name or cell is left
      behind past the right edge of the grid
- [ ] It refuses to go below about 560 wide or above 1600
- [ ] `/reload` — the window comes back the size you left it and where you put
      it, and the columns match that width
- [ ] Log in on a second character — the window is the same size there
      (`opts.window` is account-wide, like the minimap angle)
- [ ] **The 24-row ceiling is gone.** On a character with a full currency list,
      scroll the grid to the bottom: every row has a label and cells, and there
      is no run of blank rows under the last one
- [ ] A group header (`currencies`, `pockets`) has a faint rule behind it
- [ ] Moving down the rows lights each one under the cursor, full width, and
      the highlight leaves when the mouse leaves the grid
- [ ] Group headers do NOT highlight — they are not rows you read across
- [ ] Widen the window, switch to the Export tab — the string fills the new
      width rather than wrapping at the old one, and Ctrl+C still acknowledges
- [ ] Resize while the Import tab has disenchant rows on it, then go back —
      nothing has been taint-broken and the buttons still work
- [ ] Page the columns with `>` while a tooltip is up, then hover the same
      screen position — it describes the NEW character, not the old one
- [ ] A character whose lockout expired while you were logged out shows a blank
      cell there, not last week's `2/8`
- [ ] After pasting a `wbc1!` string, the `from warband.pro` rows fill in for
      the characters it covered and stay blank for the ones it did not

### The currency rows (unreleased)

The filter is the one thing here that HIDES something, so the checks are mostly
about it hiding the right rows and being findable when it hides the wrong ones.
Bring a character carrying at least one retired currency — Timewarped Badges do
for most accounts.

- [ ] The currency group is shorter than it was, and what is left is this
      season's: crests, valorstones, coffer key shards, whatever is capped
- [ ] The group header reads `currencies · N hidden` and N matches what went
      missing
- [ ] Options → **Show every currency in the Roster grid** — the hidden rows
      come back on the spot, without a `/reload`, and the header goes back to
      plain `currencies`
- [ ] Turn it off again — they go away again, and the count is the same as
      before
- [ ] A currency you are at the cap of is RED, and its hover says "at cap —
      anything more is lost"
- [ ] One near but not at its cap is ORANGE; one well under it is plain white
- [ ] A currency whose weekly allowance you have already earned is ORANGE, and
      its hover's "this week" fraction reads the same on both sides
- [ ] The colour a currency reads in the grid matches the minimap hover's
      `at cap` line — the same currency is never red in one and orange in the
      other
- [ ] `/reload` on a character with no currencies read at all — the group is
      absent rather than an empty header

### The cooldown rows (unreleased)

**The read is the untestable half** — `C_TradeSkillUI` only answers while a
profession window is open, so nothing in CI reaches it and this checklist is the
whole of the evidence. Bring a character with a profession that has a cooldown;
an alchemist is easiest, and a second profession on the same character makes the
merge check possible.

- [ ] Open the profession window on a character with a cooldown *running*. Close
      it, `/warband roster` — a `cooldowns` group under `professions`, one row
      named after the recipe, cell showing the time left
- [ ] Hover it — the profession name, `ready in`, and the charge count if it is
      a charge cooldown
- [ ] A charge-based cooldown (an alchemy transmute with a charge in hand) reads
      as `2/3` in green, **not** as the countdown
- [ ] Spend every charge — the same cell falls back to the countdown
- [ ] A character who has never opened a profession window has an EMPTY cell in
      that row, never `ready`
- [ ] Wait one out (or bring an alt whose cooldown lapsed days ago) — the cell
      reads `ready` in green, and the hover says `ready since`
- [ ] **The merge:** with an Alchemy cooldown already stored, open Blacksmithing
      on the same character. The Alchemy row is still there afterwards, with the
      same time left — opening one profession must not forget the other
- [ ] `/warband status` — `professionCooldown` is its own age in the section
      list, and it is OLDER than `profession` on a character who has logged in
      since last opening a profession window
- [ ] `/warband copy` on that character — the bundle carries
      `professionCooldowns` with an absolute `readyTime`, and no `remainingSec`
- [ ] A warband where nobody has a cooldown gets no `cooldowns` group at all,
      not an empty header

### The Options tab at its shortest (unreleased)

- [ ] Drag the window as short as it will go, then open Options — the fifth
      checkbox and its description clear the version line at the bottom
- [ ] A window left at the old 420 minimum by an earlier build opens at 460
      rather than off-screen or unresizable

## The trading post (unreleased)

**This section settles the API names, and nothing else in this repo can.**
`tools/freshness-test.lua` covers the bookkeeping either side of the read —
that each field survives a pass that could not see it, that the month rides
with the shelf, that an unread section is absent rather than empty — against a
fake client. What it cannot check is whether `C_PerksProgram`,
`C_PerksActivities` and `C_DateAndTime` answer at all, because those names were
read off Blizzard's UI rather than from anything runnable here. Every call goes
through `ns.safe`, so a wrong name costs this one section silently — which is
exactly why it needs a person to look.

Run this **before the first release that carries it**, and note the month: the
shelf only exists once the trading post has been opened in the current one.

- [ ] Log in without visiting the trading post. `/warband` → the string
      contains `"tradingPost"` with a `tender` number and **no** `items` — a
      balance with no shelf is the correct reading here, not a failure
- [ ] The tender number matches the one in the game's own currency panel
      (Trader's Tender, currency 2032)
- [ ] Open the trading post, then `/warband` again. `items` is now present and
      its length matches the number of things on the shelf
- [ ] `month` reads as the current `YYYY-MM` **on realm time** — check this
      near a month boundary if you can, because a player east of their realm is
      the case it exists for
- [ ] An item you have already bought this month carries `"purchased":true`;
      one you have not carries no `purchased` key at all
- [ ] `items[].itemID` is the item you end up owning, not the shelf entry —
      spot-check one against the item's id on Wowhead. This is the id
      warband.pro joins to your collection, so a wrong one silently reports a
      mount you own as missing
- [ ] Open the Traveler's Log. `activities` appears, with `completed` present
      only on the ones that are done
- [ ] Buy something. The tender balance in the next string has gone down by the
      price, and `purchased` is now on that item
- [ ] **If any of the above is missing entirely**, the API name is wrong rather
      than the logic. Check `Scan.TradingPost` against the current client's
      globals before assuming the section is broken — `/warband debug` reports
      `ns.errorCount`, and `ns.safe` swallowing a missing global shows up there
      as nothing at all, which is the trap

## Housing decor (unreleased)

**The same job as the section above, and it matters more here.** `C_HousingCatalog`
and its searcher object were read off Blizzard's UI, not off anything this repo
can run, and this section is the only one on the wire with **no Battle.net
fallback at all**: if these names are wrong, warband.pro cannot show decor
completion by any other route. `tools/freshness-test.lua` covers the bookkeeping
against a fake client — that an empty read is refused, that two variants of one
item count once, that an unnamed entry is counted rather than dropped, that both
the synchronous and the callback path write. What it cannot check is whether the
client answers at all.

- [ ] Log in without opening the housing catalog. `/warband` → the string has
      **no** `"decor"` key. An absent section is the correct reading here, not a
      failure — the addon refuses to write an empty read
- [ ] Open the housing catalog, wait for it to finish loading, then `/warband`
      again. `decor.owned` is present and is a list of numbers
- [ ] `#decor.owned` is in the right neighbourhood of what the catalog's own
      "collected" filter shows. It will not match exactly — variants collapse to
      one item and `unmatched` holds the rest — but an order of magnitude out
      means the searcher's filters are not doing what this reads them as
- [ ] `decor.owned` holds **item ids, not catalog entry ids.** Spot-check one
      against the decor's item on Wowhead. This is the id warband.pro joins to
      its catalog, so a wrong one reports decor you own as missing — the same
      trap as `items[].itemID` above, and the reason both are checked by hand
- [ ] The list is ascending and has no duplicates
- [ ] If `unmatched` is present, it is a plausible small number rather than the
      whole collection. `unmatched` equal to the catalog size means
      `GetCatalogEntryInfo` is not resolving the ids the searcher returns, and
      the variant fallback is not covering it either
- [ ] Redeem or destroy a decor, reopen the catalog, `/warband` again — the list
      has moved by one. This is what proves the read is live rather than a
      cached list from the first open
- [ ] Copy a bundle on one character, log to another, `/warband` — `decor` is
      still there with the same list. It is account-wide and must not follow the
      character who looked
- [ ] **If the whole section is missing after opening the catalog**, the API
      names are wrong rather than the logic. `/warband debug` reports
      `ns.errorCount`; a missing global shows up there as nothing at all, which
      is the trap. Check `Scan.Decor` against the current client's globals

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
