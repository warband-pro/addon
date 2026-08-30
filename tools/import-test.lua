-- Off-client tests for Import.lua.
--
-- Import.lua is the only file in this addon that reads a string somebody else
-- produced, which makes it the only one where being wrong is a security
-- question rather than a display bug. It is also pure — no frames, no WoW API
-- beyond ns.safe — so it can be tested on a laptop, and it is the half of the
-- wbc1! contract that can be.
--
--   lua5.1 tools/import-test.lua   (5.1 is what WoW runs; 5.4 works too)
--
-- `node tools/vector.mjs --write` must have run first: this reads the golden
-- fixture it produces and the inflated JSON beside it, so a drift on either
-- side of the wire fails here rather than in someone's bags.

package.path = "./?.lua;" .. package.path

local DIR = "docs/contract/vectors/"

-- The namespace comes from the shipped Init.lua rather than being restated
-- here. It used to be restated, and that masked a real defect: this fixture
-- defined ns.CLEANUP_WIRE while no shipped file did, so the decoder passed
-- every test and errored on the first real paste. A fixture that restates the
-- contract cannot catch the shipped file failing to meet it. Inflate is still
-- not re-implemented — the harness reads the already-inflated JSON that Node
-- wrote, so what is under test is our base64url, our JSON and our validation.
-- Init.lua keeps a pre-set ns.LibDeflate, so the stub goes in first.
local ns = {}
local inflated = nil
ns.LibDeflate = {
  DecompressDeflate = function(_, _)
    return inflated
  end,
}
assert(loadfile("Init.lua"))("WarbandPro", ns)   -- WoW's `local _, ns = ...`
assert(loadfile("Import.lua"))("WarbandPro", ns)
local Import = ns.Import

local pass, fail = 0, 0
local function check(label, cond, extra)
  if cond then
    pass = pass + 1
    print("PASS " .. label)
  else
    fail = fail + 1
    print("FAIL " .. label .. (extra ~= nil and ("  " .. tostring(extra)) or ""))
  end
end

