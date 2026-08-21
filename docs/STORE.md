# Store description

Paste this as the CurseForge / Wago / WoWInterface project description. The
first block is the **Summary** field; everything under the rule is the
**Description**. Written to satisfy the moderation rules mapped in
[POLICY.md](POLICY.md) — in particular: functional detail rather than generic
claims, English, third-party code credited, no external download links, and the
website link kept to a closing section.

Do not substitute the repo README. That one is written for contributors and
carries development planning a moderator would (fairly) read as unfinished.

---

## Summary

> Snapshots what each of your characters actually holds — bags, banks, warband
> bank, gear, talents, gold, currencies, lockouts, and vault progress — and
> copies all of them to your clipboard as one string.

---

## Description

### What it does

Warband.pro Companion records a snapshot of each character as you play, and
gives you every one of them back as a single copyable string.

Log in on a character and the addon quietly stores what that character has. Log
in on another and it stores that one too. Nothing is asked of you while you
play. When you want the data, type `/warband`, press Ctrl+C, and you have all of
them at once — not one export per character.

### What it records

For every character you log in on:

- **Identity** — name, realm, faction, class, level, XP and rested XP, guild,
  last zone, hearthstone location, average item level
- **Money and storage** — gold, every bag slot, personal bank, reagent bank,
  warband bank contents, mail (item count, pending gold, soonest expiry), and
  active auction count
- **Currencies** — quantity, cap, and weekly cap for each, so crest and
  flightstone limits are visible at a glance
- **Gear** — equipped items plus anything in a bag or bank that could be
  equipped, as the same item string SimulationCraft's own addon exports —
  bonus IDs, enchant, gems, crafted stats, item level, all included
- **Talents** — the active spec's talent loadout string, and every spec you
  have played on that character
- **Professions** — profession, current skill, and cap
- **Lockouts** — saved instances by difficulty, per-boss kill state, reset
  times, and world boss kills
- **Mythic+ and the vault** — owned keystone, runs, rating, and weekly vault
  progress against each threshold
- **Consumable rollup** — phials, health and combat potions, feasts, and weapon
  runes, counted across bags and bank

Every section carries its own timestamp, so you can tell a fresh bag count from
a bank you have not opened in a week rather than trusting all of it equally.

### How to use it

1. Play normally. Snapshots happen on their own.
2. Type `/warband` on any character.
3. The panel opens with the string already selected. Press Ctrl+C.
4. Paste it wherever you want it.

Commands:

| Command | What it does |
| --- | --- |
| `/warband` | Open the panel with every character's data ready to copy |
| `/warband copy current` | Copy this character only |
| `/warband status` | Character count, size, per-section ages, and any API failures |
| `/warband clear <name>` | Remove a character from the database |
| `/warband optimize` | Drop characters not seen in 90 days |
| `/warband gear on` \| `off` | Toggle whether gear is included in the copied string — captured data is kept either way |

### What it does not do

This matters more than the feature list, so it is stated plainly:

- **It never transmits anything.** The addon makes no network requests of any
  kind. It cannot — the code contains no messaging calls at all, and the build
  fails if one is ever added. You copy a string and decide where it goes.
- **It never uploads automatically.** There is no background sync, no account,
  no login, and no telemetry. Nothing leaves your client unless you press
  Ctrl+C and paste it somewhere yourself.
- **It only ever reads your own characters.** No other players, no guild bank,
  no chat logs.
- **It does not scan on a timer.** Captures are driven by game events and
  throttled, so it does not cost you frames.

### Performance

Saved data stays under roughly 200 KB for six characters — smaller than most
alt-tracking addons, because mounts, pets, toys, achievements, and full recipe
lists are deliberately not recorded. No `OnUpdate` handler runs.

### Requirements

Retail only, current patch. No dependencies — nothing else to install.

### Source code

Full source: <https://github.com/warband-pro/addon>

The addon is plain, readable Lua with no obfuscation or minification of any
kind. Every release is built from a tagged commit by an automated pipeline, so
what you download matches what is in that repository.

### Credits and license

Uses [LibDeflate](https://github.com/SafeteeWoW/LibDeflate) by Haoqian He, used
under the zlib license, with its notice retained in the source.

The addon itself is released under the MIT license.

### About warband.pro

This addon is the in-game companion to <https://warband.pro>, a planning site
that answers "who should I play tonight". The site reads what the Battle.net API
exposes; the addon supplies what it cannot see — where your items actually are,
what you are out of, and which lockouts are still open.

The addon is fully standalone. The string it copies is yours to paste anywhere,
and using the website is optional.
