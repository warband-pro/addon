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