local function readAll(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local TAB = string.char(9)

-- ── base64url ───────────────────────────────────────────────────────────────
-- Every length mod 3, so all three tail branches are exercised.
local B64 = {
  { raw = "A", enc = "QQ" },
  { raw = "hi", enc = "aGk" },
  { raw = "abc", enc = "YWJj" },
  { raw = "abcd", enc = "YWJjZA" },
  { raw = "the quick brown fox", enc = "dGhlIHF1aWNrIGJyb3duIGZveA" },
  -- The two characters that make it base64URL rather than base64: byte 255
  -- and byte 254 encode to a payload carrying `_` and `-`.
  { raw = string.char(255, 239, 190), enc = "_---" },
}
for _, v in ipairs(B64) do
  check("base64url " .. v.enc, Import.Base64URLDecode(v.enc) == v.raw, Import.Base64URLDecode(v.enc))
end
check("base64url rejects a foreign character", Import.Base64URLDecode("ab*d") == nil)
check("base64url rejects standard-alphabet + and /", Import.Base64URLDecode("ab+/") == nil)
check("base64url rejects padding", Import.Base64URLDecode("YWJj=") == nil)
check("base64url rejects an impossible length", Import.Base64URLDecode("abcde") == nil)
check("base64url on empty is empty", Import.Base64URLDecode("") == "")

-- ── JSON ────────────────────────────────────────────────────────────────────
local v, err = Import.JSONDecode('{"a":1,"b":[1,2,3],"c":"x\\ny","d":true,"e":null}')
check(
  "json decodes what Bundle.JSON emits",
  type(v) == "table" and v.a == 1 and #v.b == 3 and v.c == "x\ny" and v.d == true and v.e == false,
  err
)
check("json negative and float", (Import.JSONDecode('{"a":-2.5}') or {}).a == -2.5)
check("json nested", ((Import.JSONDecode('{"a":{"b":[{"c":7}]}}') or {}).a or {}).b[1].c == 7)
check("json unicode escape", Import.JSONDecode('"\\u00e9"') == string.char(195, 169))
check("json empty array", type(Import.JSONDecode("[]")) == "table")
-- Strictness. Each of these is a shape a lenient parser would wave through,
-- and a decoder that shrugs at the tail accepts two payloads concatenated.
check("json rejects trailing garbage", Import.JSONDecode('{"a":1} junk') == nil)
check("json rejects an unterminated string", Import.JSONDecode('{"a":"x') == nil)
check("json rejects a raw control character", Import.JSONDecode('{"a":"x' .. TAB .. 'y"}') == nil)
check("json rejects a missing colon", Import.JSONDecode('{"a" 1}') == nil)
check("json rejects a trailing comma", Import.JSONDecode('{"a":1,}') == nil)
check("json rejects an unquoted key", Import.JSONDecode("{a:1}") == nil)
check("json rejects a bad escape", Import.JSONDecode('"\\q"') == nil)
check("json rejects a short unicode escape", Import.JSONDecode('"\\u00"') == nil)
check("json rejects the empty string", Import.JSONDecode("") == nil)
check(
  "json rejects nesting past the depth cap",
  Import.JSONDecode(string.rep("[", 40) .. string.rep("]", 40)) == nil
)

-- ── the golden vector, end to end ───────────────────────────────────────────
local goldenJson = readAll(DIR .. "wbc1-min.json")
local goldenWire = readAll(DIR .. "wbc1-min.wbc1")
if not goldenJson or not goldenWire then
  print("FAIL golden fixtures missing — run `node tools/vector.mjs --write` first")
  os.exit(1)
end
-- The .json beside the .wbc1 is the same payload the encoder compressed, so
-- handing it back is exactly what a real inflate would return.
inflated = goldenJson
local out, code = Import.DecodePlan((goldenWire:gsub("%s+$", "")))
check("golden vector decodes", out ~= nil, code)
if out then
  check("golden generatedAt is seconds", out.generatedAt == 1724000000, out.generatedAt)
  check("golden character count", out.nJunk == 1, out.nJunk)
  local c = out.chars["Player-1-TEST"]
  check("golden is keyed by guid", c ~= nil and c.name == "Vocnar")
  check("golden carries both items", c and #c.junk == 2, c and #c.junk)
  if c then
    local byS = {}
    for _, it in ipairs(c.junk) do
      byS[it.s] = it
    end
    local unusable = byS["item:221151::::::::80:250::4:6:12053:1:28:::"]
    local gap = byS["item:215135::::::::80:250::4:6:12053:1:28:::"]
    check(
      "golden unusable verdict has no gap",
      unusable ~= nil and unusable.k == "de" and unusable.r == "unusable" and unusable.g == nil
    )
    check(
      "golden gap verdict carries its numbers",
      gap ~= nil and gap.k == "de" and gap.r == "gap" and gap.g == 56 and gap.ilvl == 570
    )
  end
end

-- ── rejections ──────────────────────────────────────────────────────────────
-- Each code is a different sentence in the panel, so each is asserted by name
-- rather than by "it returned nil".
local function codeFor(input)
  local _, c = Import.DecodePlan(input)
  return c
end

inflated = nil
check("rejects empty", codeFor("") == "empty")
check("rejects whitespace only", codeFor("   ") == "empty")
-- The one that matters most: an export string is VALID, just not here.
check("names an export string rather than calling it broken", codeFor("wb1!AAAA") == "is_export")
check("names an equip string rather than calling it broken", codeFor("wbg1!AAAA") == "is_gearset")
check("rejects a foreign prefix", codeFor("nope") == "wrong_prefix")
check("rejects an oversize input before inflating it", codeFor("wbc1!" .. string.rep("A", 41 * 1024)) == "too_large")
check("rejects a body that is not base64url", codeFor("wbc1!***") == "not_base64")
check("rejects a body that will not inflate", codeFor("wbc1!AAAA") == "not_deflate")

inflated = "not json at all"
check("rejects a payload that is not json", codeFor("wbc1!AAAA") == "not_json")
inflated = '{"v":2,"generatedAt":1,"chars":[]}'
check("rejects a future version", codeFor("wbc1!AAAA") == "wrong_version")
inflated = '{"v":1,"chars":[]}'
check("rejects a payload with no generatedAt", codeFor("wbc1!AAAA") == "not_json")
inflated = '{"v":1,"generatedAt":1,"chars":[]}'
check("rejects an empty list", codeFor("wbc1!AAAA") == "no_items")
inflated = '{"v":1,"generatedAt":1,"chars":[{"guid":"G","items":[{"k":"sell"}]}]}'
check("drops an item carrying no item string", codeFor("wbc1!AAAA") == "no_items")
inflated = '{"v":1,"generatedAt":1,"chars":[{"guid":"G","items":[{"k":"vaporise","s":"item:1"}]}]}'
check("drops an unknown verdict", codeFor("wbc1!AAAA") == "no_items")
inflated = '{"v":1,"generatedAt":1,"chars":[{"name":"X","items":[{"k":"sell","s":"item:1"}]}]}'
check("drops a character with no guid to match on", codeFor("wbc1!AAAA") == "no_items")

-- A good item alongside a bad one keeps the good one: one malformed row must
-- not cost the whole list.
inflated = '{"v":1,"generatedAt":9,"chars":[{"guid":"G","name":"N","items":[{"k":"sell"},{"k":"de","s":"item:2"}]}]}'
local partial = Import.DecodePlan("wbc1!AAAA")
check("keeps the good item beside a malformed one", partial ~= nil and #partial.chars["G"].junk == 1)

check("every code has a message", (function()
  for _, c in ipairs({
    "empty", "is_export", "wrong_prefix", "too_large", "not_base64",
    "not_deflate", "not_json", "wrong_version", "no_items",
  }) do
    local m = Import.Message(c)
    if type(m) ~= "string" or m == "" or m == "that string could not be read" then return false end
  end
  return true
end)())

-- ── the one string: three sections on wbc1! ─────────────────────────────────
-- Added 1.11.0. `items` is the clear-out list as it always was; `gear` nests
-- the equip setups (nested, because `items` at the character level was already
-- taken); `builds` says which saved talent build is for which kind of night.

local function plan(json)
  inflated = json
  return Import.DecodePlan("wbc1!AAAA")
end

local GEAR = '"gear":{"spec":103,"set":"warband.pro Feral",' ..
  '"items":[{"slot":1,"s":"item:9","id":9}],' ..
  '"sets":[{"spec":103,"set":"warband.pro Feral","items":[{"slot":1,"s":"item:9"}]},' ..
  '{"spec":105,"set":"warband.pro Rest","items":[{"slot":1,"s":"item:8"}]}]}'
local BUILDS = '"builds":[{"spec":103,"raid":7,"mplus":8,"delve":9}]'
local JUNK = '"items":[{"k":"sell","s":"item:1"}]'

local all = plan('{"v":1,"generatedAt":9,"chars":[{"guid":"G","name":"N",' ..
  JUNK .. ',' .. GEAR .. ',' .. BUILDS .. '}]}')
check("one string carries all three sections", all ~= nil and
  all.nJunk == 1 and all.nSets == 1 and all.nBuilds == 1,
  all and (all.nJunk .. "/" .. all.nSets .. "/" .. all.nBuilds))
if all then
  local c = all.chars["G"]
  check("the clear-out list is under junk", c and c.junk and #c.junk == 1)
  check("the equip list is under gear, not items", c and c.gear and #c.gear.items == 1)
  check("setups are keyed by spec", c and c.gear.bySpec and c.gear.bySpec[105] ~= nil)
  check("the legacy spec and name ride along for a downgrade",
    c and c.gear.spec == 103 and c.gear.set == "warband.pro Feral", c and c.gear.set)
  check("builds are keyed by spec then content",
    c and c.builds and c.builds[103] and c.builds[103].raid == 7 and c.builds[103].delve == 9)
end

-- The case the cleanup-only reader could not express: it required `items` and
-- dropped every character without one.
local gearOnly = plan('{"v":1,"generatedAt":9,"chars":[{"guid":"G","name":"N",' .. GEAR .. '}]}')
check("a character with setups and nothing to sell is kept", gearOnly ~= nil and
  gearOnly.nSets == 1 and gearOnly.nJunk == 0)
check("that character carries no junk section at all",
  gearOnly ~= nil and gearOnly.chars["G"].junk == nil)

local buildsOnly = plan('{"v":1,"generatedAt":9,"chars":[{"guid":"G",' .. BUILDS .. '}]}')
check("builds alone are enough to keep a character", buildsOnly ~= nil and buildsOnly.nBuilds == 1)

check("a string empty of all three is still no_items", (function()
  inflated = '{"v":1,"generatedAt":9,"chars":[{"guid":"G","name":"N"}]}'
  local _, c = Import.DecodePlan("wbc1!AAAA")
  return c == "no_items"
end)())

-- Absent is not empty, in both directions — this is what stops a paste
-- carrying only gear from deleting a clear-out list the player still wants.
check("an absent section reads as nil, never as an empty table", (function()
  local p = plan('{"v":1,"generatedAt":9,"chars":[{"guid":"G",' .. JUNK .. '}]}')
  local c = p and p.chars["G"]
  return c ~= nil and c.junk ~= nil and c.gear == nil and c.builds == nil
end)())

check("a spec naming no content at all is not stored as an empty assignment", (function()
  local p = plan('{"v":1,"generatedAt":9,"chars":[{"guid":"G",' .. JUNK ..
    ',"builds":[{"spec":103}]}]}')
  return p ~= nil and p.nBuilds == 0 and p.chars["G"].builds == nil
end)())

check("a build for an unknown content key is ignored", (function()
  local p = plan('{"v":1,"generatedAt":9,"chars":[{"guid":"G",' .. JUNK ..
    ',"builds":[{"spec":103,"pvp":4}]}]}')
  return p ~= nil and p.nBuilds == 0
end)())

check("a setup with no spec is dropped rather than guessed at", (function()
  local p = plan('{"v":1,"generatedAt":9,"chars":[{"guid":"G","gear":{"sets":' ..
    '[{"set":"x","items":[{"slot":1,"s":"item:9"}]}]}}]}')
  return p == nil
end)())

check("a gear section with neither items nor sets is nothing", (function()
  local p = plan('{"v":1,"generatedAt":9,"chars":[{"guid":"G",' .. JUNK .. ',"gear":{"spec":103}}]}')
  return p ~= nil and p.nSets == 0 and p.chars["G"].gear == nil
end)())

-- ── DecodeInbound: one entry point, two wires ───────────────────────────────

check("DecodeInbound reads the current string", (function()
  inflated = '{"v":1,"generatedAt":9,"chars":[{"guid":"G",' .. JUNK .. '}]}'
  local p, why, kind = Import.DecodeInbound("wbc1!AAAA")
  return p ~= nil and why == nil and kind == "plan"
end)())

-- The equip-only string the site sent before 1.11.0, normalised into the same
-- shape so the panel has one code path rather than two that must agree.
check("DecodeInbound normalises a legacy equip string", (function()
  inflated = '{"v":1,"generatedAt":9,"chars":[{"guid":"G","name":"N",' ..
    '"items":[{"slot":1,"s":"item:9"}]}]}'
  local p, _, kind = Import.DecodeInbound("wbg1!AAAA")
  return p ~= nil and kind == "gearset" and p.nSets == 1 and p.nJunk == 0
    and p.chars["G"].gear ~= nil and #p.chars["G"].gear.items == 1
    and p.chars["G"].junk == nil
end)())

-- Only for the codes the equip wire words differently — the shared failures
-- deliberately fall through to one table so the two cannot drift.
check("a legacy rejection still reads in that wire's own words", (function()
  local _, why, kind = Import.DecodeInbound("wbg1!" .. string.rep("A", 41 * 1024))
  return why == "too_large" and kind == "gearset"
    and Import.InboundMessage(why, kind) ~= Import.Message(why)
end)())

check("a shared failure reads the same on both wires, by design", (function()
  local _, why, kind = Import.DecodeInbound("wbg1!***")
  return why == "not_base64" and Import.InboundMessage(why, kind) == Import.Message(why)
end)())

check("DecodeInbound still names an export string rather than calling it broken", (function()
  local _, why = Import.DecodeInbound("wb1!AAAA")
  return why == "is_export"
end)())

print("")
print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
