-- Behavioural tests for PB's FurnitureEditor.
--
-- The add-on runs on a console, where one real test costs a whole session: build, upload, boot
-- the PS5, log in, walk to a house. harness.lua stubs the part of the client the add-on touches
-- -- houses, links, bags, the editor's request-then-event rhythm -- so the logic can be exercised
-- here instead. What it cannot say is whether the console behaves like the stub; that is what
-- /pbfe probe is for.
--
--   luajit test/run.lua        (from the add-on folder; any Lua 5.1+)

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."
VERBOSE = os.getenv("VERBOSE") ~= nil
dofile(HERE .. "/harness.lua")

local failures, total = 0, 0
local function check(label, got, want)
	total = total + 1
	local ok = got == want
	if not ok then failures = failures + 1 end
	print(string.format("%s %-64s got=%s want=%s", ok and "PASS" or "FAIL", label, tostring(got), tostring(want)))
end

local function near(label, got, want, tolerance)
	total = total + 1
	local ok = got ~= nil and math.abs(got - want) <= (tolerance or 0.5)
	if not ok then failures = failures + 1 end
	print(string.format("%s %-64s got=%s want=%s", ok and "PASS" or "FAIL", label, tostring(got), tostring(want)))
end

local function section(title) print("\n== " .. title .. " ==") end

-- ---------------------------------------------------------------------------------------
-- A house to copy from: a table with two candles on it, a vase on one candle (a tilted one),
-- a bookshelf with a book, and furniture that is not linked at all.
-- ---------------------------------------------------------------------------------------

local TABLE, CANDLE, VASE, CHAIR, SHELF, BOOK, DECOR = 10, 20, 30, 40, 50, 60, 70

local function BuildWorld(opts)
	opts = opts or {}
	ResetWorld()
	if opts.trueConv then World.trueConv = opts.trueConv end

	AddHouse(1)
	local table_ = AddFurniture(1, { dataId = TABLE, name = "Redguard Table", x = 1000, y = 100, z = 2000, yaw = 0.5 })
	local candleA = AddFurniture(1, { dataId = CANDLE, name = "Candle", x = 1050, y = 120, z = 2010, yaw = 1.0, parent = table_ })
	AddFurniture(1, { dataId = CANDLE, name = "Candle", x = 950, y = 120, z = 1990, yaw = -0.7, parent = table_ })
	AddFurniture(1, { dataId = VASE, name = "Vase", x = 1050, y = 160, z = 2010, pitch = 0.3, yaw = 0.2, roll = 0.1, parent = candleA })
	AddFurniture(1, { dataId = CHAIR, name = "Chair", x = 3000, y = 0, z = 3000, yaw = 2.0 })
	local shelf = AddFurniture(1, { dataId = SHELF, name = "Bookshelf", x = -500, y = 0, z = 200, yaw = 0.3 })
	AddFurniture(1, { dataId = BOOK, name = "Book", x = -500, y = 150, z = 200, yaw = 1.2, parent = shelf })
	-- enough tilted pieces for the calibrator to tell the rotation orders apart
	AddFurniture(1, { dataId = DECOR, name = "Leaning A", x = 2000, y = 10, z = 100, pitch = 0.4, yaw = 0.9, roll = 0.2 })
	AddFurniture(1, { dataId = DECOR, name = "Leaning B", x = 2200, y = 10, z = 300, pitch = -0.3, yaw = 2.1, roll = 0.5 })
	AddFurniture(1, { dataId = DECOR, name = "Leaning C", x = 2400, y = 10, z = 500, pitch = 0.6, yaw = -1.3, roll = -0.4 })
	AddFurniture(1, { dataId = DECOR, name = "Leaning D", x = 2600, y = 10, z = 700, pitch = -0.5, yaw = 1.7, roll = 0.3 })

	AddHouse(2, opts.house2)

	-- what is in the bags for the second house
	GiveItem(BAG_BACKPACK, 0, TABLE, 1, "Redguard Table")
	GiveItem(BAG_BACKPACK, 1, CANDLE, 2, "Candle")
	GiveItem(BAG_BACKPACK, 2, VASE, 1, "Vase")
	GiveItem(BAG_BACKPACK, 3, SHELF, 1, "Bookshelf")
	GiveItem(BAG_BACKPACK, 4, BOOK, 1, "Book")

	EnterHouse(1)
	World.player = { x = 1100, y = 100, z = 2100, rot = 1.0 }

	local addon = LoadAddon()
	ChatClear()
	return addon
end

-- the way a player copies: look at the list, then name a number from it
local function CopyGroup(n)
	Cmd("/pbfe list")
	Cmd("/pbfe copy " .. tostring(n or 1))
end

