# Distribution policy compliance

CurseForge's [moderation policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies)
contain no WoW-specific section, but they do contain this: *"CurseForge follows
game developers EULA and ToS, and so should your projects."* For a WoW addon
that makes **Blizzard's Addon Development Policy the binding document**, and it
is the stricter of the two. Wago and WoWInterface defer to the same policy, so
one pass covers all three sites.

Each rule below is either enforced by `tools/validate.mjs` — meaning CI fails
before a violation can ship — or listed as a standing constraint with the reason
it currently holds.

## Blizzard's addon policy

| Rule | Status | How |
| --- | --- | --- |
| Addons must be free of charge | ✅ | MIT licensed, no paid tier, no gated features. |
| Addon code must be completely visible | ✅ **enforced** | No minification (fails on any line over 2000 bytes), and no `loadstring` / `load` / `RunScript` anywhere in the zip, `Vendor/` included. Plain Lua, no packed blobs. |
| Addons may not include advertisements | ✅ **enforced** | No promotional strings in shipped Lua. `warband.pro` appears in game only in functional strings — the window title, paste instructions, and the import decoder's rejection sentences — none clickable, none promotional. |
| Addons may not solicit donations | ✅ **enforced** | Fails on `donate`/`donation` and on Patreon / Ko-fi / PayPal / Buy Me a Coffee / Boosty in shipped Lua. |
| Must not negatively impact realms or other players | ✅ | No network transmission at all — `SendAddonMessage`, `SendChatMessage`, and `BNSendGameData` fail the build. No `OnUpdate` scanner; captures are event-driven and throttled. |
| No offensive or objectionable material | ✅ | None. |
| Must abide by the WoW ToU and EULA | ✅ | Reads only the logged-in player's own client-side data through public APIs, and writes it to that player's clipboard on an explicit keypress. |

The export model has long precedent: SimulationCraft's `/simc`, WeakAuras import
strings, and Details! all hand the player an encoded string to paste elsewhere.
Nothing here transmits — the player is the transport.

## CurseForge moderation policies

| Rule | Status | Notes |
| --- | --- | --- |
| Clear, informative description; functional detail, not generic terms | ⚠️ **manual** | Paste [STORE.md](STORE.md). Do **not** paste the repo README — it is written for contributors and contains development planning. |
| Clear summary, not duplicating the description | ⚠️ **manual** | Summary line is at the top of [STORE.md](STORE.md). |
| Name and description in English | ✅ | Both English. |
| Name excludes versions and technical detail | ✅ **enforced** | Fails if `## Title:` grows a version number. Project name: "Warband.pro Companion". |
| Project avatar, 400×400, not a solid colour, no copyrighted imagery | ❌ **to do** | See the warning below — this one has a trap in it. |
| Distinct assets, name, and description | ✅ | Original addon, not a fork. |
| Third-party content credited and correctly licensed | ✅ | LibDeflate by Haoqian He, zlib license — notice retained in `Vendor/LibDeflate.lua`, credited in `LICENSE` and in the store description. |
| No external download links | ⚠️ **manual** | The store description links the GitHub **repository** (source visibility, which Blizzard's policy effectively requires) and nothing else. Never link a Releases page, a zip, or a CI artifact from a CurseForge description. |
| Promotional links at the bottom, reasonable size | ✅ | The warband.pro link sits in a closing section. Mentions inside the description are functional — the addon is a companion to that site, so describing it is not promoting it. |
| No file updates purely for visibility | ✅ | Releases are tagged deliberately; CI artifacts go to GitHub, never to a distribution site. |
| AI-generated showcase images need a visible disclaimer | ⚠️ **if applicable** | Only if AI imagery is used for screenshots or the avatar. A real screenshot of the panel needs no disclaimer. |

## The avatar trap

`WarbandPro.toc` sets `IconTexture: Interface\Icons\INV_Misc_Bag_10`. That is
correct and normal — it references a texture already in the player's client for
the addon compartment button, and ships no artwork.

**Do not use that icon, or any other Blizzard art, as the CurseForge project
avatar.** An avatar is an image *you upload*, and re-uploading Blizzard's icon
art is exactly the "copyrighted imagery" the avatar rule prohibits. The needed
asset is an original 400×400 image, and this repo does not contain one yet.

## Things only a human can do

Nothing in CI can reach the project page. Before the first release:

1. Upload an original 400×400 avatar (see above).
2. Paste [STORE.md](STORE.md) as the description, and its first line as the summary.
3. Set the project license to MIT to match `LICENSE`.
4. Take a screenshot of the `/warband` panel — the description references it, and
   a real in-game image needs no AI disclaimer.
5. Add the project ids to `WarbandPro.toc` once each project exists.

## When this needs rereading

Any change that adds a URL to the in-game UI, adds a clickable link, adds a
"support the project" anything, or adds a build step that transforms Lua. The
first three are caught by `tools/validate.mjs`; the fourth is not, because a
build step that minifies would look like a legitimate tool right up until a
moderator opened the zip.