local function HouseFurniture(houseId)
	local list = {}
	for _, f in pairs(World.houses[houseId].furniture) do list[#list + 1] = f end
	table.sort(list, function(a, b) return a.n < b.n end)
	return list
end

local function CountOf(houseId) return #HouseFurniture(houseId) end

local function FindByData(houseId, dataId)
	local out = {}
	for _, f in ipairs(HouseFurniture(houseId)) do
		if f.dataId == dataId then out[#out + 1] = f end
	end
	return out
end

-- ---------------------------------------------------------------------------------------
section("1. load")
-- ---------------------------------------------------------------------------------------
local addon = BuildWorld()
check("add-on table exists", type(addon), "table")
check("slash command registered", type(SLASH_COMMANDS["/pbfe"]), "function")
check("long slash command registered", type(SLASH_COMMANDS["/pbfurnitureeditor"]), "function")
check("no events held while idle", HandlerCount(EVENT_HOUSING_FURNITURE_PLACED), 0)

Cmd("/pbfe help")
check("help lists copy", ChatHas("/pbfe copy"), true)
check("help lists paste", ChatHas("/pbfe paste"), true)
check("help lists probe", ChatHas("/pbfe probe"), true)
ChatClear()
Cmd("/pbfe nonsense")
check("unknown command says so", ChatHas("unknown: nonsense"), true)

-- ---------------------------------------------------------------------------------------
section("2. result names")
-- ---------------------------------------------------------------------------------------
check("21 is INCORRECT_MODE", addon.ResultName(21), "INCORRECT_MODE")
check("0 is SUCCESS", addon.ResultName(0), "SUCCESS")
check("unknown number is shown as such", addon.ResultName(9999), "?9999")
check("ResultText includes the game's own string", addon.ResultText(21):find("SI_HOUSINGREQUESTRESULT", 1, true) ~= nil, true)
check("command result 0", addon.CommandResultName(0), "SUCCESS")
check("mode name", addon.ModeName(HOUSING_EDITOR_MODE_SELECTION), "SELECTION")

-- ---------------------------------------------------------------------------------------
section("3. ids are not compared with ==")
-- ---------------------------------------------------------------------------------------
local idA, idB = StringToId64("F5"), StringToId64("F5")
check("two ids for one furnishing differ under ==", idA == idB, false)
check("IdKey agrees", addon.IdKey(idA), addon.IdKey(idB))
check("SameId agrees", addon.SameId(idA, idB), true)
check("IsNoId on zero", addon.IsNoId(StringToId64("F0")), true)
check("IsNoId on nil", addon.IsNoId(nil), true)
check("IsNoId on a real id", addon.IsNoId(idA), false)

-- ---------------------------------------------------------------------------------------
section("4. api check")
-- ---------------------------------------------------------------------------------------
Cmd("/pbfe api")
check("everything exists in the stub", ChatHas("everything this add-on calls exists and is public"), true)
ChatClear()
World.private["HousingEditorRequestSetFurnitureParent"] = true
Cmd("/pbfe api")
check("a private function is named", ChatHas("private: HousingEditorRequestSetFurnitureParent"), true)
World.private = {}

-- ---------------------------------------------------------------------------------------
section("5. reading the house")
-- ---------------------------------------------------------------------------------------
ChatClear()
Cmd("/pbfe list")
check("two groups found", ChatHas("2 groups"), true)
check("the table group has 4 items", ChatHas("4 items"), true)
check("the shelf group has 2 items", ChatHas("2 items"), true)
check("6 furnishings are linked", ChatHas("6 of them linked"), true)
local firstGroupAt = ChatText():find("#1  4 items", 1, true)
check("nearest group is listed first", firstGroupAt ~= nil, true)

local house = addon:ReadHouse()
check("all 11 furnishings read", #house.list, 11)
check("no link disagreements", house.inconsistent, 0)

-- ---------------------------------------------------------------------------------------
section("6. copy")
-- ---------------------------------------------------------------------------------------
ChatClear()
Cmd("/pbfe copy")
check("copy with no argument asks", ChatHas("say which"), true)
Cmd("/pbfe copy 9")
check("a number that is not listed is refused", ChatHas("no group #9"), true)
Cmd("/pbfe copy 1")
local clip = addon.sv.clip
check("clipboard has the group", clip ~= nil and #clip.nodes, 4)
check("clipboard remembers the house", clip.houseId, 1)
check("anchor is where the player stood", clip.anchor.x, 1100)
check("root has no parent", clip.nodes[1].parent, nil)
local ordered = true
for i, node in ipairs(clip.nodes) do
	if node.parent and node.parent >= i then ordered = false end
end
check("every parent comes before its child", ordered, true)
local vaseNode
for _, node in ipairs(clip.nodes) do if node.dataId == VASE then vaseNode = node end end
check("the vase hangs off a candle", clip.nodes[vaseNode.parent].dataId, CANDLE)
check("the candle hangs off the table", clip.nodes[clip.nodes[vaseNode.parent].parent].dataId, TABLE)
check("tilt is kept", math.abs(vaseNode.pitch - 0.3) < 1e-9, true)

Cmd("/pbfe copy all")
check("copy all takes both groups", #addon.sv.clip.nodes, 6)
Cmd("/pbfe copy near")
check("copy near takes the nearest", #addon.sv.clip.nodes, 4)

-- ---------------------------------------------------------------------------------------
section("7. who may copy")
-- ---------------------------------------------------------------------------------------
BuildWorld({ house2 = { owner = false, editor = false } })
EnterHouse(2)
ChatClear()
Cmd("/pbfe list")
check("a visitor cannot copy", ChatHas("you can only copy from a house you can edit"), true)
ChatClear()
EnterHouse(0)
Cmd("/pbfe list")
check("outside a house it says so", ChatHas("you are not in a house"), true)

-- ---------------------------------------------------------------------------------------
section("8. paste: dry run")
-- ---------------------------------------------------------------------------------------
addon = BuildWorld()
CopyGroup(1)
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
ChatClear()
Cmd("/pbfe paste")
check("plan is printed", ChatHas("plan: here"), true)
check("it is ready", ChatHas("ready. to place: /pbfe paste go"), true)
check("nothing was placed", CountOf(2), 0)
check("no placement was requested", #CallsTo("HousingEditorRequestItemPlacement"), 0)
check("the shift is the player's move", ChatHas("x 39.0 m"), true)

-- ---------------------------------------------------------------------------------------
section("9. paste: the whole thing")
-- ---------------------------------------------------------------------------------------
ChatClear()
Cmd("/pbfe paste go")
RunUntilIdle()
check("the run is over", addon.run, nil)
check("four furnishings in the new house", CountOf(2), 4)
check("summary says placed 4 / 4", ChatHas("placed 4 / 4"), true)
check("summary says linked 3 / 3", ChatHas("linked 3 / 3"), true)
check("the table is used up", ItemCount(TABLE), 0)
check("the editor was put in selection mode", World.mode, HOUSING_EDITOR_MODE_SELECTION)
check("mode negotiation was reported", ChatHas("editor mode -> SELECTION"), true)

local newTable = FindByData(2, TABLE)[1]
near("table x moved by the player's shift", newTable.x, 1000 + (5000 - 1100), 0)
near("table y moved by the player's shift", newTable.y, 100 + (0 - 100), 0)
near("table z moved by the player's shift", newTable.z, 2000 + (5000 - 2100), 0)
near("table yaw is kept", newTable.yaw, 0.5, 1e-9)

local newVase = FindByData(2, VASE)[1]
near("vase pitch is kept", newVase.pitch, 0.3, 1e-9)
near("vase roll is kept", newVase.roll, 0.1, 1e-9)
local vaseParent = World.houses[2].furniture[newVase.parent]
check("the vase hangs off a candle again", vaseParent and vaseParent.dataId, CANDLE)
local candleParent = World.houses[2].furniture[vaseParent.parent]
check("the candle hangs off the table again", candleParent and candleParent.dataId, TABLE)
check("both candles are linked", #(function()
	local n = {}
	for _, c in ipairs(FindByData(2, CANDLE)) do if c.parent then n[#n + 1] = c end end
	return n
end)(), 2)
check("what was placed is recorded for undo", #addon.sv.lastPaste.keys, 4)
check("events are released afterwards", HandlerCount(EVENT_HOUSING_FURNITURE_PLACED), 0)
check("no timers left", PendingTimers(), 0)

-- ---------------------------------------------------------------------------------------
section("10. undo")
-- ---------------------------------------------------------------------------------------
ChatClear()
Cmd("/pbfe undo")
RunUntilIdle()
check("the house is empty again", CountOf(2), 0)
check("the items came back", ItemCount(TABLE), 1)
check("two candles came back", ItemCount(CANDLE), 2)
check("undo reports", ChatHas("took back 4 / 4"), true)
check("the record is cleared", addon.sv.lastPaste, nil)
ChatClear()
Cmd("/pbfe undo")
check("a second undo has nothing to do", ChatHas("nothing recorded"), true)

-- ---------------------------------------------------------------------------------------
section("11. paste: what is missing")
-- ---------------------------------------------------------------------------------------
addon = BuildWorld()
CopyGroup(1)
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.bags[BAG_BACKPACK][2] = nil    -- no vase
ChatClear()
Cmd("/pbfe paste")
check("the shortage is named", ChatHas("short: Vase  need 1, have 0"), true)
check("it is not ready", ChatHas("not ready"), true)
Cmd("/pbfe paste go")
RunUntilIdle()
check("a short paste places nothing", CountOf(2), 0)
check("and says why", ChatHas("refusing"), true)

ChatClear()
Cmd("/pbfe paste force go")
RunUntilIdle()
check("force places what there is", CountOf(2), 3)
check("the vase is not there", #FindByData(2, VASE), 0)
check("the two candles are still linked", ChatHas("linked 2 / 2"), true)

-- an item in a bank counts
addon = BuildWorld()
CopyGroup(1)
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.bags[BAG_BACKPACK][2] = nil
GiveItem(BAG_BANK, 5, VASE, 1, "Vase")
ChatClear()
Cmd("/pbfe paste go")
RunUntilIdle()
check("a vase in the bank is used", #FindByData(2, VASE), 1)
check("all four placed", CountOf(2), 4)
local placedFromBank = false
for _, c in ipairs(CallsTo("HousingEditorRequestItemPlacement")) do
	if c[1] == BAG_BANK then placedFromBank = true end
end
check("the bank slot was named in the request", placedFromBank, true)

-- stolen items are not used
addon = BuildWorld()
CopyGroup(1)
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.bags[BAG_BACKPACK][2].stolen = true
ChatClear()
Cmd("/pbfe paste")
check("a stolen vase does not count", ChatHas("short: Vase"), true)

-- ---------------------------------------------------------------------------------------
section("12. the server misbehaves")
-- ---------------------------------------------------------------------------------------
-- A paste empties the clipboard, so a test that pastes twice loads the copy it saved here ("/pbfe load t").
local function Fresh()
	local a = BuildWorld()
	CopyGroup(1)
	Cmd("/pbfe save t")
	EnterHouse(2)
	World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
	ChatClear()
	return a
end

-- busy server: "in progress" is asked again
addon = Fresh()
World.cooldown = 600
addon.sv.paceMs = 100
Cmd("/pbfe paste go")
RunUntilIdle()
check("a busy server still gets everything placed", CountOf(2), 4)
check("it asked more than once per furnishing", #CallsTo("HousingEditorRequestItemPlacement") > 4, true)
check("and linked them", ChatHas("linked 3 / 3"), true)

-- no placed event: found by looking
addon = Fresh()
World.silent[EVENT_HOUSING_FURNITURE_PLACED] = true
Cmd("/pbfe paste go")
RunUntilIdle()
check("without the event, the furnishings are found anyway", CountOf(2), 4)
check("and linked", ChatHas("linked 3 / 3"), true)

-- a private placement call
addon = Fresh()
World.private["HousingEditorRequestItemPlacement"] = true
Cmd("/pbfe paste go")
RunUntilIdle()
check("a private placement call stops the run", addon.run, nil)
check("with the client's words", ChatHas("the placement call was refused"), true)
check("nothing was placed", CountOf(2), 0)
check("no timers are left running", PendingTimers(), 0)

-- a private link call
addon = Fresh()
World.private["HousingEditorRequestSetFurnitureParent"] = true
Cmd("/pbfe paste go")
RunUntilIdle()
check("furnishings are placed even if linking is refused", CountOf(2), 4)
check("the run ends", addon.run, nil)
check("with the link refusal named", ChatHas("the link call was refused"), true)
check("and undo is possible", #addon.sv.lastPaste.keys, 4)

-- links answered with a refusal
addon = Fresh()
World.linkRefusal = RESULT_LINK_FAILED or HOUSING_REQUEST_RESULT_LINK_FAILED
Cmd("/pbfe paste go")
RunUntilIdle()
check("every refused link is listed", ChatHas("link #2 Candle"), true)
check("none were linked", ChatHas("linked 0 / 3"), true)
check("the placements stand", CountOf(2), 4)

-- landed off its mark
addon = Fresh()
World.snap = 7
Cmd("/pbfe paste go")
RunUntilIdle()
check("drift is noticed", ChatHas("landed 7 cm"), true)
check("a nudge was sent for each", #CallsTo("HousingEditorRequestChangePositionAndOrientation") >= 4, true)
local tableAfter = FindByData(2, TABLE)[1]
near("the table ends up on its mark", tableAfter.x, 1000 + (5000 - 1100), 0)

-- out of combat, in combat
addon = Fresh()
World.houses[2].owner = false
Cmd("/pbfe paste")
check("only the owner may place", ChatHas("you can only place furnishings in a house you own"), true)

-- limits
addon = Fresh()
World.houses[2].limits[2] = 3
Cmd("/pbfe paste")
check("a house limit is reported", ChatHas("room for 3, need 4"), true)
Cmd("/pbfe paste go")
RunUntilIdle()
check("and refuses", CountOf(2), 0)

-- placement refused in every mode
addon = Fresh()
World.requiredMode = 99
Cmd("/pbfe paste go")
RunUntilIdle()
check("a mode nothing satisfies ends the run", ChatHas("refused in every editor mode"), true)
check("without placing", CountOf(2), 0)

-- a stale refusal arrives while a placement is in flight: the placement still happens
addon = Fresh()
World.mode = HOUSING_EDITOR_MODE_SELECTION    -- so the first request is accepted and is in flight at 180 ms
Cmd("/pbfe paste go")
RunFor(180)
Fire(EVENT_HOUSING_EDITOR_REQUEST_RESULT, HOUSING_REQUEST_RESULT_PLACE_FAILED)
RunUntilIdle()
check("a misread answer does not lose a furnishing from the undo record", #addon.sv.lastPaste.keys, CountOf(2))
check("it says so", ChatHas("answered after they were given up on"), true)
Cmd("/pbfe undo")
RunUntilIdle()
check("undo takes back even the misread one", CountOf(2), 0)

-- a second paste says the first can no longer be undone
addon = Fresh()
Cmd("/pbfe paste go")
RunUntilIdle()
GiveItem(BAG_BACKPACK, 20, TABLE, 1)
GiveItem(BAG_BACKPACK, 21, CANDLE, 2)
GiveItem(BAG_BACKPACK, 22, VASE, 1)
Cmd("/pbfe load t")
ChatClear()
Cmd("/pbfe paste go")
RunUntilIdle()
check("an older paste's loss of undo is announced", ChatHas("can no longer be undone"), true)

-- stop mid-run
addon = Fresh()
Cmd("/pbfe paste go")
RunFor(900)
Cmd("/pbfe stop")
check("stop waits for the furnishing in flight", ChatHas("stopping after the furnishing in flight"), true)
RunUntilIdle()
local placedAtStop = CountOf(2)
check("stop ends the run", addon.run, nil)
check("fewer than all were placed", placedAtStop < 4 and placedAtStop >= 1, true)
check("everything that was placed is recorded for undo", #addon.sv.lastPaste.keys, placedAtStop)
RunFor(20000)
check("nothing more is placed after stop", CountOf(2), placedAtStop)
check("events are released after stop", HandlerCount(EVENT_HOUSING_FURNITURE_PLACED), 0)

-- stopping with nothing in flight is immediate
addon = Fresh()
Cmd("/pbfe paste go")
RunFor(10)
Cmd("/pbfe stop")
check("an early stop ends the run at once", addon.run, nil)

-- and undo takes the stopped paste back
addon = Fresh()
Cmd("/pbfe paste go")
RunFor(900)
Cmd("/pbfe stop")
RunUntilIdle()
Cmd("/pbfe undo")
RunUntilIdle()
check("undo after stop empties the house", CountOf(2), 0)

-- ---------------------------------------------------------------------------------------
section("13. geometry")
-- ---------------------------------------------------------------------------------------
local geo = addon.geo
local x, z = geo.RotateOffset(1, math.pi / 2, 1, 0)
near("a quarter turn takes x to -z", z, -1, 1e-9)
near("and leaves x at 0", x, 0, 1e-9)
local x2, z2 = geo.RotateOffset(-1, math.pi / 2, 1, 0)
near("the other sign turns the other way", z2, 1, 1e-9)

local m = geo.EulerMatrix(0.3, 1.1, -0.4, { order = "YXZ", sp = 1, sy = 1, sr = 1 })
local det = m[1] * (m[5] * m[9] - m[6] * m[8]) - m[2] * (m[4] * m[9] - m[6] * m[7]) + m[3] * (m[4] * m[8] - m[5] * m[7])
near("an orientation matrix has determinant 1", det, 1, 1e-9)

check("a flat piece can turn with a known sign", geo.CanTurn({ sy = 1 }, 0, 0), true)
check("a tilted piece cannot when yaw is not outermost", geo.CanTurn({ sy = 1, yawOuter = false }, 0.3, 0), false)
check("a tilted piece can when yaw is outermost", geo.CanTurn({ sy = 1, yawOuter = true }, 0.3, 0), true)
check("nothing turns without a sign", geo.CanTurn({}, 0, 0), false)
check("angles wrap", math.abs(geo.NormalizeAngle(3 * math.pi) - math.pi) < 1e-9 or math.abs(geo.NormalizeAngle(3 * math.pi) + math.pi) < 1e-9, true)

-- ---------------------------------------------------------------------------------------
section("14. calibration")
-- ---------------------------------------------------------------------------------------
local function CalibrateIn(conv)
	local a = BuildWorld({ trueConv = conv })
	ChatClear()
	Cmd("/pbfe calib")
	return a, a.sv.convention
end

local a1, c1 = CalibrateIn({ order = "YXZ", sp = 1, sy = 1, sr = 1 })
check("YXZ+ is recognised: sign", c1 and c1.sy, 1)
check("YXZ+ is recognised: yaw is applied last", c1 and c1.yawOuter, true)

local a2, c2 = CalibrateIn({ order = "YXZ", sp = 1, sy = -1, sr = 1 })
check("a negative yaw sign is recognised", c2 and c2.sy, -1)
check("and yaw is still applied last", c2 and c2.yawOuter, true)

local a3, c3 = CalibrateIn({ order = "XYZ", sp = 1, sy = 1, sr = 1 })
check("XYZ: sign", c3 and c3.sy, 1)
check("XYZ: yaw is not applied last", c3 and c3.yawOuter, false)

local a4, c4 = CalibrateIn({ order = "ZXY", sp = -1, sy = -1, sr = 1 })
check("ZXY: sign", c4 and c4.sy, -1)
check("ZXY: yaw is not applied last", c4 and c4.yawOuter, false)

-- a house with nothing turned says so instead of guessing
ResetWorld()
AddHouse(1)
AddFurniture(1, { dataId = 1, name = "Plain", x = 0, y = 0, z = 0 })
EnterHouse(1)
local a5 = LoadAddon()
ChatClear()
Cmd("/pbfe calib")
check("too little to go on is said, not guessed", ChatHas("not enough to decide"), true)
check("and nothing is saved", a5.sv.convention, nil)

-- ---------------------------------------------------------------------------------------
section("15. paste with rotation")
-- ---------------------------------------------------------------------------------------
addon = Fresh()
Cmd("/pbfe paste rot 90")
check("rot without calibration is refused", ChatHas("rot needs /pbfe calib first"), true)
Cmd("/pbfe paste rot 90 force go")
RunUntilIdle()
check("not even force places an uncalibrated turn", CountOf(2), 0)

addon = BuildWorld({ trueConv = { order = "YXZ", sp = 1, sy = 1, sr = 1 } })
Cmd("/pbfe calib")
check("calibrated", addon.sv.convention and addon.sv.convention.sy, 1)
CopyGroup(1)
local srcAnchor = addon.sv.clip.anchor
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
ChatClear()
Cmd("/pbfe paste rot 90 go")
RunUntilIdle()
check("a turned paste places everything", CountOf(2), 4)
local rotTable = FindByData(2, TABLE)[1]
local ex, ez = geo.RotateOffset(1, math.rad(90), 1000 - srcAnchor.x, 2000 - srcAnchor.z)
near("the table is carried round the anchor: x", rotTable.x, 5000 + ex, 1)
near("the table is carried round the anchor: z", rotTable.z, 5000 + ez, 1)
near("the table's yaw gains a quarter turn", geo.NormalizeAngle(rotTable.yaw - 0.5), math.pi / 2, 1e-6)
local rotVase = FindByData(2, VASE)[1]
near("a tilted piece keeps its pitch when yaw is outermost", rotVase.pitch, 0.3, 1e-9)
near("and its roll", rotVase.roll, 0.1, 1e-9)
check("links survive the turn", rotVase.parent ~= nil, true)

-- a client whose yaw is not outermost: tilted pieces are not turned
addon = BuildWorld({ trueConv = { order = "XYZ", sp = 1, sy = 1, sr = 1 } })
Cmd("/pbfe calib")
CopyGroup(1)
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
ChatClear()
Cmd("/pbfe paste rot 90")
check("a tilted piece that cannot be turned is reported", ChatHas("tilted pieces cannot be turned"), true)
Cmd("/pbfe paste rot 90 go")
RunUntilIdle()
check("it is refused without force", CountOf(2), 0)
Cmd("/pbfe paste rot 90 force go")
RunUntilIdle()
check("with force the flat pieces are turned and placed", CountOf(2), 3)
check("the tilted vase is left behind", #FindByData(2, VASE), 0)

-- same coordinates
addon = BuildWorld()
CopyGroup(1)
EnterHouse(2)
World.player = { x = 9, y = 9, z = 9, rot = 0 }
ChatClear()
Cmd("/pbfe paste same go")
RunUntilIdle()
local sameTable = FindByData(2, TABLE)[1]
near("same keeps the coordinates: x", sameTable.x, 1000, 0)
near("same keeps the coordinates: z", sameTable.z, 2000, 0)

-- up
addon = BuildWorld()
CopyGroup(1)
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
Cmd("/pbfe paste up 25 go")
RunUntilIdle()
near("up raises the group", FindByData(2, TABLE)[1].y, 25, 0)

-- ---------------------------------------------------------------------------------------
section("16. collectibles")
-- ---------------------------------------------------------------------------------------
ResetWorld()
AddHouse(1)
AddHouse(2)
local base = AddFurniture(1, { dataId = 100, name = "Crown Stand", x = 0, y = 0, z = 0, collectibleId = 555 })
AddFurniture(1, { dataId = 101, name = "Ornament", x = 10, y = 50, z = 0, parent = base })
GiveItem(BAG_BACKPACK, 0, 101, 1, "Ornament")
EnterHouse(1)
World.player = { x = 0, y = 0, z = 0, rot = 0 }
addon = LoadAddon()
Cmd("/pbfe copy near")
Cmd("/pbfe save stand")
EnterHouse(2)
World.player = { x = 100, y = 0, z = 100, rot = 0 }
ChatClear()
Cmd("/pbfe paste go")
RunUntilIdle()
local collectibleCalls = CallsTo("HousingEditorRequestCollectiblePlacement")
check("a collectible is placed without an item", #collectibleCalls >= 1, true)
check("it is placed by its collectible id", collectibleCalls[#collectibleCalls][1], 555)
check("both furnishings are there", CountOf(2), 2)
check("and linked", ChatHas("linked 1 / 1"), true)
Cmd("/pbfe load stand")
ChatClear()
Cmd("/pbfe paste")
check("a collectible already placed here is flagged, and left to the server", ChatHas("is already placed here"), true)

-- a collectible the player does not have is treated like an item that is short
ResetWorld()
AddHouse(1)
AddHouse(2)
local stand = AddFurniture(1, { dataId = 100, name = "Crown Stand", x = 0, y = 0, z = 0, collectibleId = 555 })
AddFurniture(1, { dataId = 101, name = "Ornament", x = 10, y = 50, z = 0, parent = stand })
GiveItem(BAG_BACKPACK, 0, 101, 1, "Ornament")
World.cannotPlace = { [555] = true }
EnterHouse(1)
World.player = { x = 0, y = 0, z = 0, rot = 0 }
addon = LoadAddon()
CopyGroup(1)
EnterHouse(2)
World.player = { x = 100, y = 0, z = 100, rot = 0 }
ChatClear()
Cmd("/pbfe paste")
check("an unowned collectible is named in the plan", ChatHas("skip: Crown Stand (collectible unavailable)"), true)
check("and the plan is not ready", ChatHas("not ready"), true)
Cmd("/pbfe paste go")
RunUntilIdle()
check("go is refused without force", CountOf(2), 0)
ChatClear()
Cmd("/pbfe paste force go")
RunUntilIdle()
check("with force the rest is placed", CountOf(2), 1)
check("the item whose parent was skipped is placed", #FindByData(2, 101), 1)
check("but not linked to anything", FindByData(2, 101)[1].parent, nil)
check("the lost link is reported", ChatHas("loses its parent and will not be linked"), true)

-- ---------------------------------------------------------------------------------------
section("17. states")
-- ---------------------------------------------------------------------------------------
ResetWorld()
AddHouse(1)
AddHouse(2)
local lamp = AddFurniture(1, { dataId = 200, name = "Lamp", x = 0, y = 0, z = 0, state = 1, numStates = 2 })
AddFurniture(1, { dataId = 201, name = "Shade", x = 0, y = 30, z = 0, parent = lamp })
GiveItem(BAG_BACKPACK, 0, 200, 1, "Lamp")
GiveItem(BAG_BACKPACK, 1, 201, 1, "Shade")
EnterHouse(1)
addon = LoadAddon()
Cmd("/pbfe copy near")
EnterHouse(2)
Cmd("/pbfe paste go")
RunUntilIdle()
check("a lamp that was on is switched on", FindByData(2, 200)[1].state, 1)
check("the state change was requested", #CallsTo("HousingEditorRequestChangeState"), 1)

-- ---------------------------------------------------------------------------------------
section("18. the clipboard survives")
-- ---------------------------------------------------------------------------------------
addon = BuildWorld()
CopyGroup(1)
Cmd("/pbfe save table")
Cmd("/pbfe clear")
check("clear empties the clipboard", addon.sv.clip, nil)
ChatClear()
Cmd("/pbfe saved")
check("saved lists the name", ChatHas("table: 4 furnishings"), true)
Cmd("/pbfe load table")
check("load brings it back", #addon.sv.clip.nodes, 4)
Cmd("/pbfe drop table")
check("drop forgets it", addon.sv.library.table, nil)
ChatClear()
Cmd("/pbfe show")
check("show describes the clipboard", ChatHas("clipboard: 4 furnishings"), true)
ChatClear()
Cmd("/pbfe load table")
check("loading a name that is gone says so", ChatHas("nothing saved under that name"), true)

-- "reload the UI": a new add-on table, the same saved variables
local before = #addon.sv.clip.nodes
local reloaded = LoadAddon()
check("the clipboard survives a reload", #reloaded.sv.clip.nodes, before)

-- ---------------------------------------------------------------------------------------
section("19. probes")
-- ---------------------------------------------------------------------------------------
addon = BuildWorld()
EnterHouse(2)
World.player = { x = 100, y = 0, z = 100, rot = 0 }
GiveItem(BAG_BACKPACK, 10, 300, 2, "Test Cup")

ChatClear()
Cmd("/pbfe items")
check("items lists the biggest stack first", ChatText():find("slot 10  x2  Test Cup", 1, true) ~= nil, true)

ChatClear()
Cmd("/pbfe probe place 10")
RunUntilIdle()
check("probe place works", ChatHas("PLACE WORKS"), true)
check("it cleans up after itself", CountOf(2), 0)
check("the item is back", ItemCount(300), 2)
check("events were counted", ChatHas("PLACED x1"), true)
check("no run left behind", addon.run, nil)
check("events released", HandlerCount(EVENT_HOUSING_FURNITURE_PLACED), 0)

ChatClear()
World.silent[EVENT_HOUSING_FURNITURE_PLACED] = true
Cmd("/pbfe probe place 10")
RunUntilIdle()
check("probe place works even without the placed event", ChatHas("PLACE WORKS"), true)
World.silent = {}

ChatClear()
World.private["HousingEditorRequestItemPlacement"] = true
Cmd("/pbfe probe place 10")
RunUntilIdle()
check("a private placement is reported by the probe", ChatHas("PLACE FAILED: call refused"), true)
World.private = {}

ChatClear()
Cmd("/pbfe probe place 10 keep")
RunUntilIdle()
check("keep leaves it in the house", CountOf(2), 1)
World.houses[2].furniture = {}
GiveItem(BAG_BACKPACK, 10, 300, 2, "Test Cup")

ChatClear()
Cmd("/pbfe probe place 99")
check("an empty slot is refused", ChatHas("nothing in bag"), true)

ChatClear()
Cmd("/pbfe probe link 10")
RunUntilIdle()
check("probe link works", ChatHas("LINK WORKS"), true)
check("the child followed the parent", ChatHas("child moved 50 cm"), true)
check("both are taken away again", CountOf(2), 0)
check("both items are back", ItemCount(300), 2)

ChatClear()
World.linkRefusal = HOUSING_REQUEST_RESULT_LINK_FAILED
Cmd("/pbfe probe link " .. tostring(SlotOf(BAG_BACKPACK, 300)))
RunUntilIdle()
check("a refused link is reported", ChatHas("LINK REFUSED"), true)
check("and both are still cleaned up", CountOf(2), 0)
World.linkRefusal = nil

ChatClear()
GiveItem(BAG_BACKPACK, 11, 301, 1, "Lone Cup")
Cmd("/pbfe probe link 11")
check("link needs two of an item", ChatHas("needs two of the same item"), true)

ChatClear()
Cmd("/pbfe probe place " .. tostring(SlotOf(BAG_BACKPACK, 300)))
Cmd("/pbfe stop")
RunUntilIdle()
check("stop ends a probe", addon.run, nil)

ChatClear()
Cmd("/pbfe state")
check("state reports the house", ChatHas("house 2"), true)
check("state reports the clipboard", ChatHas("clipboard: empty"), true)
Cmd("/pbfe where")
check("where prints the position", ChatHas("in house: x 100"), true)
Cmd("/pbfe speed 300")
check("speed is stored", addon.sv.paceMs, 300)
Cmd("/pbfe speed 5")
check("an absurd speed is refused", addon.sv.paceMs, 300)

-- ---------------------------------------------------------------------------------------
section("20. houses, and pasting into one you are not in")
-- ---------------------------------------------------------------------------------------
local function FromHouse1()
	local a = BuildWorld({ house2 = { name = "Seaside Cottage", nickname = "Beach" } })
	AddHouse(3, { name = "Locked Manor", unlocked = false })
	CopyGroup(1)
	ChatClear()
	return a
end

addon = FromHouse1()
Cmd("/pbfe houses")
check("two owned houses are listed", ChatHas("2 houses"), true)
check("a house that is not owned is not listed", ChatHas("Locked Manor"), false)
check("a nickname is shown beside the name", ChatHas("Seaside Cottage (Beach)"), true)
check("the house you are in is marked", ChatHas("<- you are here"), true)
check("the numbering follows the house id, whatever order the client lists them in",
	ChatText():find("#1  House 1", 1, true) ~= nil and ChatText():find("#2  Seaside Cottage", 1, true) ~= nil, true)
check("the primary residence is marked", ChatHas("primary"), true)

-- a dry run, there
addon = FromHouse1()
Cmd("/pbfe paste to 2")
check("the jump was requested for the second house", CallsTo("RequestJumpToHouse")[1][1], 2)
check("inside, unless told otherwise", CallsTo("RequestJumpToHouse")[1][2], false)
check("the trip is announced", ChatHas("travelling to Seaside Cottage (Beach)"), true)
check("nothing has moved yet", World.houseId, 1)
check("the command is waiting for the player to arrive", addon.jump ~= nil, true)
RunUntilIdle()
check("we are in the other house", World.houseId, 2)
check("arrival is announced", ChatHas("arrived at Seaside Cottage"), true)
check("the plan is shown on arrival", ChatHas("plan: here"), true)
check("it waited for the house to load (ownership was read after loading)",
	ChatHas("you can only place furnishings in a house you own"), false)
check("a dry run places nothing", CountOf(2), 0)
check("the trip is finished", addon.jump, nil)

-- the whole thing, with original coordinates
addon = FromHouse1()
Cmd("/pbfe paste to 2 same go")
RunUntilIdle()
check("'to 2 same go' places the group", CountOf(2), 4)
near("at its original coordinates", FindByData(2, TABLE)[1].x, 1000, 0)
check("and links it", ChatHas("linked 3 / 3"), true)
check("the undo record is for the house it went to", addon.sv.lastPaste.houseId, 2)

-- "here" has no meaning at the doorway
addon = FromHouse1()
Cmd("/pbfe paste to 2 go")
RunUntilIdle()
check("'here ... go' after a jump is shown, not done", CountOf(2), 0)
check("and says why", ChatHas("you arrive at the doorway"), true)
check("the plan is still printed", ChatHas("plan: here"), true)

-- rot and up are carried across the jump
addon = BuildWorld({ trueConv = { order = "YXZ", sp = 1, sy = 1, sr = 1 } })
Cmd("/pbfe calib")
CopyGroup(1)
ChatClear()
Cmd("/pbfe paste to 2 same rot 90 up 10 go")
RunUntilIdle()
check("rot and up survive the trip", CountOf(2), 4)
near("up was applied", FindByData(2, TABLE)[1].y, 110, 0)
near("rot was applied", geo.NormalizeAngle(FindByData(2, TABLE)[1].yaw - 0.5), math.pi / 2, 1e-6)

-- outside
addon = FromHouse1()
Cmd("/pbfe paste to 2 outside")
check("outside is passed to the jump", CallsTo("RequestJumpToHouse")[1][2], true)
check("and announced", ChatHas("(outside)"), true)
RunUntilIdle()

-- bad numbers, refusals
addon = FromHouse1()
Cmd("/pbfe paste to 9")
check("a house number that does not exist", ChatHas("no house #9"), true)
Cmd("/pbfe paste to")
check("'to' with no number", ChatHas("to needs a house number"), true)
check("no jump was made", #CallsTo("RequestJumpToHouse"), 0)

addon = FromHouse1()
World.private["RequestJumpToHouse"] = true
Cmd("/pbfe paste to 2 same go")
check("a private jump is reported", ChatHas("the jump was refused"), true)
check("and leaves no trip behind", addon.jump, nil)

addon = FromHouse1()
World.canJump = false
Cmd("/pbfe paste to 2")
check("a location that cannot jump says so, in the client's words", ChatHas("Cannot travel to house from this location."), true)
check("and does not try", #CallsTo("RequestJumpToHouse"), 0)

addon = FromHouse1()
Cmd("/pbfe clear")
ChatClear()
Cmd("/pbfe paste to 2")
check("an empty clipboard is caught before travelling", ChatHas("the clipboard is empty"), true)
check("and nothing is requested", #CallsTo("RequestJumpToHouse"), 0)

-- already there
addon = FromHouse1()
Cmd("/pbfe paste to 1")
check("already in the house: no jump", #CallsTo("RequestJumpToHouse"), 0)
check("it says so", ChatHas("you are already in House 1"), true)
check("and shows the plan", ChatHas("plan: here"), true)

-- a second trip while one is going
addon = FromHouse1()
Cmd("/pbfe paste to 2 same go")
Cmd("/pbfe paste to 2 same go")
check("two trips at once are refused", ChatHas("already under way"), true)
check("only one jump was made", #CallsTo("RequestJumpToHouse"), 1)
RunUntilIdle()
check("and the paste ran once", CountOf(2), 4)

-- stop while travelling
addon = FromHouse1()
Cmd("/pbfe paste to 2 same go")
RunFor(500)
Cmd("/pbfe stop")
check("stop cancels the trip", ChatHas("the trip is cancelled"), true)
RunUntilIdle()
check("the player still arrives", World.houseId, 2)
check("but nothing is placed", CountOf(2), 0)

-- never arrives
addon = FromHouse1()
World.jumpNever = true
Cmd("/pbfe paste to 2 same go")
RunUntilIdle()
check("a trip that never ends is dropped", addon.jump, nil)
check("with a message", ChatHas("never arrived at Seaside Cottage"), true)
check("and nothing was placed", CountOf(2), 0)

-- the player leaves before it starts
addon = FromHouse1()
Cmd("/pbfe paste to 2 same go")
RunFor(3500)
check("arrived and waiting", addon.jump ~= nil and addon.jump.arrived, true)
EnterHouse(1)
RunUntilIdle()
check("leaving during the wait stops the paste", CountOf(2), 0)

-- ---------------------------------------------------------------------------------------
section("21. cut and paste (a move)")
-- ---------------------------------------------------------------------------------------
-- A house with a table, two candles, a vase on one of them, and a chair that is not linked.
-- The bags are EMPTY: whatever is in them afterwards came out of the house.
local function CutWorld()
	ResetWorld()
	AddHouse(1, { name = "Home" })
	AddHouse(2, { name = "Cottage" })
	local tbl = AddFurniture(1, { dataId = TABLE, name = "Redguard Table", x = 1000, y = 100, z = 2000, yaw = 0.5 })
	local ca = AddFurniture(1, { dataId = CANDLE, name = "Candle", x = 1050, y = 120, z = 2010, yaw = 1.0, parent = tbl })
	AddFurniture(1, { dataId = CANDLE, name = "Candle", x = 950, y = 120, z = 1990, yaw = -0.7, parent = tbl })
	AddFurniture(1, { dataId = VASE, name = "Vase", x = 1050, y = 160, z = 2010, pitch = 0.3, yaw = 0.2, roll = 0.1, parent = ca })
	AddFurniture(1, { dataId = CHAIR, name = "Chair", x = 3000, y = 0, z = 3000, yaw = 2.0 })
	EnterHouse(1)
	World.player = { x = 1100, y = 100, z = 2100, rot = 1.0 }
	World.noStackInfo = true          -- the item link does not say whether it stacks: the cut has to estimate
	local a = LoadAddon()
	Cmd("/pbfe list")
	ChatClear()
	return a
end

local function BagsEmpty()
	return ItemCount(TABLE) + ItemCount(CANDLE) + ItemCount(VASE) + ItemCount(CHAIR)
end

-- the preview changes nothing
addon = CutWorld()
Cmd("/pbfe cut 1")
check("a cut without go shows what it would do", ChatHas("cut: 4 furnishings (4 items, 0 collectibles) leave this house"), true)
check("it names the bag and its room, as a range for kinds it has not seen", ChatHas("they go to your backpack: 40 free slots, 3 needed (up to 4 if the 3 kinds not yet seen do not stack)"), true)
check("it says nothing has been removed", ChatHas("nothing has been removed. to do it: /pbfe cut 1 go"), true)
check("the house is untouched", CountOf(1), 5)
check("and so is the clipboard", addon.sv.clip, nil)
check("nothing was requested", #CallsTo("HousingEditorRequestRemoveFurniture"), 0)

-- the cut
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("the run is over", addon.run, nil)
check("the group is out of the house", CountOf(1), 1)
check("only the chair is left", FindByData(1, CHAIR)[1] ~= nil, true)
check("the table is in the bag", ItemCount(TABLE), 1)
check("both candles are in the bag", ItemCount(CANDLE), 2)
check("the vase is in the bag", ItemCount(VASE), 1)
check("the clipboard holds the whole group", #addon.sv.clip.nodes, 4)
check("and is marked as a cut", addon.sv.clip.cut, true)
check("every piece remembers where it stood", addon.sv.clip.nodes[1].srcKey ~= nil, true)
check("the summary says so", ChatHas("took out 4 / 4"), true)
check("and where to go next", ChatHas("all of it is in your backpack"), true)
check("and how to undo it", ChatHas("/pbfe paste same go (in this house)"), true)
check("events are released", HandlerCount(EVENT_HOUSING_FURNITURE_REMOVED), 0)

-- the clipboard is not thrown away by accident
ChatClear()
Cmd("/pbfe list")
Cmd("/pbfe copy 1")
check("copy will not replace a pending cut", ChatHas("holds a cut that has not been pasted"), true)
Cmd("/pbfe load nothing")
Cmd("/pbfe clear")
check("clear will not either", addon.sv.clip ~= nil and addon.sv.clip.cut, true)
Cmd("/pbfe cut near")
check("nor will cut", addon.sv.clip.cut, true)
Cmd("/pbfe show")
check("show says it is a cut", ChatHas("this is a CUT"), true)

-- the move: paste it into the other house
Cmd("/pbfe paste to 2 same go")
RunUntilIdle()
check("the group arrives in the other house", CountOf(2), 4)
check("linked as before", ChatHas("linked 3 / 3"), true)
near("at its coordinates", FindByData(2, TABLE)[1].x, 1000, 0)
check("the bags are empty again", BagsEmpty(), 0)
check("the move is declared complete", ChatHas("the move is complete"), true)
check("and the clipboard is emptied: the move is over", addon.sv.clip, nil)
check("it says so", ChatHas("the clipboard is emptied"), true)
check("the chair stayed behind", CountOf(1), 1)

-- the other way out: put it back where it was
addon = CutWorld()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
ChatClear()
Cmd("/pbfe paste same go")
RunUntilIdle()
check("pasting back into the same house restores it", CountOf(1), 5)
near("with its coordinates", FindByData(1, TABLE)[1].x, 1000, 0)
near("and its height", FindByData(1, VASE)[1].y, 160, 0)
local vase = FindByData(1, VASE)[1]
check("and its links", World.houses[1].furniture[vase.parent].dataId, CANDLE)
check("the cut is over: the clipboard is emptied", addon.sv.clip, nil)
check("the bags are empty again", BagsEmpty(), 0)

-- a bag with too little room
addon = CutWorld()
World.bagLimit = { [BAG_BACKPACK] = 2 }
Cmd("/pbfe cut 1")
check("too little room is reported", ChatHas("not enough room in the backpack"), true)
ChatClear()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("a cut without room is refused", ChatHas("refusing"), true)
check("and removes nothing", CountOf(1), 5)
check("and keeps no clipboard", addon.sv.clip, nil)

-- start anyway: it stops when the bag is full, and can be finished or reversed
ChatClear()
Cmd("/pbfe cut 1 force go")
RunUntilIdle()
check("it stops when the bag is full", ChatHas("stopped: ITEM_REMOVE_FAILED_INVENTORY_FULL"), true)
check("the table is still standing", FindByData(1, TABLE)[1] ~= nil, true)
check("the other three are out", CountOf(1), 2)
check("it says the bag is full and how to go on", ChatHas("is full. Make room, then press Cut") and ChatHas("/pbfe cut resume go: "), true)
check("the clipboard has the whole group", #addon.sv.clip.nodes, 4)
check("and the cut is pending", addon.sv.clip.cut, true)

-- reverse it: only the three that are out are put back; the table counts as in place
ChatClear()
Cmd("/pbfe paste same")
check("the plan counts what is still standing", ChatHas("1 are still standing where they were"), true)
check("and places only the others", ChatHas("3 to place"), true)
Cmd("/pbfe paste same go")
RunUntilIdle()
check("the house is whole again", CountOf(1), 5)
check("with exactly one table", #FindByData(1, TABLE), 1)
local candles = FindByData(1, CANDLE)
check("the candles are linked to the table that stayed", World.houses[1].furniture[candles[1].parent].dataId, TABLE)
check("the cut is over: the clipboard is emptied", addon.sv.clip, nil)

-- or finish it
addon = CutWorld()
World.bagLimit = { [BAG_BACKPACK] = 2 }
Cmd("/pbfe cut 1 force go")
RunUntilIdle()
World.bagLimit = nil
ChatClear()
Cmd("/pbfe cut resume go")
RunUntilIdle()
check("resume finishes the cut", CountOf(1), 1)
check("the table is out", ItemCount(TABLE), 1)
check("and the cut is still pending until it is pasted", addon.sv.clip.cut, true)
Cmd("/pbfe cut resume")
check("a finished cut has nothing to resume", ChatHas("already out of this house"), true)
Cmd("/pbfe paste to 2 same go")
RunUntilIdle()
check("then it can be pasted", CountOf(2), 4)

-- the client wants an editor mode for removal
addon = CutWorld()
World.removeNeedsMode = HOUSING_EDITOR_MODE_SELECTION
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("removal negotiates the editor mode like placement does", CountOf(1), 1)
check("and says so", ChatHas("editor mode -> SELECTION"), true)

-- the REMOVED event never comes
addon = CutWorld()
World.silent[EVENT_HOUSING_FURNITURE_REMOVED] = true
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("a removal is read from the house, not only from the event", CountOf(1), 1)
check("and none is called a failure", ChatHas("0 failed"), true)

-- only an owner may cut
addon = CutWorld()
World.houses[1].owner = false
Cmd("/pbfe cut 1 go")
check("an editor who is not the owner cannot cut", ChatHas("you can only cut from a house you own"), true)
check("and nothing happens", CountOf(1), 5)

addon = CutWorld()
Cmd("/pbfe cut")
check("cut with no argument asks which", ChatHas("say which"), true)

-- stop in the middle: the clipboard already has everything
addon = CutWorld()
Cmd("/pbfe cut 1 go")
RunFor(800)
Cmd("/pbfe stop")
RunUntilIdle()
check("stop ends the cut", addon.run, nil)
check("some were out and some were not", CountOf(1) > 1 and CountOf(1) < 5, true)
check("the cut is pending", addon.sv.clip.cut, true)
check("the clipboard has all four", #addon.sv.clip.nodes, 4)
Cmd("/pbfe paste same go")
RunUntilIdle()
check("and stopping can be reversed", CountOf(1), 5)

-- undo that is stopped half way keeps what is left in its record
addon = CutWorld()
Cmd("/pbfe copy 1")
GiveItem(BAG_BACKPACK, 0, TABLE, 1)
GiveItem(BAG_BACKPACK, 1, CANDLE, 2)
GiveItem(BAG_BACKPACK, 2, VASE, 1)
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
Cmd("/pbfe paste go")
RunUntilIdle()
check("pasted", CountOf(2), 4)
Cmd("/pbfe undo")
RunFor(700)
Cmd("/pbfe stop")
RunUntilIdle()
local left = CountOf(2)
check("a stopped undo leaves some behind", left > 0 and left < 4, true)
check("and still remembers exactly those", addon.sv.lastPaste ~= nil and #addon.sv.lastPaste.keys, left)
Cmd("/pbfe undo")
RunUntilIdle()
check("asking again finishes the job", CountOf(2), 0)
check("and clears the record", addon.sv.lastPaste, nil)

-- ---------------------------------------------------------------------------------------
section("22. reservations")
-- ---------------------------------------------------------------------------------------
-- Home has two linked groups: A (table, two candles, a vase) and B (a shelf and a book).
-- The bags hold one copy of everything, so each can be pasted once.
local function ResvWorld()
	ResetWorld()
	AddHouse(1, { name = "Home" })
	AddHouse(2, { name = "Cottage" })
	AddHouse(3, { name = "Manor" })
	local tbl = AddFurniture(1, { dataId = TABLE, name = "Redguard Table", x = 1000, y = 100, z = 2000, yaw = 0.5 })
	local ca = AddFurniture(1, { dataId = CANDLE, name = "Candle", x = 1050, y = 120, z = 2010, yaw = 1.0, parent = tbl })
	AddFurniture(1, { dataId = CANDLE, name = "Candle", x = 950, y = 120, z = 1990, yaw = -0.7, parent = tbl })
	AddFurniture(1, { dataId = VASE, name = "Vase", x = 1050, y = 160, z = 2010, parent = ca })
	local shelf = AddFurniture(1, { dataId = SHELF, name = "Bookshelf", x = -500, y = 0, z = 200, yaw = 0.3 })
	AddFurniture(1, { dataId = BOOK, name = "Book", x = -500, y = 150, z = 200, yaw = 1.2, parent = shelf })
	GiveItem(BAG_BACKPACK, 0, TABLE, 1, "Redguard Table")
	GiveItem(BAG_BACKPACK, 1, CANDLE, 2, "Candle")
	GiveItem(BAG_BACKPACK, 2, VASE, 1, "Vase")
	GiveItem(BAG_BACKPACK, 3, SHELF, 1, "Bookshelf")
	GiveItem(BAG_BACKPACK, 4, BOOK, 1, "Book")
	EnterHouse(1)
	World.player = { x = 1100, y = 100, z = 2100, rot = 1.0 }
	local a = LoadAddon()
	Cmd("/pbfe list")
	ChatClear()
	return a
end

-- walk in through the door
local function Arrive(houseId)
	EnterHouse(houseId)
	World.player = { x = 0, y = 0, z = 0, rot = 0 }
	Fire(EVENT_PLAYER_ACTIVATED, false)
end

-- making one
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 same go")
check("a reservation is made", #addon.sv.reservations, 1)
check("and announced", ChatHas("reserved #1: copy of Redguard Table -> Cottage"), true)
check("it says when it will start", ChatHas("starts by itself 10 s after you arrive"), true)
check("nothing in the house changed", CountOf(1), 6)
check("the clipboard is untouched", addon.sv.clip, nil)
check("the reservation keeps its own clip", #addon.sv.reservations[1].clip.nodes, 4)
check("and the words of the paste", table.concat(addon.sv.reservations[1].words, " "), "same go")

-- arriving: a warning first, then the paste
ChatClear()
Arrive(2)
RunFor(6000)
check("arrival is noticed", ChatHas("1 reservation is waiting for this house"), true)
check("a start is announced with time to cancel", ChatHas("starts in 10 s -- /pbfe stop cancels it"), true)
check("nothing is placed during the warning", CountOf(2), 0)
RunUntilIdle()
check("then the group is placed", CountOf(2), 4)
check("and linked", ChatHas("linked 3 / 3"), true)
check("the reservation is done and gone", ChatHas("reservation #1 is done"), true)
check("the list is empty", #addon.sv.reservations, 0)
check("the copy left the original alone", CountOf(1), 6)

-- stop in the warning time
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 same go")
Arrive(2)
RunFor(8000)
Cmd("/pbfe stop")
check("stop says what it did", ChatHas("will not start this visit"), true)
RunUntilIdle()
check("nothing was placed", CountOf(2), 0)
check("the reservation is still there", addon.sv.reservations[1].status, "waiting")
Arrive(3)
Arrive(2)
RunUntilIdle()
check("the next visit does it", CountOf(2), 4)

-- without go: the plan is shown, and the player decides
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 same")
check("it says it is run by hand", ChatHas("shows its plan when you arrive"), true)
ChatClear()
Arrive(2)
RunUntilIdle()
check("the plan is shown on arrival", ChatHas("plan: same"), true)
check("nothing is placed", CountOf(2), 0)
check("the reservation waits", addon.sv.reservations[1].status, "waiting")
Cmd("/pbfe reservations run 1 go")
RunUntilIdle()
check("run <n> go places it now", CountOf(2), 4)
check("and the reservation is done", #addon.sv.reservations, 0)

-- 'here' cannot start at the doorway
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 go")
ChatClear()
Arrive(2)
RunUntilIdle()
check("here + go waits for the player to walk", ChatHas("you arrive at the doorway"), true)
check("so nothing is placed", CountOf(2), 0)

-- several at once, worked through in turn
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 same go")
Cmd("/pbfe reserve copy 2 to 2 same go")
Cmd("/pbfe reserve copy 1 to 3 same go")
check("three are waiting", #addon.sv.reservations, 3)
ChatClear()
Cmd("/pbfe reservations")
check("the list shows them", ChatHas("3 reservations"), true)
check("with their houses", ChatHas("Cottage") and ChatHas("Manor"), true)
check("and their age", ChatHas("ago"), true)
Arrive(2)
RunUntilIdle()
check("both for this house were done, one after the other", CountOf(2), 6)
check("the one for another house is left", #addon.sv.reservations, 1)
check("and it is the Manor's", addon.sv.reservations[1].houseId, 3)
ChatClear()
Arrive(3)
RunUntilIdle()
check("without the items, the third is refused, not forced", CountOf(3), 0)
check("and says what is short", ChatHas("short: Redguard Table"), true)
check("it stays on the list", addon.sv.reservations[1].status, "waiting")
GiveItem(BAG_BACKPACK, 20, TABLE, 1)
GiveItem(BAG_BACKPACK, 21, CANDLE, 2)
GiveItem(BAG_BACKPACK, 22, VASE, 1)
Arrive(3)
RunUntilIdle()
check("with the items it goes through next time", CountOf(3), 4)

-- a house that is not the one reserved does nothing
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 same go")
ChatClear()
Arrive(3)
RunUntilIdle()
check("another house does not trigger it", ChatHas("reservation"), false)
check("and nothing is placed there", CountOf(3), 0)

-- leaving before the house has loaded
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 same go")
Arrive(2)
RunFor(2500)
EnterHouse(3)
RunUntilIdle()
check("walking out during the load cancels it", CountOf(2), 0)
check("the reservation survives", #addon.sv.reservations, 1)

-- a visitor
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 same go")
World.houses[2].owner = false
ChatClear()
Arrive(2)
RunUntilIdle()
check("without ownership it is refused", ChatHas("you can only place furnishings in a house you own"), true)
check("nothing is placed", CountOf(2), 0)
check("and it stays", addon.sv.reservations[1].status, "waiting")

-- a move: the cut happens now
addon = ResvWorld()
Cmd("/pbfe reserve cut 1 to 2 same go")
check("a cut reservation without 'yes' only previews", ChatHas("nothing has been removed. to do it: /pbfe reserve cut 1 to 2 same go yes"), true)
check("no reservation is made", #addon.sv.reservations, 0)
check("nothing is removed", CountOf(1), 6)

ChatClear()
Cmd("/pbfe reserve cut 1 to 2 same go yes")
RunUntilIdle()
check("with yes the group leaves this house now", CountOf(1), 2)
check("and a move is reserved", addon.sv.reservations[1].kind, "move")
check("announced as a move", ChatHas("MOVE of Redguard Table -> Cottage"), true)
check("the furnishings are in the bag", ItemCount(TABLE), 2)
check("the clipboard was not used", addon.sv.clip, nil)
check("the summary points at the reservation", ChatHas("reservation #1 will paste it when you enter the other house"), true)
Arrive(2)
RunUntilIdle()
check("on arrival the group goes in", CountOf(2), 4)
check("the move is done", #addon.sv.reservations, 0)
check("the bags are back to one copy", ItemCount(TABLE), 1)

-- a move that could not finish
addon = ResvWorld()
for slot = 0, 4 do World.bags[BAG_BACKPACK][slot] = nil end
World.bagLimit = { [BAG_BACKPACK] = 2 }
ChatClear()
Cmd("/pbfe reserve cut 1 to 2 same go force yes")
RunUntilIdle()
check("a cut that stopped is still reserved", #addon.sv.reservations, 1)
check("it tells how to finish", ChatHas("/pbfe reservations load 1, then /pbfe cut resume go"), true)
check("part of the group is still in Home", CountOf(1) > 2, true)
ChatClear()
Cmd("/pbfe reservations drop 1")
check("a move cannot be dropped by accident", ChatHas("is a move"), true)
check("it is still there", #addon.sv.reservations, 1)
Cmd("/pbfe reservations load 1")
check("load puts it on the clipboard", addon.sv.clip ~= nil and addon.sv.clip.cut, true)
World.bagLimit = nil
Cmd("/pbfe cut resume go")
RunUntilIdle()
check("the cut can be resumed from there", CountOf(1), 2)
Cmd("/pbfe reservations drop 1 force")
check("force drops it", #addon.sv.reservations, 0)

-- a paste that stops part way is not repeated
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 same go")
World.linkRefusal = HOUSING_REQUEST_RESULT_LINK_FAILED
ChatClear()
Arrive(2)
RunUntilIdle()
check("a paste with failed links leaves it marked partial", addon.sv.reservations[1].status, "partial")
check("with a note", addon.sv.reservations[1].note, "all placed, 3 links failed")
check("and says what to do", ChatHas("/pbfe reservations retry 1"), true)
local placed = CountOf(2)
Arrive(3)
Arrive(2)
RunUntilIdle()
check("it does not run again by itself", CountOf(2), placed)
Cmd("/pbfe reservations retry 1")
check("retry makes it wait again", addon.sv.reservations[1].status, "waiting")

-- run <n> travels there
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 same go")
ChatClear()
Cmd("/pbfe reservations run 1")
check("run from elsewhere makes a trip", ChatHas("travelling to Cottage"), true)
RunUntilIdle()
check("and ends in the house", World.houseId, 2)
check("with the group placed", CountOf(2), 4)
check("the reservation is done", #addon.sv.reservations, 0)

-- a trip and a reservation for the same house
addon = ResvWorld()
Cmd("/pbfe reserve copy 2 to 2 same go")
Cmd("/pbfe copy 1")
ChatClear()
Cmd("/pbfe paste to 2 same go")
RunUntilIdle()
check("the trip's paste and the reservation both ran", CountOf(2), 6)
check("the reservation is done", #addon.sv.reservations, 0)

-- housekeeping
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 same go")
Cmd("/pbfe reserve copy 2 to 3 same")
ChatClear()
Cmd("/pbfe reservations drop 1")
check("drop removes one", #addon.sv.reservations, 1)
check("the other is renumbered by id, not by place", addon.sv.reservations[1].id, 2)
Cmd("/pbfe reservations drop 9")
check("an unknown number is said", ChatHas("no reservation #9"), true)
Cmd("/pbfe reservations drop all")
check("drop all empties the list", #addon.sv.reservations, 0)
ChatClear()
Cmd("/pbfe reservations")
check("an empty list says so", ChatHas("no reservations"), true)

-- refused at the door
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 same go")
check("a house is required", ChatHas("which house?"), true)
Cmd("/pbfe reserve copy 1 to 9")
check("a house that does not exist", ChatHas("no house #9"), true)
Cmd("/pbfe reserve move 1 to 2")
check("only copy and cut", ChatHas("reserve what?"), true)
Cmd("/pbfe reserve copy 1 to 2 same rot 90")
check("rot needs calibration before it is promised", ChatHas("rot needs /pbfe calib first"), true)
Cmd("/pbfe reserve copy to 2")
check("a group must be named", ChatHas("say which"), true)
check("none of those made a reservation", #addon.sv.reservations, 0)

-- they outlive the session
addon = ResvWorld()
Cmd("/pbfe reserve copy 1 to 2 same go")
local reloaded2 = LoadAddon()
check("a reservation survives a reload", #reloaded2.sv.reservations, 1)
Arrive(2)
RunUntilIdle()
check("and still fires", CountOf(2), 4)

-- ---------------------------------------------------------------------------------------
section("23. item or collectible (the first console paste called every item a collectible)")
-- ---------------------------------------------------------------------------------------
-- The console answered a non-zero collectible id for ordinary furnishings, and every piece of a
-- group of stone slabs was refused as "a collectible you cannot place". The client's own housing
-- code does not ask that question that way: it reads the collectible LINK, and takes the id from it.
local function SlabWorld()
	ResetWorld()
	AddHouse(1, { name = "Home" })
	AddHouse(2, { name = "Cottage" })
	local a = AddFurniture(1, { dataId = 700, name = "Rough Block (Slab)", x = 100, y = 50, z = 100 })
	AddFurniture(1, { dataId = 700, name = "Rough Block (Slab)", x = 200, y = 50, z = 100, parent = a })
	AddFurniture(1, { dataId = 700, name = "Rough Block (Slab)", x = 300, y = 50, z = 100, parent = a })
	AddFurniture(1, { dataId = 700, name = "Rough Block (Slab)", x = 400, y = 50, z = 100, parent = a })
	GiveItem(BAG_BACKPACK, 0, 700, 4, "Rough Block (Slab)")
	World.rawCollectibleQuirk = 7
	World.cannotPlace = { [7] = true }
	EnterHouse(1)
	World.player = { x = 100, y = 50, z = 100, rot = 0 }
	local ad = LoadAddon()
	Cmd("/pbfe list")
	ChatClear()
	return ad
end

addon = SlabWorld()
Cmd("/pbfe copy 1")
check("plain items are counted as items", ChatHas("(4 items, 0 collectibles, 3 links)"), true)
for i, node in ipairs(addon.sv.clip.nodes) do
	if node.collectibleId ~= 0 then check("node " .. i .. " is not a collectible", node.collectibleId, 0) end
end
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
ChatClear()
Cmd("/pbfe paste")
check("the plan is ready", ChatHas("ready. to place"), true)
check("nothing is called unavailable", ChatHas("collectible unavailable"), false)
Cmd("/pbfe paste go")
RunUntilIdle()
check("the four slabs are placed", CountOf(2), 4)
check("and linked", ChatHas("linked 3 / 3"), true)
check("by item, not by collectible", #CallsTo("HousingEditorRequestCollectiblePlacement"), 0)

-- a clipboard copied by the old build still says "collectible", and is healed when the bags hold the item
addon = SlabWorld()
Cmd("/pbfe copy 1")
for _, node in ipairs(addon.sv.clip.nodes) do node.collectibleId = 7 end     -- as the old build stored it
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
ChatClear()
Cmd("/pbfe paste")
check("an old clipboard is read as items when the bags hold them", ChatHas("treating them as items"), true)
check("and is ready", ChatHas("ready. to place"), true)
Cmd("/pbfe paste go")
RunUntilIdle()
check("and pastes", CountOf(2), 4)
check("the paste emptied the clipboard, healed or not", addon.sv.clip, nil)

-- no items in the bags: the old guess is still reported honestly
addon = SlabWorld()
Cmd("/pbfe copy 1")
for _, node in ipairs(addon.sv.clip.nodes) do node.collectibleId = 7 end
World.bags[BAG_BACKPACK][0] = nil
EnterHouse(2)
ChatClear()
Cmd("/pbfe paste")
check("without the items it is still refused", ChatHas("not ready"), true)

-- the stored id happens to be a REAL, placeable collectible that is some other furnishing: the slabs
-- must not turn into that collectible
addon = SlabWorld()
World.cannotPlace = nil
AddFurniture(1, { dataId = 999, name = "Some Crown Statue", x = 9000, y = 0, z = 9000, collectibleId = 7 })
Cmd("/pbfe list")
Cmd("/pbfe copy 1")
for _, node in ipairs(addon.sv.clip.nodes) do node.collectibleId = 7 end
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
ChatClear()
Cmd("/pbfe paste go")
RunUntilIdle()
check("a collectible id that is another furnishing is not placed in its stead", #CallsTo("HousingEditorRequestCollectiblePlacement"), 0)
check("the slabs are placed as items", CountOf(2), 4)

-- no link API: the raw call is believed only when the collectible's own furniture data id agrees
addon = SlabWorld()
local savedLink = GetPlacedFurnitureLink
GetPlacedFurnitureLink = nil
Cmd("/pbfe copy 1")
GetPlacedFurnitureLink = savedLink
check("a raw id that does not belong to this furnishing is not believed", ChatHas("(4 items, 0 collectibles"), true)

-- a real collectible is still a collectible
ResetWorld()
AddHouse(1)
AddHouse(2)
local stand2 = AddFurniture(1, { dataId = 100, name = "Crown Stand", x = 0, y = 0, z = 0, collectibleId = 555 })
AddFurniture(1, { dataId = 101, name = "Ornament", x = 10, y = 50, z = 0, parent = stand2 })
World.rawCollectibleQuirk = 7
EnterHouse(1)
World.player = { x = 0, y = 0, z = 0, rot = 0 }
addon = LoadAddon()
Cmd("/pbfe list")
ChatClear()
Cmd("/pbfe copy 1")
check("a real collectible is still counted as one", ChatHas("(1 items, 1 collectibles, 1 links)"), true)
check("with its own id", addon.sv.clip.nodes[1].collectibleId, 555)

-- the diagnostic shows what the client says about each piece
addon = SlabWorld()
ChatClear()
Cmd("/pbfe kind 2")
check("kind shows the item link", ChatHas("item link: yes"), true)
check("and the empty collectible link", ChatHas("collectible link: no"), true)
check("and the raw call's answer", ChatHas("GetCollectibleIdFromFurnitureId -> 7"), true)
check("and the verdict", ChatHas("=> item"), true)

-- ---------------------------------------------------------------------------------------
section("24. Paste and Move on the quickslot wheel")
-- ---------------------------------------------------------------------------------------
local wheel
local function WheelWorld(opts)
	local a = ResvWorld()
	wheel = InstallMockWheel(opts)
	return a
end

-- nothing waiting: the wheel is the game's, and nothing is hooked
addon = WheelWorld()
check("a plain wheel has its eight entries", wheel:ShowMenu(), 8)
check("and nothing has been hooked", World.hookCalls, 0)

-- a reservation waiting for the house: Paste appears on arrival, and goes when picked
addon = WheelWorld()
Cmd("/pbfe reserve copy 1 to 2 same")
ChatClear()
Arrive(2)
RunFor(6000)
check("arrival says what is on the wheel", ChatHas("quickslot wheel: Paste (1). hold the quickslot button"), true)
check("the wheel was hooked once", World.hookCalls, 1)
check("the wheel now has nine entries", wheel:ShowMenu(), 9)
check("the new one is Paste (1)", wheel:Names()[9], "Paste (1)")
check("the eight that were there are untouched", wheel:Names()[1], "Potion A")
check("it borrows an empty slot to be drawn with", wheel.menu.entries[9].data.slotNum, 4)
check("it is marked as ours", wheel.menu.entries[9].data.pbfe, "paste")
check("and carries an icon", wheel.menu.entries[9].inactiveIcon ~= nil, true)
check("picking does nothing in the client's call chain", CountOf(2), 0)
wheel:Select(9)
check("it only schedules", CountOf(2), 0)
RunUntilIdle()
check("then the group is placed", CountOf(2), 4)
check("and linked", ChatHas("linked 3 / 3"), true)
check("the reservation is done", #addon.sv.reservations, 0)
check("the wheel says it is back to normal", ChatHas("the quickslot wheel is back to normal"), true)
check("and has its eight entries again", wheel:ShowMenu(), 8)

-- the hook is inert once there is nothing to offer, and does not break the next opening
check("the entries are not left behind", wheel:Names()[9], nil)

-- Paste and Move together: ten entries, the most the accessible wheel has hotkeys for
addon = WheelWorld()
Cmd("/pbfe reserve copy 2 to 2 same")
Cmd("/pbfe reserve cut 1 to 2 same yes")
RunUntilIdle()
check("the cut happened now", CountOf(1), 2)
ChatClear()
Arrive(2)
RunFor(6000)
check("both are announced", ChatHas("quickslot wheel: Paste (1) / Move (1)"), true)
check("the wheel has ten entries", wheel:ShowMenu(), 10)
check("Paste comes first", wheel:Names()[9], "Paste (1)")
check("then Move", wheel:Names()[10], "Move (1)")
wheel:Select(10)
RunUntilIdle()
check("picking Move places the moved group", #FindByData(2, TABLE), 1)
check("and only that", CountOf(2), 4)
check("Paste is still on the wheel", wheel:ShowMenu(), 9)
check("with its name", wheel:Names()[9], "Paste (1)")
check("the wheel is not back to normal yet", ChatHas("still on the wheel: Paste (1)"), true)
wheel:Select(9)
RunUntilIdle()
check("picking Paste places the copy", CountOf(2), 6)
check("now the wheel is the game's again", wheel:ShowMenu(), 8)
check("and says so", ChatHas("the quickslot wheel is back to normal"), true)

-- two of one kind are one entry that runs both, one after the other
addon = WheelWorld()
Cmd("/pbfe reserve copy 1 to 2 same")
Cmd("/pbfe reserve copy 2 to 2 same")
Arrive(2)
RunFor(6000)
check("still nine entries", wheel:ShowMenu(), 9)
check("two pastes are one entry with a count", wheel:Names()[9], "Paste (2)")
wheel:Select(9)
RunUntilIdle()
check("it ran both", CountOf(2), 6)
check("and the wheel is back", wheel:ShowMenu(), 8)

-- an automatic reservation: picking during the warning starts it at once, and it does not run twice
addon = WheelWorld()
Cmd("/pbfe reserve copy 1 to 2 same go")
Arrive(2)
RunFor(6000)
check("an automatic one is on the wheel too", wheel:ShowMenu(), 9)
wheel:Select(9)
RunFor(1500)
check("picked, it starts before the warning ends", CountOf(2) > 0, true)
RunUntilIdle()
check("and runs once", CountOf(2), 4)

-- somewhere else, or somebody else's house: nothing
addon = WheelWorld()
Cmd("/pbfe reserve copy 1 to 2 same")
ChatClear()
Arrive(3)
RunFor(6000)
check("another house does not announce", ChatHas("quickslot wheel"), false)
check("and the wheel is untouched", wheel:ShowMenu(), 8)

addon = WheelWorld()
Cmd("/pbfe reserve copy 1 to 2 same")
World.houses[2].owner = false
ChatClear()
Arrive(2)
RunFor(6000)
check("a house you do not own offers nothing", wheel:ShowMenu(), 8)
check("and says nothing", ChatHas("quickslot wheel"), false)

-- in combat, and the other wheels
addon = WheelWorld()
Cmd("/pbfe reserve copy 1 to 2 same")
Arrive(2)
RunFor(6000)
World.inCombat = true
check("in combat the wheel is left alone", wheel:ShowMenu(), 8)
World.inCombat = false
wheel.category = HOTBAR_CATEGORY_EMOTE_WHEEL
check("the emote wheel is left alone", wheel:ShowMenu(), 8)
wheel.category = HOTBAR_CATEGORY_QUICKSLOT_WHEEL
check("the quickslot wheel has it again", wheel:ShowMenu(), 9)

-- the switch
addon = WheelWorld()
Cmd("/pbfe reserve copy 1 to 2 same")
Cmd("/pbfe menu off")
ChatClear()
Arrive(2)
RunFor(6000)
check("off: it says something is waiting, and that the menu is off", ChatHas("the wheel extension is off"), true)
check("off: nothing is hooked", World.hookCalls, 0)
check("off: the wheel is untouched", wheel:ShowMenu(), 8)
ChatClear()
Cmd("/pbfe menu on")
check("on: it is announced at once", ChatHas("quickslot wheel: Paste (1)"), true)
check("on: the wheel has it", wheel:ShowMenu(), 9)
ChatClear()
Cmd("/pbfe menu")
check("status says what is on the wheel", ChatHas("on the wheel here: Paste (1)"), true)
check("status says the hook is installed", ChatHas("hook: installed, borrowed slot: 4"), true)

-- no way to hook safely: say so, and the commands still work
addon = WheelWorld({ noSecurePostHook = true })
Cmd("/pbfe reserve copy 1 to 2 same")
ChatClear()
Arrive(2)
RunFor(6000)
check("without SecurePostHook it says so", ChatHas("SecurePostHook is not available"), true)
check("and does not fall back to a plain hook", wheel:ShowMenu(), 8)
Cmd("/pbfe reservations run 1 go")
RunUntilIdle()
check("the commands still do it", CountOf(2), 4)

addon = WheelWorld()
World.securePostHookBroken = true
Cmd("/pbfe reserve copy 1 to 2 same")
ChatClear()
Arrive(2)
RunFor(6000)
check("a refused hook is reported", ChatHas("SecurePostHook refused"), true)
check("and the wheel is untouched", wheel:ShowMenu(), 8)

-- something goes wrong inside the hook: contained, and it stops itself
addon = WheelWorld()
Cmd("/pbfe reserve copy 1 to 2 same")
World.wheelAddThrows = true
ChatClear()
Arrive(2)
RunFor(6000)
check("an error adding the entry does not break the wheel", wheel:ShowMenu(), 8)
check("the extension stops itself", addon.wheelBroken ~= nil, true)
check("and says so", ChatHas("stopped itself"), true)
ChatClear()
World.wheelAddThrows = false
check("it stays stopped", wheel:ShowMenu(), 8)
check("without repeating itself", ChatHas("stopped itself"), false)
Cmd("/pbfe reservations run 1 go")
RunUntilIdle()
check("and the commands go on working", CountOf(2), 4)

-- which slot number the entries are drawn with
addon = WheelWorld({ quickslots = { "a", "b", "c", "d", "e", "f", "g", "h" } })
World.strictSlots = true
Cmd("/pbfe reserve copy 1 to 2 same")
ChatClear()
Arrive(2)
RunFor(6000)
check("a full wheel and a client that refuses slot 9: nothing is hooked", World.hookCalls, 0)
check("it says why", ChatHas("no empty quickslot to borrow"), true)
check("the wheel is untouched", wheel:ShowMenu(), 8)

addon = WheelWorld({ quickslots = { "a", "b", "c", "d", "e", "f", "g", "h" } })
Cmd("/pbfe reserve copy 1 to 2 same")
Arrive(2)
RunFor(6000)
check("a full wheel and a client that copes with slot 9: it is used", wheel:ShowMenu(), 9)
check("as the slot number", wheel.menu.entries[9].data.slotNum, 9)

addon = WheelWorld()
World.strictSlots = true
Cmd("/pbfe reserve copy 1 to 2 same")
Arrive(2)
RunFor(6000)
check("an empty slot is preferred, and drawing it does not raise", wheel:ShowMenu(), 9)

-- never more than ten
addon = WheelWorld()
World.baseEntries = 9
Cmd("/pbfe reserve copy 2 to 2 same")
Cmd("/pbfe reserve cut 1 to 2 same yes")
RunUntilIdle()
Arrive(2)
RunFor(6000)
check("the wheel stops at ten entries", wheel:ShowMenu(), 10)
check("Paste got the last place", wheel:Names()[10], "Paste (1)")

-- Japanese
addon = WheelWorld()
World.language = "jp"
Cmd("/pbfe reserve copy 1 to 2 same")
Arrive(2)
RunFor(6000)
wheel:ShowMenu()
check("the entry is named in Japanese on a Japanese client", wheel:Names()[9], "ペースト (1)")

-- a paste that travelled here and only showed its plan is offered on the wheel
addon = WheelWorld()
Cmd("/pbfe copy 1")
ChatClear()
Cmd("/pbfe paste to 2")
RunFor(12000)
check("the trip arrived and showed its plan", ChatHas("plan: here"), true)
check("it is offered on the wheel", ChatHas("quickslot wheel: Paste (1)"), true)
check("the wheel has it", wheel:ShowMenu(), 9)
check("nothing has been placed", CountOf(2), 0)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }     -- walk to where it belongs
wheel:Select(9)
RunUntilIdle()
check("picking it pastes where you stand", CountOf(2), 4)
near("relative to the player", FindByData(2, TABLE)[1].x, 1000 + (5000 - 1100), 0)
check("the wheel is back to normal", wheel:ShowMenu(), 8)

-- a trip's move is a Move
addon = WheelWorld()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
Cmd("/pbfe paste to 2")
RunFor(12000)
check("a cut clipboard is offered as Move", wheel:ShowMenu() == 9 and wheel:Names()[9] == "Move (1)", true)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
wheel:Select(9)
RunUntilIdle()
check("and moves it", CountOf(2), 4)
check("the move is complete: the clipboard is emptied", addon.sv.clip, nil)

-- ---------------------------------------------------------------------------------------
section("25. Copy and Cut in the housing editor (a clipboard: no house to choose)")
-- ---------------------------------------------------------------------------------------
-- Home has the table group (table 1001, candles 1002 and 1003, vase 1004), the shelf group (1005, 1006)
-- and, added here, a chair that is linked to nothing (1007).
local TABLE_ID, SHELF_ID, CHAIR_ID = 1001, 1005, 1007
local CIRCLE, SQUARE = "HOUSING_EDITOR_NEGATIVE_ACTION", "HOUSING_EDITOR_SECONDARY_ACTION"

local function EditorWorld()
	local a = ResvWorld()
	AddFurniture(1, { dataId = CHAIR, name = "Chair", x = 3000, y = 0, z = 3000 })
	wheel = InstallMockWheel()
	InstallMockEditor()
	-- the add-on looked for the editor HUD when it loaded and found none; it looks again when the
	-- player is activated
	Fire(EVENT_PLAYER_ACTIVATED, false)
	ChatClear()
	return a
end

-- The client updates its buttons two ways: a full rebuild (palette added, THEN the strip) and, when
-- only the target changed, a palette refresh with the strip already registered. Everything about the
-- square button has to hold after either.
-- (looked up when called: the mock editor is rebuilt for every world)
-- After the client's update the add-on settles the square button a frame later (which descriptor the strip
-- keeps decides whether Browse is drawn along the bottom), so each order includes that frame.
local ORDERS = {
	-- Browse is registered last, so Browse's descriptor is the one the strip keeps; then the target event
	rebuild = function() Rebuild(); Fire(EVENT_HOUSING_TARGET_FURNITURE_CHANGED); RunFor(10) end,
	-- the palette's descriptor is registered last
	refresh = function() Rebuild(); TargetChanged(); Fire(EVENT_HOUSING_TARGET_FURNITURE_CHANGED); RunFor(10) end,
	-- a full update with no target event at all (a link was made, a path changed): only the strip's own draw
	-- of Browse can say the wrong descriptor was kept
	relink = function() Rebuild(); RunFor(10) end,
}
local function Settle(order) ORDERS[order]() end
local function Names(order) Settle(order or "rebuild"); return PaletteNames() end
local function Has(names, name)
	for _, n in ipairs(names) do if n == name then return true end end
	return false
end

-- the buttons are put in
addon = EditorWorld()
check("the editor keys were installed when the HUD appeared", addon.editorKeysInstalled, true)
check("a missing HUD at load was not called a failure", addon.editorBroken, nil)
Fire(EVENT_PLAYER_ACTIVATED, false)
Fire(EVENT_PLAYER_ACTIVATED, false)
local ours = 0
for _, d in ipairs(HOUSING_EDITOR_SHARED.selectionModeKeybindPaletteGamepadDescriptor) do
	if d.pbfe then ours = ours + 1 end
end
check("two entries (Copy and Cut), once, however often the player is activated", ours, 2)

for _, order in ipairs({ "rebuild", "refresh", "relink" }) do
	local tag = " [" .. order .. "]"

	-- what is drawn on the palette
	addon = EditorWorld()
	World.target = TABLE_ID
	local names = Names(order)
	check("linked piece: Copy is on the palette" .. tag, Has(names, "Copy"), true)
	check("linked piece: Cut is on the palette too" .. tag, Has(names, "Cut"), true)
	check("beside the game's own buttons" .. tag, Has(names, "Select") and Has(names, "Link"), true)
	check("Copy then Cut, after them" .. tag, names[#names - 1] == "Copy" and names[#names] == "Cut", true)
	World.target = 1002
	check("a child counts as linked too" .. tag, Has(Names(order), "Cut"), true)
	World.target = CHAIR_ID
	names = Names(order)
	check("unlinked piece: neither" .. tag, Has(names, "Copy") or Has(names, "Cut"), false)
	check("unlinked piece: the game's buttons stay" .. tag, Has(names, "Select"), true)
	World.target = nil
	check("nothing aimed at: neither" .. tag, Has(Names(order), "Copy") or Has(Names(order), "Cut"), false)

	-- the square button: Browse, or Cut
	World.target = CHAIR_ID
	Settle(order)
	check("unlinked piece: the strip's label is Browse" .. tag, StripLabel(SQUARE), "Browse")
	check("unlinked piece: the square button is handled" .. tag, PressKey(SQUARE), true)
	RunFor(50)
	check("and it browses" .. tag, World.browseCalls, 1)
	check("without cutting anything" .. tag, CountOf(1), 7)

	World.target = nil
	Settle(order)
	check("nothing aimed at: the square button still browses" .. tag, PressKey(SQUARE), true)
	check("and Browse was called again" .. tag, World.browseCalls, 2)

	World.target = TABLE_ID
	Settle(order)
	check("linked piece: the bottom of the screen says nothing for the square button (the palette says Cut)" .. tag, StripLabel(SQUARE), nil)
	check("linked piece: the square button is handled" .. tag, PressKey(SQUARE), true)
	RunUntilIdle()
	check("and it cuts: the group leaves the house" .. tag, CountOf(1), 3)
	check("Browse was not called" .. tag, World.browseCalls, 2)
	check("the clipboard is a cut" .. tag, addon.sv.clip ~= nil and addon.sv.clip.cut, true)

	-- the circle button copies
	addon = EditorWorld()
	World.target = TABLE_ID
	Settle(order)
	check("the circle button is handled" .. tag, PressKey(CIRCLE), true)
	RunFor(50)
	check("and puts the group on the clipboard" .. tag, addon.sv.clip ~= nil and #addon.sv.clip.nodes, 4)
	check("it is a copy, not a cut" .. tag, addon.sv.clip.cut, nil)
	check("nothing left the house" .. tag, CountOf(1), 7)
end

-- Copy: the clipboard, then Paste on the wheel in any house of yours
addon = EditorWorld()
World.target = TABLE_ID
Settle("rebuild")
check("the circle button is handled", PressKey(CIRCLE), true)
check("it only schedules: nothing is on the clipboard yet", addon.sv.clip, nil)
RunFor(50)
check("then the group is on the clipboard", #addon.sv.clip.nodes, 4)
check("fresh, which is what puts it on the wheel", addon.sv.clipFresh, true)
check("it says what was copied", ChatHas("copied 4 furnishings"), true)
check("and what to do", ChatHas("use the quickslot wheel: Paste"), true)
check("no screen was opened", World.dialog, nil)
check("the wheel already offers Paste, here in this house", ChatHas("quickslot wheel: Paste (1)"), true)
check("it has it", wheel:ShowMenu(), 9)
Arrive(2)
RunFor(6000)
check("in another house of yours it is announced again", ChatHas("quickslot wheel: Paste (1)"), true)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.camera = { yaw = 0, pitch = math.rad(-30) }
wheel:ShowMenu()
wheel:Select(9)
RunUntilIdle()
check("one pick pastes it", CountOf(2), 4)
check("at the cursor, by default", math.abs(FindByData(2, TABLE)[1].z - (5000 + 160 / math.tan(math.rad(30)) - 100)) < 3, true)
check("the clipboard is no longer fresh", addon.sv.clipFresh, false)
check("so the wheel is the game's again", wheel:ShowMenu(), 8)
check("and says so", ChatHas("the quickslot wheel is back to normal"), true)
check("the paste emptied the clipboard", addon.sv.clip, nil)
check("and says so", ChatHas("pasted; the clipboard is emptied"), true)

-- there is nothing left to paste by hand, and the wheel does not come back
ChatClear()
Cmd("/pbfe paste same")
check("a second paste has nothing to take", ChatHas("the clipboard is empty"), true)

-- Cut: the cut now, then Move in a house of yours
for _, order in ipairs({ "rebuild", "refresh" }) do
	local tag = " [" .. order .. "]"
	addon = EditorWorld()
	World.target = TABLE_ID
	Settle(order)
	check("the square button is handled" .. tag, PressKey(SQUARE), true)
	RunUntilIdle()
	check("the group left this house at once" .. tag, CountOf(1), 3)
	check("the chair stayed" .. tag, #FindByData(1, CHAIR), 1)
	check("the clipboard holds all four, as a cut" .. tag, #addon.sv.clip.nodes == 4 and addon.sv.clip.cut, true)
	check("fresh" .. tag, addon.sv.clipFresh, true)
	check("and the wheel offers Move" .. tag, ChatHas("quickslot wheel: Move (1)"), true)
	Arrive(2)
	RunFor(6000)
	World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
	World.camera = { yaw = 0, pitch = math.rad(-30) }
	wheel:ShowMenu()
	wheel:Select(9)
	RunUntilIdle()
	check("one pick moves it" .. tag, CountOf(2), 4)
	check("the move is complete: the clipboard is emptied" .. tag, addon.sv.clip, nil)
	check("and the wheel is back" .. tag, wheel:ShowMenu(), 8)
end

-- a cut is not replaced by the next copy or cut
addon = EditorWorld()
World.target = TABLE_ID
Settle("rebuild")
PressKey(SQUARE)
RunUntilIdle()
World.target = SHELF_ID
Settle("rebuild")
ChatClear()
PressKey(CIRCLE)
RunFor(50)
check("a second copy is refused while a cut waits", ChatHas("a cut is still waiting (4 furnishings)"), true)
check("the clipboard is still the cut", addon.sv.clip.cut, true)
check("and still the table", addon.sv.clip.nodes[1].name, "Redguard Table")
PressKey(SQUARE)
RunFor(50)
check("so is a second cut", CountOf(1), 3)

-- who may
for _, order in ipairs({ "rebuild", "refresh" }) do
	local tag = " [" .. order .. "]"
	addon = EditorWorld()
	World.houses[1].owner = false
	World.target = TABLE_ID
	local names = Names(order)
	check("an editor who is not the owner can copy" .. tag, Has(names, "Copy"), true)
	check("but is not offered Cut" .. tag, Has(names, "Cut"), false)
	check("the square button stays Browse" .. tag, StripLabel(SQUARE), "Browse")
	check("and handles" .. tag, PressKey(SQUARE), true)
	RunFor(50)
	check("it browses" .. tag, World.browseCalls, 1)
	check("and cuts nothing" .. tag, CountOf(1), 7)
end

addon = EditorWorld()
World.houses[1].owner = false
World.houses[1].editor = false
World.target = TABLE_ID
check("a visitor gets neither", Has(Names(), "Copy") or Has(Names(), "Cut"), false)

-- the switch takes everything back out, and the keyboard interface is left alone
addon = EditorWorld()
World.target = TABLE_ID
Settle("rebuild")
Cmd("/pbfe editor off")
World.duplicateKeybinds = 0
Settle("rebuild")
Settle("refresh")
check("off: neither button", Has(PaletteNames(), "Copy") or Has(PaletteNames(), "Cut"), false)
check("off: the square button is Browse", StripLabel(SQUARE), "Browse")
check("off: and it browses", PressKey(SQUARE), true)
check("off: Browse was called", World.browseCalls, 1)
check("off: the palette list is the client's own again", #HOUSING_EDITOR_SHARED.selectionModeKeybindPaletteGamepadDescriptor, 4)
check("off: no duplicate keybinds are provoked", World.duplicateKeybinds, 0)
Cmd("/pbfe editor on")
check("on: Copy and Cut are back", Has(PaletteNames(), "Copy") and Has(PaletteNames(), "Cut"), true)
RunFor(10)
check("on: Cut is drawn on the palette and not along the bottom", Has(PaletteNames(), "Cut") and StripLabel(SQUARE) == nil, true)
check("on: and the square button still handles", PressKey(SQUARE), true)
RunUntilIdle()
ChatClear()
Cmd("/pbfe editor")
check("status says it is on and installed", ChatHas("editor buttons: on") and ChatHas("installed: yes"), true)

addon = EditorWorld()
World.target = TABLE_ID
World.gamepad = false
check("with the keyboard interface there is no Copy or Cut", Has(Names(), "Copy") or Has(Names(), "Cut"), false)
check("and the button is Browse", StripLabel(SQUARE), "Browse")
World.gamepad = true

-- Browse is put back when the target changes to something that is not a linked furnishing
addon = EditorWorld()
World.stripUpdates = 0
Fire(EVENT_HOUSING_TARGET_FURNITURE_CHANGED)
check("nothing happens before the client has finished", World.stripUpdates, 0)
RunFor(10)
check("a target change refreshes the strip a frame later", World.stripUpdates, 1)
Fire(EVENT_HOUSING_TARGET_FURNITURE_CHANGED)
Fire(EVENT_HOUSING_TARGET_FURNITURE_CHANGED)
Fire(EVENT_HOUSING_TARGET_FURNITURE_CHANGED)
RunFor(10)
check("a burst of target changes is one refresh", World.stripUpdates, 2)

-- Cut is not drawn along the bottom, in any order, and does not loop
addon = EditorWorld()
World.target = TABLE_ID
Rebuild()
check("right after the client's own update Browse is the descriptor the strip keeps", StripLabel(SQUARE), "Browse")
check("and the square button already cuts, whichever is kept", PressKey(SQUARE), true)
RunUntilIdle()
check("the group left the house", CountOf(1), 3)
addon = EditorWorld()
World.target = TABLE_ID
Rebuild()
RunFor(10)
check("a frame later the strip keeps the palette's Cut: nothing is drawn along the bottom", StripLabel(SQUARE), nil)
Rebuild()
RunFor(10)
Rebuild()
RunFor(10)
RunUntilIdle()                      -- it ends: nothing keeps scheduling itself
check("repeated full updates settle each time, and the label is still not there", StripLabel(SQUARE), nil)
World.target = CHAIR_ID
Rebuild(); Fire(EVENT_HOUSING_TARGET_FURNITURE_CHANGED); RunFor(10)
check("moving to a furnishing that is not linked brings Browse back", StripLabel(SQUARE), "Browse")
World.target = TABLE_ID
Rebuild(); Fire(EVENT_HOUSING_TARGET_FURNITURE_CHANGED); RunFor(10)
check("and back to a linked one takes it away again", StripLabel(SQUARE), nil)

-- while something is running, the buttons are not offered
addon = EditorWorld()
World.target = TABLE_ID
Cmd("/pbfe cut 1 go")
RunFor(300)
check("while a cut runs there is no Copy or Cut", Has(Names(), "Copy") or Has(Names(), "Cut"), false)
RunUntilIdle()

-- a cut that would not fit in the bag does not start
addon = EditorWorld()
World.bagLimit = { [BAG_BACKPACK] = 1 }
for slot = 0, 4 do World.bags[BAG_BACKPACK][slot] = nil end
World.target = TABLE_ID
Settle("rebuild")
PressKey(SQUARE)
RunUntilIdle()
check("a cut with no room for it is refused", ChatHas("refusing"), true)
check("so nothing is taken out", CountOf(1), 7)
check("and the clipboard is untouched", addon.sv.clip, nil)

-- Japanese
addon = EditorWorld()
World.language = "jp"
World.target = TABLE_ID
local names = Names()
check("the palette says コピー and カット", Has(names, "コピー") and Has(names, "カット"), true)
check("along the bottom the strip says nothing: only the palette says カット", StripLabel(SQUARE), nil)

-- ---------------------------------------------------------------------------------------
section("26. pasting where the cursor points")
-- ---------------------------------------------------------------------------------------
-- The camera looks along a heading, pitched up or down; the cursor is the middle of the screen. The
-- player's eyes are 160 cm above the floor, so looking down by an angle reaches the floor 160 / tan
-- of that angle ahead.
local function Down(degrees) return math.rad(-degrees) end
local AHEAD_30 = 160 / math.tan(math.rad(30))             -- about 277 cm

local function AimWorld()
	local a = ResvWorld()
	wheel = InstallMockWheel()
	return a
end

-- the point itself
for _, flavour in ipairs({ "zeros behind", "points behind" }) do
	local tag = " [" .. flavour .. "]"
	addon = AimWorld()
	World.rayBehindReturns = flavour == "points behind"

	World.camera = { yaw = 0, pitch = Down(30) }
	local aim, why = addon:AimPoint()
	check("looking down ahead gives a point" .. tag, aim ~= nil, true)
	near("on the player's own floor" .. tag, aim.y, 100, 0)
	near("straight ahead" .. tag, aim.z - 2100, AHEAD_30, 3)
	near("and not sideways" .. tag, aim.x - 1100, 0, 3)
	near("with its distance" .. tag, aim.distance, AHEAD_30, 3)

	World.camera = { yaw = math.rad(90), pitch = Down(30) }
	aim = addon:AimPoint()
	near("turned a quarter, it is to the side" .. tag, aim.x - 1100, AHEAD_30, 3)

	World.camera = { yaw = 0, pitch = math.rad(20) }
	aim, why = addon:AimPoint()
	check("looking up gives no point" .. tag, aim, nil)
	check("and says why" .. tag, why, "the cursor is not pointing down at the floor")

	World.camera = { yaw = 0, pitch = 0 }
	check("at the horizon gives none" .. tag, (addon:AimPoint()), nil)

	World.camera = { yaw = 0, pitch = Down(2) }
	aim, why = addon:AimPoint()
	check("a floor point beyond thirty metres is refused" .. tag, aim, nil)
	check("with the distance in the reason" .. tag, why:find("m away", 1, true) ~= nil, true)

	World.camera = { yaw = 0, pitch = Down(80) }
	aim = addon:AimPoint()
	near("looking almost straight down is a point at the feet" .. tag, aim.distance, 160 / math.tan(math.rad(80)), 3)

	-- a third-person camera, set back: the point can be a little behind the player
	World.camera = { yaw = 0, pitch = Down(45), back = 300 }
	aim = addon:AimPoint()
	check("a third-person camera still finds the floor" .. tag, aim ~= nil, true)
	near("a little behind the player is allowed" .. tag, aim and (aim.z - 2100), 160 - 300, 3)
	World.camera = { yaw = 0, pitch = Down(45), back = 600 }
	aim, why = addon:AimPoint()
	check("well behind the player is not" .. tag, aim, nil)
	check("and says so" .. tag, why, "the point is behind you")
end

-- without the camera's direction, the answers are compared: aim lower, and a point in front comes nearer
addon = AimWorld()
local savedForward = GetCameraForward
GetCameraForward = nil
World.camera = { yaw = 0, pitch = Down(30) }
check("with no camera direction, looking down still works", addon:AimPoint() ~= nil, true)
World.rayBehindReturns = true
World.camera = { yaw = 0, pitch = math.rad(20) }
local upAim, upWhy = addon:AimPoint()
check("looking up is told from looking down by aiming lower", upAim, nil)
check("with its own reason", upWhy, "the cursor is pointing above the horizon")
GetCameraForward = savedForward
World.rayBehindReturns = false

-- the command that shows it
addon = AimWorld()
World.camera = { yaw = 0, pitch = Down(30) }
ChatClear()
Cmd("/pbfe aim")
check("/pbfe aim prints the floor point", ChatHas("the cursor meets your floor at x 1100"), true)
check("and the camera's direction", ChatHas("camera forward:"), true)
World.camera = { yaw = 0, pitch = math.rad(30) }
ChatClear()
Cmd("/pbfe aim")
check("and why not, when it cannot", ChatHas("no point: the cursor is not pointing down at the floor"), true)

-- a typed paste, at the cursor
addon = ResvWorld()
Cmd("/pbfe copy 1")
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.camera = { yaw = 0, pitch = Down(30) }
ChatClear()
Cmd("/pbfe paste aim")
check("the plan is for the cursor", ChatHas("plan: aim"), true)
check("and ready", ChatHas("ready. to place: /pbfe paste aim go"), true)
Cmd("/pbfe paste aim go")
RunUntilIdle()
check("it places the group", CountOf(2), 4)
near("the table is at the cursor point, by its offset from where you copied: x", FindByData(2, TABLE)[1].x, 5000 - 100, 3)
near("z", FindByData(2, TABLE)[1].z, 5000 + AHEAD_30 - 100, 3)
near("at the floor you stand on", FindByData(2, TABLE)[1].y, 0, 0)
check("and linked", ChatHas("linked 3 / 3"), true)

-- up lifts it
addon = ResvWorld()
Cmd("/pbfe copy 1")
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.camera = { yaw = 0, pitch = Down(30) }
Cmd("/pbfe paste aim up 50 go")
RunUntilIdle()
near("'up' lifts a paste at the cursor", FindByData(2, TABLE)[1].y, 50, 0)

-- nothing to point at: no paste, and not even with force
addon = ResvWorld()
Cmd("/pbfe copy 1")
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.camera = { yaw = 0, pitch = math.rad(20) }
ChatClear()
Cmd("/pbfe paste aim")
check("with the cursor in the air the plan says so", ChatHas("could not read where the cursor points"), true)
check("and offers 'here'", ChatHas("use 'here'"), true)
Cmd("/pbfe paste aim force go")
RunUntilIdle()
check("it will not place anything, force or not", CountOf(2), 0)

-- the wheel: the point is taken at the pick, before the camera can move
addon = AimWorld()
Cmd("/pbfe reserve copy 1 to 2 aim")
check("'aim' is accepted as a word of a reservation", table.concat(addon.sv.reservations[1].words, " "), "aim")
Arrive(2)
RunFor(6000)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.camera = { yaw = math.rad(90), pitch = Down(30) }       -- the player looks at a spot to the side...
wheel:ShowMenu()
wheel:Select(9)                                               -- ...lets go of the button...
World.camera = { yaw = 0, pitch = math.rad(40) }              -- ...and swings the camera away at once
RunUntilIdle()
check("the group is placed", CountOf(2), 4)
near("where the cursor pointed at the pick: x", FindByData(2, TABLE)[1].x, 5000 + AHEAD_30 - 100, 3)
near("where the cursor pointed at the pick: z", FindByData(2, TABLE)[1].z, 5000 - 100, 3)

-- a pick whose cursor cannot be read does not fail: it pastes where you stand, and says so
addon = AimWorld()
Cmd("/pbfe reserve copy 1 to 2 aim")
Arrive(2)
RunFor(6000)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.camera = { yaw = 0, pitch = 0 }                 -- looking at the horizon
wheel:ShowMenu()
ChatClear()
wheel:Select(9)
RunUntilIdle()
check("a pick with the cursor at the horizon says why it stood in", ChatHas("could not read where the cursor points"), true)
check("and where it put the group instead", ChatHas("placing where you stand instead"), true)
check("the group is placed", CountOf(2), 4)
near("at your feet: x", FindByData(2, TABLE)[1].x, 5000 + (1000 - 1100), 3)
near("at your feet: z", FindByData(2, TABLE)[1].z, 5000 + (2000 - 2100), 3)
check("the reservation is done", #addon.sv.reservations, 0)
check("and the wheel is back", wheel:ShowMenu(), 8)

-- two waiting pastes share the point of one pick
addon = AimWorld()
Cmd("/pbfe reserve copy 1 to 2 aim")
Cmd("/pbfe reserve copy 2 to 2 aim")
Arrive(2)
RunFor(6000)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.camera = { yaw = 0, pitch = Down(30) }
wheel:ShowMenu()
wheel:Select(9)
RunUntilIdle()
check("both groups are placed", CountOf(2), 6)
near("the second is placed from the same point: the shelf", FindByData(2, SHELF)[1].z, 5000 + AHEAD_30 + (200 - 2100), 3)

-- an automatic reservation at a doorway waits for the player
addon = AimWorld()
Cmd("/pbfe reserve copy 1 to 2 aim go")
ChatClear()
Arrive(2)
RunUntilIdle()
check("aim ... go at the doorway shows the plan and waits", ChatHas("you arrive at the doorway"), true)
check("the plan says the point is read on the pick", ChatHas("the cursor position is read when you pick Paste"), true)
check("nothing is placed", CountOf(2), 0)

-- where the wheel pastes: /pbfe position
addon = EditorWorld()
check("the default is the cursor", addon.sv.pasteMode, "aim")
ChatClear()
Cmd("/pbfe position")
check("/pbfe position says what it is", ChatHas("the wheel pastes: aim"), true)
Cmd("/pbfe position nonsense")
check("a word it does not know changes nothing", addon.sv.pasteMode, "aim")

addon = EditorWorld()
Cmd("/pbfe position here")
check("here is stored", addon.sv.pasteMode, "here")
World.target = TABLE_ID
Settle("rebuild")
PressKey(CIRCLE)
RunFor(50)
Arrive(2)
RunFor(6000)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.camera = { yaw = 0, pitch = Down(30) }          -- the cursor is perfectly readable...
wheel:ShowMenu()
wheel:Select(9)
RunUntilIdle()
check("with 'here', a pick pastes at your feet", CountOf(2), 4)
near("not at the cursor: z", FindByData(2, TABLE)[1].z, 5000 + (2000 - 2100), 3)

addon = EditorWorld()
Cmd("/pbfe position same")
World.target = TABLE_ID
Settle("rebuild")
PressKey(CIRCLE)
RunFor(50)
Arrive(2)
RunFor(6000)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
wheel:ShowMenu()
wheel:Select(9)
RunUntilIdle()
check("with 'same', a pick pastes at the original coordinates", CountOf(2), 4)
near("x", FindByData(2, TABLE)[1].x, 1000, 3)
near("z", FindByData(2, TABLE)[1].z, 2000, 3)

-- the editor's copy with an unreadable cursor: still pasted, where you stand
addon = EditorWorld()
World.target = TABLE_ID
Settle("rebuild")
PressKey(CIRCLE)
RunFor(50)
Arrive(2)
RunFor(6000)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.camera = { yaw = 0, pitch = math.rad(30) }       -- looking up
wheel:ShowMenu()
ChatClear()
wheel:Select(9)
RunUntilIdle()
check("a pick with the cursor in the air still pastes", CountOf(2), 4)
check("and says it stood in", ChatHas("placing where you stand instead"), true)

-- an error while reading the cursor must not stop the pick either
addon = EditorWorld()
World.target = TABLE_ID
Settle("rebuild")
PressKey(CIRCLE)
RunFor(50)
Arrive(2)
RunFor(6000)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
local savedAim = addon.AimPoint
addon.AimPoint = function() error("the camera exploded") end
wheel:ShowMenu()
wheel:Select(9)
RunUntilIdle()
addon.AimPoint = savedAim
check("an error in the cursor read does not stop the paste", CountOf(2), 4)

-- ---------------------------------------------------------------------------------------
section("27. a cut counts the slots it will need, stacks and all")
-- ---------------------------------------------------------------------------------------
-- A group of a table, two candles and a vase: three kinds, four pieces. The bags are empty unless a
-- test puts something in them.
local function RoomWorld()
	ResetWorld()
	AddHouse(1, { name = "Home" })
	AddHouse(2, { name = "Cottage" })
	local tbl = AddFurniture(1, { dataId = TABLE, name = "Redguard Table", x = 1000, y = 100, z = 2000 })
	local c1 = AddFurniture(1, { dataId = CANDLE, name = "Candle", x = 1010, y = 120, z = 2000, parent = tbl })
	AddFurniture(1, { dataId = CANDLE, name = "Candle", x = 990, y = 120, z = 2000, parent = tbl })
	AddFurniture(1, { dataId = VASE, name = "Vase", x = 1010, y = 160, z = 2000, parent = c1 })
	EnterHouse(1)
	World.player = { x = 1000, y = 100, z = 2000, rot = 0 }
	World.noStackInfo = true          -- the item link does not say whether it stacks: the cut has to estimate
	local a = LoadAddon()
	Cmd("/pbfe list")
	ChatClear()
	return a
end

-- kinds nobody has seen: the need is a range, and only a shortfall below its LOW end is refused
addon = RoomWorld()
World.bagLimit = { [BAG_BACKPACK] = 2 }
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("two free slots, three kinds at least: refused", ChatHas("not enough room in the backpack: 2 free, at least 3 needed"), true)
check("so nothing is taken out", CountOf(1), 4)
check("and the clipboard is empty", addon.sv.clip, nil)

addon = RoomWorld()
World.bagLimit = { [BAG_BACKPACK] = 3 }
ChatClear()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("three free slots is inside the range: it warns", ChatHas("it may fill up"), true)
check("and goes ahead", CountOf(1), 0)
check("the candles shared a slot, as stacks do", ItemCount(CANDLE), 2)
check("so it fitted", ChatHas("took out 4 / 4"), true)

-- what the bags teach is kept, so the next preview is exact
check("nothing is known about the kinds before they have been in a bag", next(addon.sv.stackMax), nil)
Cmd("/pbfe paste same go")
RunUntilIdle()
check("put back", CountOf(1), 4)
check("looking in the bags for the paste taught the stack maximum of each kind", addon.sv.stackMax[CANDLE] == 200 and addon.sv.stackMax[TABLE] == 200 and addon.sv.stackMax[VASE] == 200, true)
World.bagLimit = nil
Cmd("/pbfe list")
ChatClear()
Cmd("/pbfe cut 1")
check("the next preview is exact, no range", ChatHas("40 free slots, 3 needed") and not ChatHas("up to"), true)

-- a stack that has room takes the retrieved pieces without a new slot
addon = RoomWorld()
GiveItem(BAG_BACKPACK, 0, CANDLE, 195, "Candle")           -- room for five more
World.bagLimit = { [BAG_BACKPACK] = 3 }                    -- one slot is used: two free
ChatClear()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("candles that fit in an existing stack need no slot: two free is enough", ChatHas("2 free slots, 2 needed"), true)
check("so the cut went through", CountOf(1), 0)
check("and the candles joined the stack", ItemCount(CANDLE), 197)

-- a stack that is full does not
addon = RoomWorld()
GiveItem(BAG_BACKPACK, 0, CANDLE, 200, "Candle")
World.bagLimit = { [BAG_BACKPACK] = 3 }                    -- two free
ChatClear()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("a full stack takes nothing: the candles need a slot of their own", ChatHas("2 free, at least 3 needed"), true)
check("so it is refused", CountOf(1), 4)

-- a kind that does not stack is learned from another bag
addon = RoomWorld()
World.stackMaxFor = { [CANDLE] = 1 }
GiveItem(BAG_BANK, 0, CANDLE, 1, "Candle")                 -- the bank holds one, which shows the maximum
World.bagLimit = { [BAG_BACKPACK] = 3 }
ChatClear()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("candles that do not stack need a slot each: four slots, three free", ChatHas("3 free, at least 4 needed"), true)
check("and as it is known, it is not a range", ChatHas("up to"), false)
check("so it is refused", CountOf(1), 4)
check("the maximum was learned", addon.sv.stackMax[CANDLE], 1)

-- ...and remembered when the bank no longer shows it
World.bags[BAG_BANK] = nil
ChatClear()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("a learned maximum is used when no bag shows it", ChatHas("3 free, at least 4 needed"), true)

-- an estimate that turns out wrong stops safely, and nothing is lost
addon = RoomWorld()
World.stackMaxFor = { [CANDLE] = 1 }                       -- the add-on has not seen this kind
World.bagLimit = { [BAG_BACKPACK] = 3 }
ChatClear()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("it was inside the range, so it started", ChatHas("it may fill up"), true)
check("and the bag filled: the game said so and it stopped", ChatHas("stopped: ITEM_REMOVE_FAILED_INVENTORY_FULL"), true)
check("one piece is still in the house", CountOf(1), 1)
check("three are in the bag", ItemCount(TABLE) + ItemCount(CANDLE) + ItemCount(VASE), 3)
check("the clipboard holds all four", #addon.sv.clip.nodes, 4)
check("it says the bag is full and how to go on", ChatHas("is full. Make room, then press Cut") and ChatHas("/pbfe cut resume go: "), true)
World.bagLimit = nil
Cmd("/pbfe cut resume go")
RunUntilIdle()
check("with room made, resume finishes the cut", CountOf(1), 0)

-- 'force' still starts one that is certain not to fit, and it stops where the bag is full
addon = RoomWorld()
World.bagLimit = { [BAG_BACKPACK] = 2 }
Cmd("/pbfe cut 1 force go")
RunUntilIdle()
check("force starts it anyway", ChatHas("going on: 'force'"), true)
check("and it stops when the bag is full", ChatHas("stopped: ITEM_REMOVE_FAILED_INVENTORY_FULL"), true)
check("with the rest still in the house", CountOf(1), 1)

-- collectibles take no slot
ResetWorld()
AddHouse(1, { name = "Home" })
local stand = AddFurniture(1, { dataId = 100, name = "Crown Stand", x = 0, y = 0, z = 0, collectibleId = 555 })
AddFurniture(1, { dataId = 101, name = "Ornament", x = 10, y = 50, z = 0, parent = stand })
EnterHouse(1)
World.player = { x = 0, y = 0, z = 0, rot = 0 }
addon = LoadAddon()
Cmd("/pbfe list")
World.bagLimit = { [BAG_BACKPACK] = 1 }
ChatClear()
Cmd("/pbfe cut 1")
check("a collectible takes no slot: one item, one slot", ChatHas("1 free slots, 1 needed"), true)

-- ---------------------------------------------------------------------------------------
section("28. a paste empties the clipboard")
-- ---------------------------------------------------------------------------------------
-- A copy that was pasted has done its job: the clipboard is emptied, so it does not sit there to be pasted
-- again by mistake. It stays when something was not placed.

-- a plan alone does not use it up
addon = Fresh()
Cmd("/pbfe paste")
Cmd("/pbfe paste same")
check("a plan only shows what would happen: the clipboard stays", addon.sv.clip ~= nil, true)
check("and stays fresh", addon.sv.clipFresh, true)

-- a complete paste does
ChatClear()
Cmd("/pbfe paste go")
RunUntilIdle()
check("everything is placed", CountOf(2), 4)
check("the clipboard is empty", addon.sv.clip, nil)
check("not fresh either", addon.sv.clipFresh, false)
check("it says so, and how to keep one", ChatHas("pasted; the clipboard is emptied (/pbfe save <name> before a paste keeps a copy)"), true)
Cmd("/pbfe show")
check("show agrees", ChatHas("the clipboard is empty"), true)
check("it stays empty after a reload of the UI", LoadAddon().sv.clip, nil)
check("undo still takes the pasted group back", #addon.sv.lastPaste.keys, 4)
Cmd("/pbfe undo")
RunUntilIdle()
check("without the clipboard", CountOf(2), 0)

-- a copy saved under a name is the way to keep one
Cmd("/pbfe load t")
check("the saved copy is still there", addon.sv.clip ~= nil and #addon.sv.clip.nodes, 4)
Cmd("/pbfe paste go")
RunUntilIdle()
check("and pastes again", CountOf(2), 4)
check("and empties the clipboard again", addon.sv.clip, nil)
check("the saved copy is untouched", #addon.sv.library.t.nodes, 4)

-- nothing placed: the clipboard stays, for another try
addon = Fresh()
World.bags[BAG_BACKPACK][2] = nil
Cmd("/pbfe paste go")
RunUntilIdle()
check("a refused paste places nothing", CountOf(2), 0)
check("and keeps the clipboard", addon.sv.clip ~= nil, true)
check("and the wheel offer", addon.sv.clipFresh, true)

-- part of it placed: the clipboard stays, and says so
ChatClear()
Cmd("/pbfe paste force go")
RunUntilIdle()
check("force places what there is", CountOf(2), 3)
check("the clipboard is kept", addon.sv.clip ~= nil and #addon.sv.clip.nodes, 4)
check("it says how many were not placed", ChatHas("1 not placed: the clipboard is kept, so it can be tried again"), true)
check("it does not say it was emptied", ChatHas("the clipboard is emptied"), false)
check("the wheel offer is over, a placement happened", addon.sv.clipFresh, false)

-- stopped part way: the same
addon = Fresh()
Cmd("/pbfe paste go")
RunFor(900)
Cmd("/pbfe stop")
RunUntilIdle()
check("a stopped paste placed some", CountOf(2) > 0 and CountOf(2) < 4, true)
check("and keeps the clipboard", addon.sv.clip ~= nil, true)

-- a finished move leaves nothing pending: the next copy or cut is no longer refused
addon = CutWorld()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("while the cut waits, a new clipboard is refused", addon:PendingCutBlocks(false), true)
Cmd("/pbfe paste to 2 same go")
RunUntilIdle()
check("the move is complete", CountOf(2), 4)
check("the clipboard is empty", addon.sv.clip, nil)
ChatClear()
check("so nothing blocks the next copy", addon:PendingCutBlocks(false), false)

-- a half-done move keeps the record of where the rest goes
addon = CutWorld()
World.bagLimit = { [BAG_BACKPACK] = 2 }
Cmd("/pbfe cut 1 force go")
RunUntilIdle()
Cmd("/pbfe paste same go")
RunUntilIdle()
check("what was out is back, the table never left", CountOf(1), 5)
check("a cut that is whole again is over: the clipboard is empty", addon.sv.clip, nil)

-- another clipboard's reservation does not touch this one
addon = ResvWorld()
Cmd("/pbfe copy 2")
Cmd("/pbfe reserve copy 1 to 2 same go")
Arrive(2)
RunUntilIdle()
check("the reservation pasted its own group", CountOf(2), 4)
check("the clipboard is not the reservation's: it stays", addon.sv.clip ~= nil and addon.sv.clip.nodes[1].name, "Bookshelf")

-- ---------------------------------------------------------------------------------------
section("29. big link groups")
-- ---------------------------------------------------------------------------------------
-- ESO lets one furnishing take 50 children, and a child can have children of its own. The biggest group
-- here is a base with 50 panels, five of which carry six pins each: 81 furnishings, 80 links.
local BASE, PANEL, PIN = 800, 801, 802

local function BigWorld(panels, carriers, pins)
	ResetWorld()
	AddHouse(1, { name = "Home" })
	AddHouse(2, { name = "Cottage" })
	local base = AddFurniture(1, { dataId = BASE, name = "Base", x = 1000, y = 0, z = 2000 })
	for i = 1, panels do
		local panel = AddFurniture(1, { dataId = PANEL, name = "Panel", x = 1000 + i * 100, y = 50, z = 2000, parent = base })
		if i <= carriers then
			for j = 1, pins do
				AddFurniture(1, { dataId = PIN, name = "Pin", x = 1000 + i * 100, y = 100 + j * 20, z = 2000 + j * 100, parent = panel })
			end
		end
	end
	GiveItem(BAG_BACKPACK, 0, BASE, 1, "Base")
	GiveItem(BAG_BACKPACK, 1, PANEL, panels, "Panel")
	GiveItem(BAG_BACKPACK, 2, PIN, carriers * pins, "Pin")
	World.maxChildren = 50
	EnterHouse(1)
	World.player = { x = 1000, y = 0, z = 1900, rot = 0 }
	local a = LoadAddon()
	Cmd("/pbfe list")
	Cmd("/pbfe copy 1")
	EnterHouse(2)
	World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
	ChatClear()
	return a
end

-- how many children each furnishing of a house has, and whether every one of them hangs from the base
local function Shape(houseId)
	local most, rootless = 0, 0
	local kids = {}
	local furniture = World.houses[houseId].furniture
	for _, f in pairs(furniture) do
		if f.parent then kids[f.parent] = (kids[f.parent] or 0) + 1 end
	end
	for _, count in pairs(kids) do most = math.max(most, count) end
	for _, f in pairs(furniture) do
		local top, guard = f, 0
		while top.parent and guard < 100 do top = furniture[top.parent]; guard = guard + 1 end
		if top.dataId ~= BASE then rootless = rootless + 1 end
	end
	return most, rootless
end

-- the largest group the game allows a parent
addon = BigWorld(50, 5, 6)
check("the clipboard holds all 81", #addon.sv.clip.nodes, 81)
Cmd("/pbfe paste")
check("the plan says how wide it is", ChatHas("links: 80, most children on one furnishing: 50 (ESO's limit is 50)"), true)
check("and does not call it over the limit", ChatHas("over the limit"), false)
ChatClear()
Cmd("/pbfe paste go")
check("it says roughly how long", ChatHas("placing 81 furnishings, 450 ms apart, about 3 min"), true)
RunUntilIdle()
check("all 81 are placed", CountOf(2), 81)
check("and all 80 linked", ChatHas("linked 80 / 80, 0 failed"), true)
local most, rootless = Shape(2)
check("the base has its 50 children", most, 50)
check("every piece hangs from the base", rootless, 0)
check("progress is reported on the way", ChatHas("linked 40 / 80"), true)
check("nothing needed a second try", ChatHas("went through on another try"), false)
check("the paste is complete", addon.sv.clip, nil)

-- a server that says "not now" to some requests, as a busy one does
addon = BigWorld(50, 5, 6)
World.flaky = { place = 5, link = 6 }
Cmd("/pbfe paste go")
RunUntilIdle()
check("every fifth placement and sixth link failed, and all 81 are there", CountOf(2), 81)
check("exactly 81: nothing twice", #FindByData(2, PANEL) + #FindByData(2, BASE) + #FindByData(2, PIN), 81)
check("all 80 links made", ChatHas("linked 80 / 80, 0 failed"), true)
check("it says some needed another try", ChatHas("failed the first time and went through on another try"), true)
most, rootless = Shape(2)
check("the shape is whole", most == 50 and rootless == 0, true)
check("so the paste counts as done", addon.sv.clip, nil)

-- answers that come long after the wait: the piece is taken in as the one that was missing
addon = BigWorld(50, 5, 6)
World.slowPlace = { every = 9, delay = 8000 }
Cmd("/pbfe paste go")
RunUntilIdle()
check("every ninth placement answered 2 s late, and all 81 are there once", CountOf(2), 81)
check("it says they were taken in", ChatHas("they were taken in as the pieces they were"), true)
check("all 80 links made", ChatHas("linked 80 / 80, 0 failed"), true)
most, rootless = Shape(2)
check("the shape is whole", most == 50 and rootless == 0, true)

-- a group wider than the server allows: the rest go under their siblings
addon = BigWorld(25, 0, 0)
World.maxChildren = 10
Cmd("/pbfe paste")
check("the plan notes nothing over the documented limit", ChatHas("over the limit"), false)
ChatClear()
Cmd("/pbfe paste go")
RunUntilIdle()
check("all 26 are placed", CountOf(2), 26)
check("and all 25 linked", ChatHas("linked 25 / 25, 0 failed"), true)
check("it names the limit it found", ChatHas("takes no more than 10 children"), true)
check("and how many links moved", ChatHas("15 links were made under a sibling because a furnishing took no more than 10 children"), true)
most, rootless = Shape(2)
check("nothing has more than 10", most <= 10, true)
check("it is still one tree", rootless, 0)
check("done", addon.sv.clip, nil)

-- a group wider than 50 says so in the plan
addon = BigWorld(52, 0, 0)
World.maxChildren = 50
Cmd("/pbfe paste")
check("the plan warns of what is over the limit", ChatHas("most children on one furnishing: 52 (ESO's limit is 50)"), true)
check("and what will happen", ChatHas("over the limit: the extra links are made under a sibling"), true)
Cmd("/pbfe paste go")
RunUntilIdle()
check("it is placed and linked as one tree", CountOf(2) == 53 and select(2, Shape(2)) == 0, true)
check("with 50 at most", (Shape(2)) <= 50, true)
check("and says what it did", ChatHas("2 links were made under a sibling because a furnishing took no more than 50 children"), true)

-- a link that never takes ends, and says so
addon = BigWorld(6, 0, 0)
World.flaky = { link = 1 }
Cmd("/pbfe paste go")
RunUntilIdle()
check("the pieces are placed", CountOf(2), 7)
check("the links that failed are asked for again, then given up", ChatHas("links did not take; trying them again (round 4)"), true)
check("it does not go on for ever when nothing gets through", ChatHas("(round 5)"), false)
check("none were made", ChatHas("linked 0 / 6, 6 failed"), true)
check("and the clipboard is kept for another try", addon.sv.clip ~= nil, true)

-- a cut of a big group, on a server that fails some removals
addon = BigWorld(50, 5, 6)
EnterHouse(1)
World.player = { x = 1000, y = 0, z = 1900, rot = 0 }
Cmd("/pbfe list")
World.bags[BAG_BACKPACK] = {}                -- what the paste into house 2 had to use: gone, only the cut's remain
ChatClear()
World.flaky = { remove = 5 }
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("all 81 left the house despite every fifth removal failing", CountOf(1), 0)
check("it says so", ChatHas("took out 81 / 81"), true)
check("none left behind", ChatHas("still here"), false)
check("the bag holds them", ItemCount(PANEL) == 50 and ItemCount(PIN) == 30 and ItemCount(BASE) == 1, true)

-- and the whole move: cut, then paste in the other house
World.flaky = { place = 7, link = 5 }
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
Cmd("/pbfe paste to 2 same go")
RunUntilIdle()
check("the move arrives whole in the other house", CountOf(2), 81)
most, rootless = Shape(2)
check("with its shape", most == 50 and rootless == 0, true)
check("and the move is complete", addon.sv.clip, nil)

-- ---------------------------------------------------------------------------------------
section("30. a flaky server, many times over")
-- ---------------------------------------------------------------------------------------
-- The same group on a server that fails requests at random (and answers some placements late), over many
-- seeds. Whatever the dice say, the house ends up with exactly the group: each piece once, one tree.
local bad = {}
for seed = 1, 25 do
	math.randomseed(seed)
	addon = BigWorld(12, 3, 3)           -- 1 + 12 + 9 = 22 furnishings
	World.chance = { place = 0.25, link = 0.25 }
	if seed % 3 == 0 then World.slowPlace = { chance = 0.08, delay = 9000 } end
	Cmd("/pbfe paste go")
	RunUntilIdle()
	local _, rootless = Shape(2)
	if CountOf(2) ~= 22 or rootless ~= 0 or addon.sv.clip ~= nil then
		bad[#bad + 1] = string.format("seed %d: %d placed, %d off the tree, clipboard %s", seed, CountOf(2), rootless, addon.sv.clip and "kept" or "empty")
	end
end
check("25 random runs all end whole" .. (#bad > 0 and (": " .. table.concat(bad, "; ")) or ""), #bad, 0)

bad = {}
for seed = 1, 15 do
	math.randomseed(100 + seed)
	addon = BigWorld(12, 3, 3)
	EnterHouse(1)
	World.player = { x = 1000, y = 0, z = 1900, rot = 0 }
	Cmd("/pbfe list")
	World.bags[BAG_BACKPACK] = {}
	World.chance = { remove = 0.2 }
	Cmd("/pbfe cut 1 go")
	RunUntilIdle()
	if CountOf(1) ~= 0 then
		bad[#bad + 1] = string.format("seed %d: %d left", 100 + seed, CountOf(1))
	end
end
check("15 random cuts all take everything out" .. (#bad > 0 and (": " .. table.concat(bad, "; ")) or ""), #bad, 0)

-- ---------------------------------------------------------------------------------------
section("31. a cut on a server that is busy between requests")
-- ---------------------------------------------------------------------------------------
-- Every removal meets a "not yet" and is asked again. That is counted per furnishing, not over the whole
-- cut: twenty-two removals used to run the allowance out after ten, and the rest were left standing.
addon = BigWorld(12, 3, 3)
EnterHouse(1)
World.player = { x = 1000, y = 0, z = 1900, rot = 0 }
Cmd("/pbfe list")
World.bags[BAG_BACKPACK] = {}
World.cooldown = 700
ChatClear()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("all 22 are out", CountOf(1), 0)
check("at the first pass: nobody was left to ask for again", ChatHas("still there; asking again"), false)
check("and nothing failed", ChatHas("took out 22 / 22, 0 were already out, 0 failed"), true)

-- ---------------------------------------------------------------------------------------
section("32. one group of every kind of furnishing")
-- ---------------------------------------------------------------------------------------
-- A linked group can hold a crafted item (traditional), a crate item that is a special furnishing, a Crown
-- Store collectible, and a special collectible. Each is placed by a different call and counted against a
-- different one of the house's four limits.
local CRAFTED, SPECIAL, CRATE, TRIM = 902, 900, 901, 903
local LAMP, BANNER = 7001, 7002

local function MixedWorld()
	ResetWorld()
	AddHouse(1, { name = "Home" })
	AddHouse(2, { name = "Cottage" })
	World.limitTypeOf = { [SPECIAL] = 0, [906] = 0, [907] = 0 }
	local table_ = AddFurniture(1, { dataId = CRAFTED, name = "Crafted Table", x = 1000, y = 0, z = 2000 })
	local case = AddFurniture(1, { dataId = SPECIAL, name = "Display Case", x = 1100, y = 0, z = 2000, parent = table_, limitType = 0 })
	AddFurniture(1, { dataId = CRATE, name = "Crate Statue", x = 900, y = 0, z = 2000, parent = table_ })
	local lamp = AddFurniture(1, { dataId = 9000 + LAMP, name = "Crown Lamp", x = 1000, y = 0, z = 2100, parent = table_, collectibleId = LAMP, limitType = 3 })
	AddFurniture(1, { dataId = 9000 + BANNER, name = "Grand Banner", x = 1100, y = 100, z = 2000, parent = case, collectibleId = BANNER, limitType = 1 })
	AddFurniture(1, { dataId = TRIM, name = "Gold Trim", x = 1000, y = 50, z = 2100, parent = lamp })
	for slot, dataId in ipairs({ CRAFTED, SPECIAL, CRATE, TRIM }) do
		GiveItem(BAG_BACKPACK, slot - 1, dataId, 1, "Item " .. dataId)
	end
	World.limitTypeOfCollectible = { [BANNER] = 1 }
	EnterHouse(1)
	World.player = { x = 1000, y = 0, z = 1900, rot = 0 }
	local a = LoadAddon()
	Cmd("/pbfe list")
	Cmd("/pbfe copy 1")
	EnterHouse(2)
	World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
	ChatClear()
	return a
end

local function PlacedBy(name) return #CallsTo(name) end

-- everything fits
addon = MixedWorld()
EnterHouse(1)
World.player = { x = 1000, y = 0, z = 1900, rot = 0 }
ChatClear()
Cmd("/pbfe kind 6")
check("kind says which limit each counts against", ChatHas("counts against the special limit") and ChatHas("counts against the special collectible limit")
	and ChatHas("counts against the traditional limit") and ChatHas("counts against the collectible limit"), true)
check("what the bags hold of an item", ChatHas("copies in your bags: 1"), true)
check("and whether a collectible can be placed", ChatHas("can be placed from your collection: true"), true)
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.houses[2].limits = { [2] = 10, [3] = 5, [0] = 2, [1] = 1 }
Cmd("/pbfe show")
check("the clipboard says what kinds it holds", ChatHas("by the house's limits: 3 traditional, 1 special, 1 collectible, 1 special collectible"), true)
ChatClear()
Cmd("/pbfe paste")
check("the plan shows each limit against the group: traditional", ChatHas("traditional furnishings: 3 to place, room for 10"), true)
check("special", ChatHas("special furnishings: 1 to place, room for 2"), true)
check("collectible", ChatHas("collectible furnishings: 1 to place, room for 5"), true)
check("special collectible", ChatHas("special collectible furnishings: 1 to place, room for 1"), true)
Cmd("/pbfe paste go")
RunUntilIdle()
check("all six are placed", CountOf(2), 6)
check("the two collectibles were placed by the collectible call", PlacedBy("HousingEditorRequestCollectiblePlacement"), 2)
check("and the items by the item call (one request more for the mode change)", PlacedBy("HousingEditorRequestItemPlacement") <= 5, true)
check("each of the six is there once", #FindByData(2, CRAFTED) + #FindByData(2, SPECIAL) + #FindByData(2, CRATE) + #FindByData(2, TRIM)
	+ #FindByData(2, 9000 + LAMP) + #FindByData(2, 9000 + BANNER), 6)
check("all five links are made", ChatHas("linked 5 / 5, 0 failed"), true)
check("the paste is complete", addon.sv.clip, nil)

-- the special limit is full: the special piece is refused, nothing else is
addon = MixedWorld()
World.houses[2].limits = { [2] = 10, [3] = 5, [0] = 0, [1] = 1 }
Cmd("/pbfe paste")
check("the plan says the special limit is short", ChatHas("limit special: room for 0, need 1"), true)
Cmd("/pbfe paste go")
RunUntilIdle()
check("without force it will not start", CountOf(2), 0)
ChatClear()
Cmd("/pbfe paste force go")
RunUntilIdle()
check("with force the other five are placed", CountOf(2), 5)
check("the paste did not stop on the special limit", ChatHas("stopped:"), false)
check("the one that could not be placed is named", ChatHas("Display Case"), true)
check("the banner on it could not be linked, and says why", ChatHas("link #3 Grand Banner: the parent or child was not placed"), true)
check("the other links were made", ChatHas("linked 3 / 5"), true)
check("the clipboard is kept for another try", addon.sv.clip ~= nil, true)

-- a limit met part way: that kind stops, the others go on
addon = MixedWorld()
World.limitTypeOf[906], World.limitTypeOf[907] = 0, 0
AddFurniture(1, { dataId = 906, name = "Second Case", x = 800, y = 0, z = 2000, parent = 1001, limitType = 0 })
AddFurniture(1, { dataId = 907, name = "Third Case", x = 700, y = 0, z = 2000, parent = 1001, limitType = 0 })
GiveItem(BAG_BACKPACK, 10, 906, 1, "Second Case")
GiveItem(BAG_BACKPACK, 11, 907, 1, "Third Case")
EnterHouse(1)
World.player = { x = 1000, y = 0, z = 1900, rot = 0 }
Cmd("/pbfe list")
Cmd("/pbfe clear")
Cmd("/pbfe copy 1")
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
World.houses[2].limits = { [2] = 10, [3] = 5, [0] = 1, [1] = 1 }
ChatClear()
Cmd("/pbfe paste force go")
RunUntilIdle()
check("one special fits", #FindByData(2, SPECIAL) + #FindByData(2, 906) + #FindByData(2, 907), 1)
check("the first refusal is the game's words", ChatHas("Second Case: <SI_HOUSINGREQUESTRESULT") or ChatHas("Second Case:"), true)
check("the next of that kind is not even asked", ChatHas("Third Case: the house has no room for any more special furnishings"), true)
check("the paste did not stop", ChatHas("stopped:"), false)
check("the traditional pieces and both collectibles were placed", #FindByData(2, CRAFTED) + #FindByData(2, CRATE) + #FindByData(2, TRIM) == 3 and #FindByData(2, 9000 + LAMP) + #FindByData(2, 9000 + BANNER) == 2, true)

-- a cut and a move of the lot
addon = MixedWorld()
World.houses[2].limits = { [2] = 10, [3] = 5, [0] = 2, [1] = 1 }
EnterHouse(1)
World.player = { x = 1000, y = 0, z = 1900, rot = 0 }
Cmd("/pbfe list")
World.bags[BAG_BACKPACK] = {}
ChatClear()
Cmd("/pbfe cut 1")
check("the cut preview says what kinds leave", ChatHas("kinds: 3 traditional, 1 special, 1 collectible, 1 special collectible"), true)
check("and where the collectibles go", ChatHas("collectibles go back to your collection, not to a bag"), true)
check("only the four items need the bag", ChatHas("4 needed"), true)
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("all six left the house", CountOf(1), 0)
check("the four items are in the bag, the collectibles are not", ItemCount(CRAFTED) + ItemCount(SPECIAL) + ItemCount(CRATE) + ItemCount(TRIM), 4)
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
ChatClear()
Cmd("/pbfe paste go")
RunUntilIdle()
check("the move puts all six in the other house", CountOf(2), 6)
check("linked as before", ChatHas("linked 5 / 5, 0 failed"), true)
check("the move is complete", addon.sv.clip, nil)

-- an item the bag already holds one of and may not hold two (unique): that one stays, the rest go
addon = MixedWorld()
EnterHouse(1)
World.player = { x = 1000, y = 0, z = 1900, rot = 0 }
Cmd("/pbfe list")
World.bags[BAG_BACKPACK] = {}
GiveItem(BAG_BACKPACK, 0, CRATE, 1, "Crate Statue")
World.uniqueKinds = { [CRATE] = true }
ChatClear()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("the unique one could not be taken out", #FindByData(1, CRATE), 1)
check("it is named with the game's reason", ChatHas("remove Crate Statue:"), true)
check("the other five are out", CountOf(1), 1)
check("it was not asked for again, for nothing", ChatHas("asking again"), false)
check("the cut is still pending, to be finished", addon.sv.clip ~= nil and addon.sv.clip.cut, true)

-- ---------------------------------------------------------------------------------------
-- the house's performance budget refuses a heavy piece: the light ones still go in
addon = MixedWorld()
World.heavy = { [SPECIAL] = true }
ChatClear()
Cmd("/pbfe paste go")
RunUntilIdle()
check("only the heavy piece is refused", CountOf(2), 5)
check("and said so, in the game's words", ChatHas("Display Case: METRICS_LIMIT_HIT") or ChatHas("Display Case:"), true)
check("the paste did not stop", ChatHas("stopped:"), false)

-- three refused in a row is the budget gone: it stops
addon = MixedWorld()
World.heavy = { [CRAFTED] = true, [SPECIAL] = true, [9000 + BANNER] = true }
ChatClear()
Cmd("/pbfe paste go")
RunUntilIdle()
check("three refusals in a row end it", ChatHas("stopped: "), true)

-- ---------------------------------------------------------------------------------------
section("33. a cut that knows what stacks, and one that can be carried on")
-- ---------------------------------------------------------------------------------------
-- The item link says whether an item stacks (IsItemLinkStackable), and that is recorded when the group is
-- copied. A piece that does not stack takes a bag slot of its own, so a group of them is counted exactly, even
-- when none of that kind is in any bag yet: the cut is refused before it starts instead of stopping half way.
local function CutHome(panels, noStack, slots)
	addon = BigWorld(panels, 0, 0)               -- a base and its panels, in house 1; the clipboard is a copy of them
	if noStack then World.stackMaxFor = { [PANEL] = 1, [BASE] = 1 } end
	EnterHouse(1)
	World.player = { x = 1000, y = 0, z = 1900, rot = 0 }
	Cmd("/pbfe list")
	World.bags[BAG_BACKPACK] = {}
	if slots then World.bagLimit = { [BAG_BACKPACK] = slots } end
	ChatClear()
	return addon
end

CutHome(12, true, 10)
AlertClear()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("the refusal is also put on the screen, for a player who is not looking at the chat", AlertHas("Cut refused: your backpack has 10 free slots, 13 are needed"), true)
check("13 pieces that do not stack, 10 slots: refused up front, with the exact figures", ChatHas("not enough room in the backpack: 10 free, at least 13 needed"), true)
check("it is an exact figure, not a range", ChatHas("up to"), false)
check("nothing was taken out", CountOf(1), 13)
check("and no cut is waiting", addon.sv.clip == nil or addon.sv.clip.cut == nil, true)

CutHome(12, true, 13)
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("with 13 slots it fits, and goes", CountOf(1), 0)
check("and says it needed 13", ChatHas("13 free slots, 13 needed") or ChatHas("13 needed"), true)

-- stacks, by an amount nobody knows: at least two to a slot, so the 12 panels are at most six slots, and the
-- base one: seven in all
CutHome(12, false, 7)
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("pieces that stack need at most half as many slots as pieces: it is certain to fit", ChatHas("it may fill up"), false)
check("and the cut is complete", CountOf(1), 0)

-- a cut that stops because the bag is full can be carried on from the editor
CutHome(12, true, 10)
AlertClear()
Cmd("/pbfe cut 1 force go")
RunUntilIdle()
check("ten are out and the bag is full", CountOf(1), 3)
check("the screen says the cut stopped and why", AlertHas("Cut stopped: 3 of 13 are still in this house (your bag is full)"), true)
check("it says so, and what to do", ChatHas("is full. Make room, then press Cut (square) on one of the furnishings still here"), true)
local standing
for n, f in pairs(World.houses[1].furniture) do standing = { n = n } end

ChatClear()
AlertClear()
addon:PerformEditorKey("copy", standing)
check("the screen says a cut is unfinished", AlertHas("A cut is unfinished: 3 still stand here. Press Cut on one of them to carry on"), true)
check("a copy meanwhile is refused", ChatHas("a cut is still waiting (13 furnishings), so a new copy is refused"), true)
check("and told how many are still standing", ChatHas("3 of its 13 furnishings are still standing in this house: press Cut (square) on one of them"), true)
check("and how to let go of it", ChatHas("/pbfe clear force forgets it"), true)
Cmd("/pbfe cut 1")
check("the command says the same", ChatHas("3 of its 13 furnishings are still standing"), true)

ChatClear()
addon:PerformEditorKey("cut", standing)
RunUntilIdle()
check("Cut on a piece of it, with the bag still full, tries and is refused for room", ChatHas("not enough room in the backpack"), true)
check("so nothing moved", CountOf(1), 3)

World.bagLimit = nil
ChatClear()
AlertClear()
addon:PerformEditorKey("cut", standing)
RunUntilIdle()
check("the screen says it is carrying on, and then that it is done", AlertHas("Carrying on with the cut: 3 to go") and AlertHas("Cut done: 3 furnishings are in your backpack"), true)
check("with room, the same press carries the cut on", ChatHas("carrying on with the cut: 3 of 13 are still standing"), true)
check("and the last three come out", CountOf(1), 0)

ChatClear()
addon:PerformEditorKey("copy", { n = 1 })
check("everything is out: it says to Move or put back", ChatHas("all 13 are out of this house, in your bag: pick Move on the quickslot wheel"), true)
EnterHouse(2)
ChatClear()
addon:PerformEditorKey("copy", { n = 1 })
check("in another house it says where the cut came from", ChatHas("a cut of 13 furnishings from house 1 is waiting"), true)

-- ---------------------------------------------------------------------------------------
section("34. the settings panel: forgetting what is held")
-- ---------------------------------------------------------------------------------------
local CLEAR, CLEAR_ALL, STOP, SHOW = "Clear copy / cut", "Clear everything", "Stop what is running", "Show what is held"

addon = Fresh()
check("the panel is built when the settings library is there", Panel ~= nil and Panel.title, "PB’s FurnitureEditor")
check("and is listed with the typographic apostrophe: an ASCII one makes the library drop \"PB's \"", Panel.title:find("'", 1, true), nil)
check("with two headings, a switch, five buttons and an explanation", #Panel.rows, 9)
check("each button is there", Panel.byLabel[CLEAR] ~= nil and Panel.byLabel[CLEAR_ALL] ~= nil and Panel.byLabel[STOP] ~= nil and Panel.byLabel[SHOW] ~= nil, true)

-- a plain copy goes at once
ChatClear()
AlertClear()
PressRow(SHOW)
check("show says what is held", ChatHas("clipboard: a copy of 4 furnishings (offered on the quickslot wheel)"), true)
check("and what is not", ChatHas("undo record: none") and ChatHas("reservations: 0") and ChatHas("saved clipboards: 1"), true)
PressRow(CLEAR)
check("a copy is forgotten with one press", addon.sv.clip, nil)
check("and is no longer offered", addon.sv.clipFresh, false)
check("it says so, in chat and on the screen", ChatHas("the copy of 4 furnishings forgotten") and AlertHas("Copy forgotten (4 furnishings)"), true)
ChatClear()
PressRow(CLEAR)
check("with nothing held it says so", ChatHas("the clipboard is already empty"), true)
check("the saved clipboard is not touched", addon.sv.library.t ~= nil, true)

-- a cut that has not been pasted is asked twice
addon = CutWorld()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
check("a cut is pending", addon.sv.clip ~= nil and addon.sv.clip.cut, true)
ChatClear()
AlertClear()
PressRow(CLEAR)
check("the first press only asks", addon.sv.clip ~= nil, true)
check("and says what forgetting a cut means", ChatHas("A CUT of 4 furnishings has not been pasted") or ChatHas("a CUT of 4 furnishings has not been pasted"), true)
check("on the screen too", AlertHas("A cut of 4 furnishings is not pasted. Do it again within 10 s to forget it"), true)
PressRow(CLEAR)
check("the second press forgets it", addon.sv.clip, nil)
check("the furnishings stay in the bag", ItemCount(TABLE), 1)

-- ...and the question is not left open for ever
addon = CutWorld()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
PressRow(CLEAR)
RunFor(11000)
PressRow(CLEAR)
check("a second press after the ten seconds are over asks again", addon.sv.clip ~= nil, true)
PressRow(CLEAR)
check("and then forgets", addon.sv.clip, nil)

-- the other button is not the same question
addon = CutWorld()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
PressRow(CLEAR)
PressRow(CLEAR_ALL)
check("an answer to one question is not an answer to the other", addon.sv.clip ~= nil, true)

-- while something runs
addon = Fresh()
Cmd("/pbfe paste go")
RunFor(700)
ChatClear()
PressRow(CLEAR)
check("nothing is forgotten while a paste runs", addon.sv.clip ~= nil and ChatHas("a paste is running: stop it first"), true)
PressRow(STOP)
RunUntilIdle()
check("the stop button stops it", ChatHas("stopped by you") or ChatHas("stopping after the furnishing in flight"), true)
check("so now it can be forgotten", select(1, addon:ClearCopyCut(true)), "cleared")

-- everything: the undo record, the reservations, the trip, the wheel offers; saved clipboards stay
addon = Fresh()
Cmd("/pbfe paste go")
RunUntilIdle()
check("a paste leaves an undo record", addon.sv.lastPaste ~= nil and #addon.sv.lastPaste.keys, 4)
addon.sv.reservations = { { id = 1, houseId = 2, words = { "same", "go" }, label = "x", clip = { nodes = { { name = "n" } } } } }
addon.jump = { houseId = 3 }
addon.tripOffers = { { clip = {} } }
ChatClear()
PressRow(CLEAR_ALL)
check("nothing held that is a cut: one press is enough", addon.sv.lastPaste, nil)
check("the reservations are gone", #addon.sv.reservations, 0)
check("a trip is no longer waiting", addon.jump, nil)
check("and the offers", #addon.tripOffers, 0)
check("saved clipboards are kept", addon.sv.library.t ~= nil, true)
check("it says what it forgot", ChatHas("forgotten: the clipboard (0), the undo record (4), 1 reservations. Saved clipboards (1) are kept."), true)

-- a reservation that holds a cut counts as a cut
addon = Fresh()
addon.sv.clip = nil
addon.sv.reservations = { { id = 1, houseId = 2, words = { "same", "go" }, label = "x", clip = { cut = true, nodes = { { name = "n" } } } } }
ChatClear()
PressRow(CLEAR_ALL)
check("a cut reservation is asked about too", #addon.sv.reservations, 1)
check("and said so", ChatHas("this forgets 1 cut that has not been pasted"), true)
PressRow(CLEAR_ALL)
check("the second press forgets it", #addon.sv.reservations, 0)

-- typed, for anyone without the panel
addon = CutWorld()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
Cmd("/pbfe reset")
check("/pbfe reset asks about a cut", addon.sv.clip ~= nil, true)
Cmd("/pbfe reset force")
check("and force does not", addon.sv.clip, nil)
Cmd("/pbfe reset show")
check("reset show prints the state", ChatHas("clipboard: empty"), true)
Cmd("/pbfe reset all")
check("reset all with nothing held goes through", ChatHas("forgotten: the clipboard (0)"), true)

-- a Japanese client gets Japanese rows
Fresh()
World.language = "jp"
LoadAddon()
check("the rows are in Japanese", Panel.byLabel["コピー／カットをクリア"] ~= nil and Panel.byLabel["保持している内容を表示"] ~= nil, true)
World.language = "en"

-- no library, no panel, and nothing else is the worse for it
local library = LibHarvensAddonSettings
LibHarvensAddonSettings = nil
Panel = nil
addon = Fresh()
check("without the settings library there is no panel", Panel, nil)
check("and the commands still work", select(1, addon:ClearCopyCut(true)), "cleared")
LibHarvensAddonSettings = library

-- ---------------------------------------------------------------------------------------
section("35. a cut still held is said when you arrive")
-- ---------------------------------------------------------------------------------------
-- It is saved with the game, so it is still there after a log-out, and it refuses every new copy and cut. The
-- first the player saw of it was the refusal, with nothing to say where it had come from.
addon = CutWorld()
Cmd("/pbfe cut 1 go")
RunUntilIdle()
addon.sv.clipFresh = false           -- as after a paste that placed only some of it: nothing on the wheel
ChatClear()
Arrive(2)
RunFor(6000)
check("arriving in another house says a cut is still held", ChatHas("a cut of 4 furnishings is still held from an earlier visit:"), true)
check("and where it came from", ChatHas("a cut of 4 furnishings from house 1 is waiting"), true)
check("and how to let go of it", ChatHas("/pbfe clear force forgets it"), true)

ChatClear()
Arrive(1)
RunFor(6000)
check("in the house it came from it says all four are out", ChatHas("all 4 are out of this house, in your bag"), true)

Cmd("/pbfe reset force")
ChatClear()
Arrive(2)
RunFor(6000)
check("once it is forgotten, nothing is said", ChatHas("still held"), false)

-- ---------------------------------------------------------------------------------------
section("36. the progress bar")
-- ---------------------------------------------------------------------------------------
local BAR = "PBsFurnitureEditorProgress"
local function Bar() return Windows[BAR] end
local function BarPart(suffix) return Windows[BAR .. suffix] end

-- run until the paste/cut is over, calling `each` every 200 ms
local function Watch(each)
	local guard = 0
	while addon.run and guard < 3000 do
		RunFor(200)
		if each then each() end
		guard = guard + 1
	end
end

Windows = {}
addon = Fresh()
check("nothing is built until something has to be drawn", Windows[BAR], nil)

-- a paste
local percents, seenDetail = {}, {}
Cmd("/pbfe paste go")
RunFor(300)
check("the window exists, and is shown", Bar() ~= nil and Bar().hidden, false)
check("it takes no clicks", Bar().mouse, false)
check("it is in front, at the top of the screen", Bar().anchors[1].point, TOP)
check("it says what is being done", BarPart("Title").text, "Paste")
Watch(function()
	local drawn = addon.progress.drawn
	if drawn then
		percents[#percents + 1] = drawn.percent
		seenDetail[#seenDetail + 1] = drawn.detail
	end
end)
local monotone = true
for i = 2, #percents do if percents[i] < percents[i - 1] then monotone = false end end
check("the bar only ever fills", monotone, true)
check("and it is full at the end", percents[#percents], 100)
check("it says placing, then linking", (table.concat(seenDetail, "|")):find("placing", 1, true) ~= nil and (table.concat(seenDetail, "|")):find("linking", 1, true) ~= nil, true)
check("it counts what has been done", BarPart("Detail").text:find("7 / 7 (100%)", 1, true) ~= nil, true)
check("and says it is done", BarPart("Detail").text:find("done", 1, true) ~= nil, true)
check("the bar is green at the end", BarPart("Fill").centre[1] < 0.5, true)
check("it stays a moment", Bar().hidden, false)
RunFor(3500)
check("and then goes", Bar().hidden, true)

-- a time, once there is something to go on
addon = BigWorld(30, 0, 0)
Cmd("/pbfe paste go")
local timed = false
Watch(function() if BarPart("Detail") and BarPart("Detail").text:find("left", 1, true) then timed = true end end)
check("it says roughly how long is left", timed, true)

-- a move says Move
addon = CutWorld()
Cmd("/pbfe cut 1 go")
RunFor(300)
check("a cut says Cut", BarPart("Title").text, "Cut")
Watch()
check("the cut counts every piece", BarPart("Detail").text:find("4 / 4 (100%)", 1, true) ~= nil, true)
RunFor(3500)
EnterHouse(2)
World.player = { x = 5000, y = 0, z = 5000, rot = 0 }
Cmd("/pbfe paste go")
RunFor(300)
check("pasting a cut says Move", BarPart("Title").text, "Move")
Watch()
RunFor(3500)

-- undo
Cmd("/pbfe undo")
RunFor(300)
check("undo says Undo", BarPart("Title").text, "Undo")
Watch()
RunFor(3500)

-- what did not go through is said, and the bar is red
addon = Fresh()
World.linkRefusal = HOUSING_REQUEST_RESULT_LINK_FAILED
Cmd("/pbfe paste go")
Watch()
check("it ends short, and says how many failed", BarPart("Detail").text:find("done, 3 failed", 1, true) ~= nil, true)
check("the bar is red", BarPart("Fill").centre[1] > 0.9 and BarPart("Fill").centre[2] < 0.5, true)
RunFor(3500)

-- stopped
addon = Fresh()
Cmd("/pbfe paste go")
RunFor(900)
Cmd("/pbfe stop")
Watch()
check("a stopped run says stopped", BarPart("Detail").text:find("stopped", 1, true) ~= nil, true)
RunFor(3500)

-- a new run while the last one is lingering takes the bar over, and the old hide does not take it away
addon = Fresh()
Cmd("/pbfe paste go")
Watch()
Cmd("/pbfe undo")
RunFor(2800)
Watch()
RunFor(1000)
check("the linger of an earlier run does not hide a later one", Bar().hidden, false)
RunFor(3500)

-- where it sits, and off
Cmd("/pbfe progress bottom")
addon = Fresh()
Cmd("/pbfe progress bottom")
Cmd("/pbfe paste go")
RunFor(300)
check("it can be moved to the bottom", Bar().anchors[1].point, BOTTOM)
Watch()
RunFor(3500)
Cmd("/pbfe progress off")
addon = Fresh()
Cmd("/pbfe progress off")
Bar().hidden = true
Windows[BAR].text = nil
Cmd("/pbfe paste go")
RunFor(300)
check("switched off, a paste does not show it", Bar().hidden, true)
Watch()
check("and the paste is no worse for it", CountOf(2), 4)
Cmd("/pbfe progress on")
check("on again", addon.sv.progress, true)

-- a Japanese client
Windows = {}
addon = Fresh()
World.language = "jp"
LoadAddon()
addon = PBS_FURNITURE_EDITOR
-- (a new add-on table: the clipboard and the houses are still there)
Cmd("/pbfe paste go")
RunFor(300)
check("the words are Japanese", BarPart("Title").text, "ペースト")
Watch()
check("with Japanese counts", BarPart("Detail").text:find("（", 1, true) ~= nil, true)
World.language = "en"
RunFor(3500)

-- a bar that cannot be built turns itself off, once, and nothing else stops
Windows = {}
addon = Fresh()
World.windowFails = "control"
ChatClear()
Cmd("/pbfe paste go")
Watch()
check("the paste goes through without it", CountOf(2), 4)
check("and says once that the bar is off", ChatHas("the progress bar could not be drawn"), true)
ChatClear()
Cmd("/pbfe undo")
Watch()
check("it does not say it again", ChatHas("could not be drawn"), false)
World.windowFails = nil

-- the test bar
Windows = {}
addon = Fresh()
Cmd("/pbfe progress test")
RunFor(3000)
local mid = addon.progress.drawn and addon.progress.drawn.percent
check("the test bar fills over a few seconds", mid ~= nil and mid > 20 and mid < 100, true)
RunFor(4000)
check("and is full, then gone", BarPart("Detail").text:find("100%", 1, true) ~= nil, true)
RunFor(4000)
check("gone", Bar().hidden, true)

-- the settings switch
addon = Fresh()
check("the panel has a switch for it", Panel.byLabel["Show the progress bar"] ~= nil, true)
Panel.byLabel["Show the progress bar"].setFunction(false)
check("which turns it off", addon.sv.progress, false)
check("and reads back", Panel.byLabel["Show the progress bar"].getFunction(), false)
Panel.byLabel["Show the progress bar"].setFunction(true)
PressRow("Show a test bar")
RunFor(500)
check("and a button shows a test bar", Bar() ~= nil and Bar().hidden, false)
RunFor(9000)

-- ---------------------------------------------------------------------------------------
print(string.format("\n%d checks, %d failed", total, failures))
os.exit(failures == 0 and 0 or 1)
