-- Stub of just enough ESO client to exercise PBsFurnitureEditor.
--
-- The add-on runs on a console, where one real test costs a whole session: build, upload, boot
-- the PS5, log in, walk to a house. This stands in for the parts of the client the add-on
-- touches -- houses with furnishings and links, bags, the housing editor's request/answer
-- rhythm, and the events -- so that the logic can be exercised here instead.
--
-- What it models on purpose, because the add-on has to survive each of them:
--   * ids are tables with NO __eq, so two ids for one furnishing do not compare equal with ==
--   * a request is answered at once with a result, and carried out later, with an event
--   * a second request while one is in flight is answered REQUEST_IN_PROGRESS
--   * placing needs a particular editor mode, and says INCORRECT_MODE otherwise
--   * any of the calls can be made "private" (it raises) or "silent" (no event is sent)
-- What it does NOT know is whether the real console behaves like this. That is /pbfe probe.

local DIR = ADDON_DIR

unpack = unpack or table.unpack

-- ---- time and timers ----------------------------------------------------------------
local now = 0
local timers = {}
local timerSeq = 0

function GetGameTimeMilliseconds() return now end
function GetFrameTimeMilliseconds() return now end
function GetTimeStamp() return 1700000000 + math.floor(now / 1000) end

function zo_callLater(fn, ms)
	timerSeq = timerSeq + 1
	timers[#timers + 1] = { at = now + (ms or 0), seq = timerSeq, fn = fn }
	return timerSeq
end

local function NextTimer(limit)
	local best, bestIndex
	for i, t in ipairs(timers) do
		if (not limit or t.at <= limit) and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then
			best, bestIndex = t, i
		end
	end
	return best, bestIndex
end

function RunFor(ms)
	local limit = now + ms
	while true do
		local t, i = NextTimer(limit)
		if not t then break end
		table.remove(timers, i)
		if t.at > now then now = t.at end
		t.fn()
	end
	now = limit
end

function RunUntilIdle(maxMs)
	local limit = now + (maxMs or 600000)
	while true do
		local t, i = NextTimer(limit)
		if not t then break end
		table.remove(timers, i)
		if t.at > now then now = t.at end
		t.fn()
	end
end

function PendingTimers() return #timers end
function Now() return now end

-- ---- chat ---------------------------------------------------------------------------
Chat = {}
CHAT_ROUTER = {
	AddSystemMessage = function(_, text)
		Chat[#Chat + 1] = text
		if VERBOSE then print("[chat] " .. text) end
	end,
}
function d(text) print("[d] " .. tostring(text)) end

-- WINDOW_MANAGER: controls that record what is done to them, so the tests can read the progress bar.
CT_LABEL, CT_BACKDROP = 1, 2
TOPLEFT, TOP, BOTTOM, CENTER, BOTTOMRIGHT = 1, 2, 3, 4, 5
TEXT_ALIGN_CENTER, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP = 1, 2, 3
DL_OVERLAY, DT_HIGH = 6, 7
Windows = {}
local function NewControl(kind, name, parent)
	local control = { kind = kind, name = name, parent = parent, hidden = false, anchors = {}, mouse = true }
	local methods = {
		SetText = function(self, text) self.text = text end,
		SetHidden = function(self, hidden) self.hidden = hidden end,
		SetDimensions = function(self, w, h) self.w, self.h = w, h end,
		SetCenterColor = function(self, r, g, b, a) self.centre = { r, g, b, a } end,
		SetMouseEnabled = function(self, on) self.mouse = on end,
		SetAnchor = function(self, point, rel, relPoint, x, y) self.anchors[#self.anchors + 1] = { point = point, x = x, y = y } end,
		ClearAnchors = function(self) self.anchors = {} end,
	}
	return setmetatable(control, { __index = function(t, key)
		if methods[key] then return methods[key] end
		return function() end          -- every other setter is accepted and ignored
	end })
end
WINDOW_MANAGER = {
	CreateTopLevelWindow = function(_, name)
		if World.windowFails == "window" then error("the window could not be built") end
		Windows[name] = NewControl("window", name)
		return Windows[name]
	end,
	CreateControl = function(_, name, parent, kind)
		if World.windowFails == "control" then error("the control could not be built") end
		Windows[name] = NewControl(kind, name, parent)
		return Windows[name]
	end,
}

-- The settings library (LibHarvensAddonSettings): the rows are recorded by label, so a test can press a button.
Panel = nil
LibHarvensAddonSettings = {
	ST_LABEL = 1, ST_SECTION = 2, ST_CHECKBOX = 3, ST_SLIDER = 4, ST_DROPDOWN = 5, ST_BUTTON = 6,
	AddAddon = function(_, title)
		Panel = {
			title = title,
			rows = {},
			byLabel = {},
			AddSetting = function(self, row)
				self.rows[#self.rows + 1] = row
				if row.label then self.byLabel[row.label] = row end
			end,
		}
		return Panel
	end,
}
function PressRow(label)
	local row = Panel and Panel.byLabel[label]
	assert(row and row.clickHandler, "no button called " .. tostring(label))
	row.clickHandler()
end

-- the client's on-screen alert: kept, for the tests to read
UI_ALERT_CATEGORY_ALERT = 1
Alerts = {}
function ZO_AlertNoSuppression(category, sound, text) Alerts[#Alerts + 1] = tostring(text) end
function AlertText() return table.concat(Alerts, "\n") end
function AlertHas(needle) return string.find(AlertText(), needle, 1, true) ~= nil end
function AlertClear() Alerts = {} end
SLASH_COMMANDS = {}

function ChatText() return table.concat(Chat, "\n") end
function ChatHas(needle) return string.find(ChatText(), needle, 1, true) ~= nil end
function ChatClear() Chat = {} end

function GetString(a, b)
	if b ~= nil then return "<" .. tostring(a) .. ":" .. tostring(b) .. ">" end
	return tostring(a)
end
function zo_strformat(format, ...)
	local args = { ... }
	return (tostring(format):gsub("<<(%d)>>", function(n) return tostring(args[tonumber(n)] or "") end))
end

-- ---- constants ----------------------------------------------------------------------
local RESULT = {
	SUCCESS = 0, PLACE_FAILED = 1, ITEM_REMOVE_FAILED = 2, REMOVE_FAILED = 5, PERMISSION_FAILED = 6,
	INCORRECT_MODE = 21, REQUEST_IN_PROGRESS = 23, ITEM_REMOVE_FAILED_INVENTORY_FULL = 26,
	IN_COMBAT = 27, NOT_IN_HOUSE = 28, IS_DEAD = 29, METRICS_LIMIT_HIT = 33, LINK_FAILED = 35,
	LINK_SAME_FURNITURE = 36, LINK_INFINITE_PARENT_LOOP = 37, LINK_ALREADY_LINKED = 38,
	LINK_ALREADY_HAS_PARENT = 39, LINK_HAS_NO_PARENT = 40, LINK_HAS_TOO_MANY_CHILDREN = 42, INVALID_FURNITURE_POSITION = 52,
	NO_SUCH_FURNITURE = 60, ALREADY_SET_TO_MODE = 3, ALREADY_BEING_MOVED = 11,
	ITEM_REMOVE_FAILED_ALREADY_OWN_UNIQUE = 34,
	HIGH_IMPACT_ITEM_PLACE_LIMIT = 70, LOW_IMPACT_ITEM_PLACE_LIMIT = 71,
	HIGH_IMPACT_COLLECTIBLE_PLACE_LIMIT = 72, LOW_IMPACT_COLLECTIBLE_PLACE_LIMIT = 73,
}
for name, value in pairs(RESULT) do _G["HOUSING_REQUEST_RESULT_" .. name] = value end

-- The house's four limits (the globals are defined below, with the real values). Items are traditional (2)
-- unless World.limitTypeOf says otherwise.
local LIMIT_ANSWER = { [2] = RESULT.LOW_IMPACT_ITEM_PLACE_LIMIT, [3] = RESULT.LOW_IMPACT_COLLECTIBLE_PLACE_LIMIT,
	[0] = RESULT.HIGH_IMPACT_ITEM_PLACE_LIMIT, [1] = RESULT.HIGH_IMPACT_COLLECTIBLE_PLACE_LIMIT }

HOUSING_EDITOR_MODE_DISABLED, HOUSING_EDITOR_MODE_BROWSE, HOUSING_EDITOR_MODE_SELECTION = 0, 1, 2
HOUSING_EDITOR_MODE_PLACEMENT, HOUSING_EDITOR_MODE_LINK = 3, 4
HOUSING_EDITOR_COMMAND_RESULT_SUCCESS, HOUSING_EDITOR_COMMAND_RESULT_COMMAND_FAILED = 0, 1

HOUSING_FURNISHING_LIMIT_TYPE_HIGH_IMPACT_ITEM = 0
HOUSING_FURNISHING_LIMIT_TYPE_HIGH_IMPACT_COLLECTIBLE = 1
HOUSING_FURNISHING_LIMIT_TYPE_LOW_IMPACT_ITEM = 2
HOUSING_FURNISHING_LIMIT_TYPE_LOW_IMPACT_COLLECTIBLE = 3

BAG_BACKPACK, BAG_BANK, BAG_SUBSCRIBER_BANK = 1, 2, 3
BAG_HOUSE_BANK_ONE, BAG_HOUSE_BANK_TWO = 6, 7
BAG_FURNITURE_VAULT = 16

EVENT_ADD_ON_LOADED = "EVENT_ADD_ON_LOADED"
EVENT_PLAYER_ACTIVATED = "EVENT_PLAYER_ACTIVATED"
COLLECTIBLE_CATEGORY_TYPE_HOUSE = 7
SI_COLLECTIONS_CANNOT_JUMP_TO_HOUSE_FROM_LOCATION = "Cannot travel to house from this location."
EVENT_HOUSING_FURNITURE_PLACED = "EVENT_HOUSING_FURNITURE_PLACED"
EVENT_HOUSING_FURNITURE_REMOVED = "EVENT_HOUSING_FURNITURE_REMOVED"
EVENT_HOUSING_EDITOR_REQUEST_RESULT = "EVENT_HOUSING_EDITOR_REQUEST_RESULT"
EVENT_HOUSING_EDITOR_COMMAND_RESULT = "EVENT_HOUSING_EDITOR_COMMAND_RESULT"
EVENT_HOUSING_EDITOR_MODE_CHANGED = "EVENT_HOUSING_EDITOR_MODE_CHANGED"
EVENT_HOUSING_FURNITURE_MOVED = "EVENT_HOUSING_FURNITURE_MOVED"
EVENT_HOUSING_TARGET_FURNITURE_CHANGED = "EVENT_HOUSING_TARGET_FURNITURE_CHANGED"

-- ---- events -------------------------------------------------------------------------
local handlers = {}
EVENT_MANAGER = {
	RegisterForEvent = function(_, name, event, fn)
		handlers[event] = handlers[event] or {}
		handlers[event][name] = fn
	end,
	UnregisterForEvent = function(_, name, event)
		if handlers[event] then handlers[event][name] = nil end
	end,
}
function Fire(event, ...)
	local list = {}
	for _, fn in pairs(handlers[event] or {}) do list[#list + 1] = fn end
	for _, fn in ipairs(list) do fn(event, ...) end
end
function HandlerCount(event)
	local n = 0
	for _ in pairs(handlers[event] or {}) do n = n + 1 end
	return n
end

-- ---- saved variables ----------------------------------------------------------------
SavedStore = {}
local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = DeepCopy(v) end
	return out
end
ZO_SavedVars = {
	NewAccountWide = function(_, name, version, namespace, defaults)
		local store = SavedStore[name]
		if not store then
			store = DeepCopy(defaults or {})
			SavedStore[name] = store
		else
			for k, v in pairs(defaults or {}) do
				if store[k] == nil then store[k] = DeepCopy(v) end
			end
		end
		return store
	end,
}

-- ---- id64 ---------------------------------------------------------------------------
-- A fresh table per call, and no __eq: == between two ids for one furnishing is false.
local function NewId(n) return { n = n } end
function Id64ToString(id) return "F" .. tostring(id.n) end
function StringToId64(text) return NewId(tonumber((tostring(text):gsub("^F", "")))) end
function AreId64sEqual(a, b) return a.n == b.n end
function IsId64EqualToNumber(id, number) return id.n == number end

-- ---- the world ----------------------------------------------------------------------
World = nil

local function NewHouse(houseId, opts)
	opts = opts or {}
	return {
		houseId = houseId,
		name = opts.name or ("House " .. houseId),
		nickname = opts.nickname,
		unlocked = opts.unlocked ~= false,
		collectibleId = 5000 + houseId,
		owner = opts.owner ~= false,
		editor = opts.editor ~= false,
		ownerName = opts.ownerName or "@tester",
		furniture = {},
		nextId = 1000 * houseId,
		limits = opts.limits or { [0] = 100, [1] = 100, [2] = 800, [3] = 800 },
	}
end

function ResetWorld()
	HOUSING_EDITOR_SHARED = nil
	HOUSING_EDITOR_KEYBIND_PALETTE = nil
	KEYBIND_STRIP = nil
	UTILITY_WHEEL_GAMEPAD = nil
	UTILITY_WHEEL_KEYBOARD = nil
	SecurePostHook = nil
	SavedStore = {}
	timers = {}
	now = 0
	handlers = {}
	Chat = {}
	World = {
		houses = {},
		houseId = 0,
		mode = HOUSING_EDITOR_MODE_DISABLED,
		player = { x = 0, y = 0, z = 0, rot = 0 },
		bags = {},
		latency = 150,
		cooldown = 0,            -- how long the server stays busy after it has answered
		busyUntil = 0,
		requiredMode = HOUSING_EDITOR_MODE_SELECTION,   -- placing is refused outside it
		trueConv = { order = "YXZ", sp = 1, sy = 1, sr = 1 },
		-- failure switches
		private = {},            -- [functionName] = true: the call raises, as a private one does
		silent = {},             -- [eventName] = true: the event is never sent
		snap = 0,                -- placed furnishings land this many cm off in x
		linkRefusal = nil,       -- result code every link request is answered with
		maxChildren = nil,       -- the most children the server lets one furnishing have
		flaky = nil,             -- { place = k, link = k, remove = k }: every k-th request is refused with a failure
		chance = nil,            -- { place = p, link = p, remove = p }: each request fails with probability p (seed math.random)
		slowPlace = nil,         -- { every = k, delay = ms }: every k-th placement happens, and is announced, late
		calls = {},              -- every write call, in order, for the tests to read
	}
	ADDONS_LOADED = false
end

local function Cur() return World.houses[World.houseId] end
local function Find(id) local h = Cur(); return h and h.furniture[id.n] end

function AddHouse(houseId, opts)
	World.houses[houseId] = NewHouse(houseId, opts)
	return World.houses[houseId]
end

function EnterHouse(houseId)
	World.houseId = houseId
	World.mode = HOUSING_EDITOR_MODE_DISABLED
end

local DEFAULT_BOX = { lmin = { -0.5, 0, -0.25 }, lmax = { 1.5, 1, 0.75 } }

-- A furnishing placed straight into a house (as if by hand), returning its numeric id.
function AddFurniture(houseId, spec)
	local house = World.houses[houseId]
	house.nextId = house.nextId + 1
	local f = {
		n = house.nextId,
		dataId = spec.dataId or 1,
		name = spec.name or ("Thing " .. spec.dataId),
		x = spec.x or 0, y = spec.y or 0, z = spec.z or 0,
		pitch = spec.pitch or 0, yaw = spec.yaw or 0, roll = spec.roll or 0,
		parent = spec.parent,
		collectibleId = spec.collectibleId or 0,
		state = spec.state or 0,
		numStates = spec.numStates or 1,
		lmin = spec.lmin or DEFAULT_BOX.lmin,
		lmax = spec.lmax or DEFAULT_BOX.lmax,
		limitType = spec.limitType or 2,
	}
	house.furniture[f.n] = f
	return f.n
end

function GiveItem(bag, slot, dataId, count, name, stolen)
	World.bags[bag] = World.bags[bag] or {}
	World.bags[bag][slot] = { dataId = dataId, count = count, name = name or ("Thing " .. dataId), stolen = stolen }
end

-- Where an item of this kind is now: the slot it came back to need not be the one it left.
function SlotOf(bag, dataId)
	for slot, item in pairs(World.bags[bag] or {}) do
		if item.dataId == dataId and item.count > 0 then return slot end
	end
	return nil
end

function ItemCount(dataId)
	local total = 0
	for _, bag in pairs(World.bags) do
		for _, item in pairs(bag) do
			if item.dataId == dataId then total = total + item.count end
		end
	end
	return total
end

local function Call(name, ...)
	World.calls[#World.calls + 1] = { name = name, ... }
end
function CallsTo(name)
	local list = {}
	for _, c in ipairs(World.calls) do if c.name == name then list[#list + 1] = c end end
	return list
end

local function Guard(name)
	if World.private[name] then
		error("function " .. name .. " is private", 2)
	end
end

local function Send(event, ...)
	if not World.silent[event] then Fire(event, ...) end
end

local function Busy()
	return now < World.busyUntil
end

-- Is this the request that the flaky server fails? Counted per kind, over the requests that reached it.
local function Flaky(kind)
	if World.chance and World.chance[kind] then
		return math.random() < World.chance[kind]
	end
	local every = World.flaky and World.flaky[kind]
	if not every then return false end
	World.attempts = World.attempts or {}
	World.attempts[kind] = (World.attempts[kind] or 0) + 1
	return World.attempts[kind] % every == 0
end

local function Answer(fn)
	World.busyUntil = now + World.latency + (World.cooldown or 0)
	zo_callLater(fn, World.latency)
end

-- ---- house / player -----------------------------------------------------------------
function GetCurrentZoneHouseId() return World.houseId end
local function Loading() return World.loadingUntil ~= nil and now < World.loadingUntil end
function IsOwnerOfCurrentHouse() local h = Cur(); return (h and h.owner and not Loading()) or false end
function HasAnyEditingPermissionsForCurrentHouse() local h = Cur(); return h and h.editor or false end
function GetCurrentHouseOwner() local h = Cur(); return h and h.ownerName or "" end
function GetPlayerWorldPositionInHouse() local p = World.player; return p.x, p.y, p.z, p.rot end
function GetUnitWorldPosition() local p = World.player; return 1, p.x, p.y, p.z end
function GetUnitRawWorldPosition() local p = World.player; return 1, p.x + 1000, p.y, p.z + 1000 end
function GetPlayerCameraHeading() return World.player.rot end
function GetHousingEditorMode() return World.mode end
function GetHousingVisitorRole() return 0 end
function HousingEditorGetSelectedFurnitureId() return nil end
-- What is in the reticle: World.target is a furniture number, or nil for nothing.
function HousingEditorGetTargetInfo() return NewId(World.target or 0), nil end
function IsInGamepadPreferredMode() return World.gamepad ~= false end
function IsPrivateFunction(name) return World.private[name] and true or false end

function HousingEditorRequestModeChange(mode)
	Guard("HousingEditorRequestModeChange")
	Call("HousingEditorRequestModeChange", mode)
	if World.mode == mode then return RESULT.ALREADY_SET_TO_MODE end
	local old = World.mode
	World.mode = mode
	Fire(EVENT_HOUSING_EDITOR_MODE_CHANGED, old, mode)
	return RESULT.SUCCESS
end

-- ---- the houses the player owns, and travelling to them -------------------------------
local function HouseList()
	local ids = {}
	for houseId in pairs(World.houses) do ids[#ids + 1] = houseId end
	table.sort(ids, function(a, b) return a > b end)    -- deliberately not in houseId order
	return ids
end
function GetTotalCollectiblesByCategoryType(categoryType)
	if categoryType ~= COLLECTIBLE_CATEGORY_TYPE_HOUSE then return 0 end
	return #HouseList()
end
function GetCollectibleIdFromType(categoryType, index) return World.houses[HouseList()[index]].collectibleId end
local function HouseOfCollectible(collectibleId)
	for _, h in pairs(World.houses) do if h.collectibleId == collectibleId then return h end end
end
function IsCollectibleUnlocked(id) local h = HouseOfCollectible(id); return h and h.unlocked or false end
function GetCollectibleReferenceId(id) local h = HouseOfCollectible(id); return h and h.houseId or 0 end
function GetCollectibleName(id) local h = HouseOfCollectible(id); return h and h.name or "" end
function GetCollectibleNickname(id) local h = HouseOfCollectible(id); return h and h.nickname or "" end
function GetHousingPrimaryHouse() return World.primaryHouse or 1 end
function CanJumpToHouseFromCurrentLocation() return World.canJump ~= false end

function RequestJumpToHouse(houseId, jumpOutside)
	Guard("RequestJumpToHouse")
	Call("RequestJumpToHouse", houseId, jumpOutside)
	if World.jumpNever then return end
	zo_callLater(function()
		World.houseId = houseId
		World.mode = HOUSING_EDITOR_MODE_DISABLED
		World.player = { x = 0, y = 0, z = 0, rot = 0 }      -- the doorway
		World.loadingUntil = now + (World.loadTime or 4000)
		Fire(EVENT_PLAYER_ACTIVATED, false)
	end, World.jumpDelay or 3000)
end

-- ---- reading furnishings ------------------------------------------------------------
function GetNextPlacedHousingFurnitureId(last)
	local h = Cur()
	if not h or Loading() then return nil end
	local ids = {}
	for n in pairs(h.furniture) do ids[#ids + 1] = n end
	table.sort(ids)
	if last == nil then return ids[1] and NewId(ids[1]) or nil end
	for i, n in ipairs(ids) do
		if n == last.n then return ids[i + 1] and NewId(ids[i + 1]) or nil end
	end
	return nil
end

function GetPlacedHousingFurnitureInfo(id)
	local f = Find(id)
	if not f then return "", "", 0 end
	return f.name, "icon", f.dataId
end
function HousingEditorGetFurnitureWorldPosition(id)
	local f = Find(id); if not f then error("no such furniture") end
	return f.x, f.y, f.z
end
function HousingEditorGetFurnitureOrientation(id)
	local f = Find(id); if not f then error("no such furniture") end
	return f.pitch, f.yaw, f.roll
end
function HousingEditorGetFurnitureLocalBounds(id)
	local f = Find(id); if not f then error("no such furniture") end
	return f.lmin[1], f.lmin[2], f.lmin[3], f.lmax[1], f.lmax[2], f.lmax[3]
end
function HousingEditorGetFurnitureWorldBounds(id)
	local f = Find(id); if not f then error("no such furniture") end
	local geo = PBS_FURNITURE_EDITOR.geo
	local mn, mx = geo.PredictBounds({
		pitch = f.pitch, yaw = f.yaw, roll = f.roll, x = f.x, y = f.y, z = f.z, lmin = f.lmin, lmax = f.lmax,
	}, World.trueConv)
	local r = function(v) return math.floor(v + 0.5) end
	return r(mn[1]), r(mn[2]), r(mn[3]), r(mx[1]), r(mx[2]), r(mx[3])
end
function GetPlacedFurnitureParent(id)
	local f = Find(id); if not f then return nil end
	return f.parent and NewId(f.parent) or nil
end
function GetPlacedFurnitureChildren(id)
	local h = Cur()
	local kids = {}
	for n, f in pairs(h.furniture) do
		if f.parent == id.n then kids[#kids + 1] = n end
	end
	table.sort(kids)
	local ids = {}
	for i, n in ipairs(kids) do ids[i] = NewId(n) end
	return unpack(ids)
end
-- The raw call. World.rawCollectibleQuirk makes it answer a non-zero number for ordinary items, as
-- the console was seen to do (a first real paste called every plain item a collectible).
function GetCollectibleIdFromFurnitureId(id)
	local f = Find(id)
	if not f then return 0 end
	if f.collectibleId == 0 and World.rawCollectibleQuirk then return World.rawCollectibleQuirk end
	return f.collectibleId
end
-- What the client's own housing code reads: an item link and a collectible link, one of them empty.
function GetPlacedFurnitureLink(id, linkStyle)
	local f = Find(id)
	if not f then return "", "" end
	if f.collectibleId ~= 0 then return "", "|Hcollectible:" .. f.collectibleId .. "|h|h" end
	return "|Hitem:" .. f.dataId .. "|h|h", ""
end
-- What an item link says about the item: whether it stacks, whether only one may be owned.
local function LinkDataId(link)
	local n = tostring(link):match("item:(%d+)")
	return n and tonumber(n) or nil
end
function IsItemLinkStackable(link)
	if World.noStackInfo then return nil end        -- as if the link said nothing: the add-on has to estimate
	local dataId = LinkDataId(link)
	return not (dataId and World.stackMaxFor and World.stackMaxFor[dataId] == 1)
end
function IsItemLinkUnique(link)
	local dataId = LinkDataId(link)
	return (dataId and World.uniqueKinds and World.uniqueKinds[dataId]) and true or false
end
function GetCollectibleIdFromLink(link)
	local n = tostring(link):match("collectible:(%d+)")
	return n and tonumber(n) or nil
end
function GetCollectibleFurnitureDataId(collectibleId)
	for _, h in pairs(World.houses) do
		for _, f in pairs(h.furniture) do
			if f.collectibleId == collectibleId then return f.dataId end
		end
	end
	return 0
end
LINK_STYLE_BRACKETS = 1
function GetPlacedHousingFurnitureCurrentObjectStateIndex(id) local f = Find(id); return f and f.state or 0 end
function GetPlacedHousingFurnitureNumObjectStates(id) local f = Find(id); return f and f.numStates or 0 end
function HousingEditorGetNumPathNodesForFurniture() return 0 end
function HousingEditorCanPlaceCollectible(id) return not (World.cannotPlace and World.cannotPlace[id]) end

-- ---- limits -------------------------------------------------------------------------
function GetFurnitureDataInfo(dataId)
	local limitType = 2
	for _, h in pairs(World.houses) do
		for _, f in pairs(h.furniture) do
			if f.dataId == dataId then limitType = f.limitType end
		end
	end
	return 1, 1, 1, (World.limitTypeOf and World.limitTypeOf[dataId]) or limitType
end
function GetHouseFurnishingPlacementLimit(houseId, limitType) return World.houses[houseId].limits[limitType] end
function GetNumHouseFurnishingsPlaced(limitType)
	local count = 0
	for _, f in pairs(Cur().furniture) do
		if f.limitType == limitType then count = count + 1 end
	end
	return count
end

-- ---- bags ---------------------------------------------------------------------------
function GetBagSize(bag) return (World.bags[bag] and World.bagSize and World.bagSize[bag]) or (World.bags[bag] and 40 or 0) end
function HasItemInSlot(bag, slot) local i = World.bags[bag] and World.bags[bag][slot]; return i ~= nil and i.count > 0 end
function IsItemPlaceableFurniture(bag, slot) return HasItemInSlot(bag, slot) end
function GetItemFurnitureDataId(bag, slot) local i = World.bags[bag] and World.bags[bag][slot]; return i and i.dataId or 0 end
-- The most one slot holds of a kind: World.stackMaxFor[dataId], else World.stackMax, else 200.
local function StackMax(dataId) return (World.stackMaxFor and World.stackMaxFor[dataId]) or World.stackMax or 200 end
function GetSlotStackSize(bag, slot)
	local i = World.bags[bag] and World.bags[bag][slot]
	if not i then return 0, 0 end
	return i.count, StackMax(i.dataId)
end
function IsItemStolen(bag, slot) local i = World.bags[bag] and World.bags[bag][slot]; return i and i.stolen or false end
function HousingEditorGetRetrieveToBag() return World.retrieveBag or BAG_BACKPACK end
local function BagLimit(bag) return (World.bagLimit and World.bagLimit[bag]) or 40 end
function GetNumBagFreeSlots(bag)
	local used = 0
	for _, item in pairs(World.bags[bag] or {}) do
		if item.count > 0 then used = used + 1 end
	end
	return BagLimit(bag) - used
end
function GetItemName(bag, slot) local i = World.bags[bag] and World.bags[bag][slot]; return i and i.name or "" end

-- ---- writing ------------------------------------------------------------------------
local function CreateFurniture(spec)
	local h = Cur()
	h.nextId = h.nextId + 1
	spec.n = h.nextId
	h.furniture[spec.n] = spec
	return spec.n
end

function HousingEditorRequestItemPlacement(bag, slot, x, y, z, pitch, yaw, roll)
	Guard("HousingEditorRequestItemPlacement")
	Call("HousingEditorRequestItemPlacement", bag, slot, x, y, z, pitch, yaw, roll)
	if not Cur() then return RESULT.NOT_IN_HOUSE end
	if Busy() then return RESULT.REQUEST_IN_PROGRESS end
	if World.requiredMode and World.mode ~= World.requiredMode then return RESULT.INCORRECT_MODE end
	local item = World.bags[bag] and World.bags[bag][slot]
	if not item or item.count < 1 then return RESULT.PLACE_FAILED end
	if Flaky("place") then return RESULT.PLACE_FAILED end
	if World.heavy and World.heavy[item.dataId] then return RESULT.METRICS_LIMIT_HIT end
	do
		local limitType = (World.limitTypeOf and World.limitTypeOf[item.dataId]) or 2
		local limit = Cur().limits[limitType]
		if limit and GetNumHouseFurnishingsPlaced(limitType) >= limit then return LIMIT_ANSWER[limitType] end
	end
	local function create()
		item.count = item.count - 1
		local n = CreateFurniture({
			dataId = item.dataId, name = item.name,
			x = x + World.snap, y = y, z = z, pitch = pitch, yaw = yaw, roll = roll,
			collectibleId = 0, state = 0, numStates = 1,
			lmin = DEFAULT_BOX.lmin, lmax = DEFAULT_BOX.lmax,
			limitType = (World.limitTypeOf and World.limitTypeOf[item.dataId]) or 2,
		})
		Send(EVENT_HOUSING_FURNITURE_PLACED, NewId(n), 0)
	end
	if World.slowPlace then
		World.slowCount = (World.slowCount or 0) + 1
		local slow
		if World.slowPlace.chance then slow = math.random() < World.slowPlace.chance
		else slow = World.slowCount % World.slowPlace.every == 0 end
		if slow then
			-- the request is accepted, the server is free again, and the piece appears long after
			World.busyUntil = now + World.latency
			zo_callLater(create, World.slowPlace.delay)
			return RESULT.SUCCESS
		end
	end
	Answer(create)
	return RESULT.SUCCESS
end

function HousingEditorRequestCollectiblePlacement(collectibleId, x, y, z, pitch, yaw, roll)
	Guard("HousingEditorRequestCollectiblePlacement")
	Call("HousingEditorRequestCollectiblePlacement", collectibleId, x, y, z, pitch, yaw, roll)
	if Busy() then return RESULT.REQUEST_IN_PROGRESS end
	if World.requiredMode and World.mode ~= World.requiredMode then return RESULT.INCORRECT_MODE end
	if World.heavy and World.heavy[9000 + collectibleId] then return RESULT.METRICS_LIMIT_HIT end
	do
		local limitType = (World.limitTypeOfCollectible and World.limitTypeOfCollectible[collectibleId]) or 3
		local limit = Cur().limits[limitType]
		if limit and GetNumHouseFurnishingsPlaced(limitType) >= limit then return LIMIT_ANSWER[limitType] end
	end
	Answer(function()
		local n = CreateFurniture({
			dataId = 9000 + collectibleId, name = "Collectible " .. collectibleId,
			x = x, y = y, z = z, pitch = pitch, yaw = yaw, roll = roll,
			collectibleId = collectibleId, state = 0, numStates = 1,
			lmin = DEFAULT_BOX.lmin, lmax = DEFAULT_BOX.lmax,
			limitType = (World.limitTypeOfCollectible and World.limitTypeOfCollectible[collectibleId]) or 3,
		})
		Send(EVENT_HOUSING_FURNITURE_PLACED, NewId(n), collectibleId)
	end)
	return RESULT.SUCCESS
end

local function MoveWithChildren(f, nx, ny, nz)
	local dx, dy, dz = nx - f.x, ny - f.y, nz - f.z
	f.x, f.y, f.z = nx, ny, nz
	for _, other in pairs(Cur().furniture) do
		if other.parent == f.n then
			MoveWithChildren(other, other.x + dx, other.y + dy, other.z + dz)
		end
	end
end

function HousingEditorRequestChangePositionAndOrientation(id, x, y, z, pitch, yaw, roll)
	Guard("HousingEditorRequestChangePositionAndOrientation")
	Call("HousingEditorRequestChangePositionAndOrientation", id, x, y, z, pitch, yaw, roll)
	local f = Find(id)
	if not f then return RESULT.NO_SUCH_FURNITURE end
	if Busy() then return RESULT.REQUEST_IN_PROGRESS end
	Answer(function()
		MoveWithChildren(f, x, y, z)
		f.pitch, f.yaw, f.roll = pitch, yaw, roll
		Send(EVENT_HOUSING_FURNITURE_MOVED, id)
	end)
	return RESULT.SUCCESS
end

function HousingEditorRequestChangePosition(id, x, y, z)
	Guard("HousingEditorRequestChangePosition")
	Call("HousingEditorRequestChangePosition", id, x, y, z)
	local f = Find(id)
	if not f then return RESULT.NO_SUCH_FURNITURE end
	if Busy() then return RESULT.REQUEST_IN_PROGRESS end
	Answer(function() MoveWithChildren(f, x, y, z); Send(EVENT_HOUSING_FURNITURE_MOVED, id) end)
	return RESULT.SUCCESS
end

function HousingEditorRequestChangeState(id, state)
	Guard("HousingEditorRequestChangeState")
	Call("HousingEditorRequestChangeState", id, state)
	local f = Find(id)
	if not f then return RESULT.NO_SUCH_FURNITURE end
	f.state = state
	return RESULT.SUCCESS
end

local function IsAncestor(candidate, of)
	local f = Cur().furniture[of]
	local guard = 0
	while f and f.parent and guard < 100 do
		if f.parent == candidate then return true end
		f = Cur().furniture[f.parent]
		guard = guard + 1
	end
	return false
end

function HousingEditorRequestSetFurnitureParent(childId, parentId)
	Guard("HousingEditorRequestSetFurnitureParent")
	Call("HousingEditorRequestSetFurnitureParent", childId, parentId)
	if World.linkRefusal then return World.linkRefusal end
	local child, parent = Find(childId), Find(parentId)
	if not child or not parent then return RESULT.NO_SUCH_FURNITURE end
	if child.n == parent.n then return RESULT.LINK_SAME_FURNITURE end
	if child.parent == parent.n then return RESULT.LINK_ALREADY_LINKED end
	if child.parent then return RESULT.LINK_ALREADY_HAS_PARENT end
	if IsAncestor(child.n, parent.n) then return RESULT.LINK_INFINITE_PARENT_LOOP end
	if Busy() then return RESULT.REQUEST_IN_PROGRESS end
	if World.maxChildren then
		local kids = 0
		for _, other in pairs(Cur().furniture) do
			if other.parent == parent.n then kids = kids + 1 end
		end
		if kids >= World.maxChildren then return RESULT.LINK_HAS_TOO_MANY_CHILDREN end
	end
	if Flaky("link") then return RESULT.LINK_FAILED end
	Answer(function()
		child.parent = parent.n
		Send(EVENT_HOUSING_EDITOR_COMMAND_RESULT, HOUSING_EDITOR_COMMAND_RESULT_SUCCESS)
	end)
	return RESULT.SUCCESS
end

function HousingEditorRequestClearFurnitureParent(id)
	Guard("HousingEditorRequestClearFurnitureParent")
	Call("HousingEditorRequestClearFurnitureParent", id)
	local f = Find(id)
	if not f then return RESULT.NO_SUCH_FURNITURE end
	if not f.parent then return RESULT.LINK_HAS_NO_PARENT end
	if Busy() then return RESULT.REQUEST_IN_PROGRESS end
	Answer(function() f.parent = nil end)
	return RESULT.SUCCESS
end

function HousingEditorRequestRemoveFurniture(id)
	Guard("HousingEditorRequestRemoveFurniture")
	Call("HousingEditorRequestRemoveFurniture", id)
	local f = Find(id)
	if not f then return RESULT.NO_SUCH_FURNITURE end
	if Busy() then return RESULT.REQUEST_IN_PROGRESS end
	if World.removeNeedsMode and World.mode ~= World.removeNeedsMode then return RESULT.INCORRECT_MODE end
	if Flaky("remove") then return RESULT.REMOVE_FAILED end
	if f.collectibleId == 0 and World.uniqueKinds and World.uniqueKinds[f.dataId] then
		for _, item in pairs(World.bags[BAG_BACKPACK] or {}) do
			if item.dataId == f.dataId and item.count > 0 then return RESULT.ITEM_REMOVE_FAILED_ALREADY_OWN_UNIQUE end
		end
	end
	if f.collectibleId == 0 then
		-- room for it: a stack of its kind that is not full, or a free slot
		local stacked = false
		for _, item in pairs(World.bags[BAG_BACKPACK] or {}) do
			if item.dataId == f.dataId and item.count > 0 and item.count < StackMax(item.dataId) then stacked = true end
		end
		if not stacked and GetNumBagFreeSlots(BAG_BACKPACK) <= 0 then
			return RESULT.ITEM_REMOVE_FAILED_INVENTORY_FULL
		end
	end
	Answer(function()
		-- children are released, not removed
		for _, other in pairs(Cur().furniture) do
			if other.parent == f.n then other.parent = nil end
		end
		Cur().furniture[f.n] = nil
		-- the item goes back to the first backpack stack of its kind, or a new slot; a collectible
		-- goes to no bag at all
		if f.collectibleId == 0 then
			local bag = World.bags[BAG_BACKPACK] or {}
			World.bags[BAG_BACKPACK] = bag
			local put = false
			for _, item in pairs(bag) do
				if item.dataId == f.dataId and item.count > 0 and item.count < StackMax(item.dataId) then
					item.count = item.count + 1; put = true; break
				end
			end
			if not put then
				for slot = 0, 39 do
					if not bag[slot] or bag[slot].count == 0 then
						bag[slot] = { dataId = f.dataId, count = 1, name = f.name }
						break
					end
				end
			end
		end
		Send(EVENT_HOUSING_FURNITURE_REMOVED, id, 0)
	end)
	return RESULT.SUCCESS
end

-- ---- the quickslot wheel --------------------------------------------------------------
-- As the client builds it: ShowMenu clears the menu, PopulateMenu fills it, and every entry is then
-- drawn through a setup that reads data.slotNum with four slot calls. A slot number the calls do not
-- accept (World.strictSlots) raises, as a bad one would in the real draw.
HOTBAR_CATEGORY_QUICKSLOT_WHEEL, HOTBAR_CATEGORY_EMOTE_WHEEL = 1, 2
ACTION_BAR_UTILITY_BAR_SIZE = 8
ACTION_TYPE_NOTHING, ACTION_TYPE_ITEM = 0, 1

local function SlotOK(slot)
	if World.strictSlots and (type(slot) ~= "number" or slot < 1 or slot > 8) then error("bad slot " .. tostring(slot)) end
end
function GetSlotType(slot) SlotOK(slot); return (World.quickslots and World.quickslots[slot]) and ACTION_TYPE_ITEM or ACTION_TYPE_NOTHING end
function GetSlotItemCount(slot) SlotOK(slot); return (World.quickslots and World.quickslots[slot]) and 3 or 0 end
function GetSlotCooldownInfo(slot) SlotOK(slot); return 0, 0 end
function GetSlotTexture(slot) SlotOK(slot); return "" end
function IsUnitInCombat() return World.inCombat or false end
function GetCVar() return World.language or "en" end

function InstallMockWheel(opts)
	opts = opts or {}
	World.quickslots = opts.quickslots or { "Potion A", "Potion B", "Potion C" }
	World.hookCalls = 0
	local wheel = { category = HOTBAR_CATEGORY_QUICKSLOT_WHEEL, menu = { entries = {} } }

	function wheel.menu:AddEntry(name, inactiveIcon, activeIcon, callback, data)
		if data and data.pbfe and World.wheelAddThrows then error("AddEntry exploded") end
		self.entries[#self.entries + 1] = { name = name, inactiveIcon = inactiveIcon, activeIcon = activeIcon, callback = callback, data = data }
	end
	function wheel:GetHotbarCategory() return self.category end
	function wheel:PopulateMenu()
		for i = 1, (World.baseEntries or 8) do
			local name = World.quickslots[i] or "(empty)"
			self.menu:AddEntry(name, "icon", "icon", function() self.lastSlot = i end, { slotNum = i, name = name })
		end
	end
	function wheel:ShowMenu()
		self.menu.entries = {}
		self:PopulateMenu()
		for _, entry in ipairs(self.menu.entries) do
			local slot = entry.data.slotNum
			GetSlotItemCount(slot, self.category)
			GetSlotType(slot, self.category)
			GetSlotCooldownInfo(slot, self.category)
			GetSlotTexture(slot, self.category)
		end
		return #self.menu.entries
	end
	-- let go of the button over entry i
	function wheel:Select(i)
		local entry = self.menu.entries[i]
		entry.callback(self.menu)
	end
	function wheel:Names()
		local names = {}
		for i, entry in ipairs(self.menu.entries) do names[i] = entry.name end
		return names
	end

	UTILITY_WHEEL_GAMEPAD = wheel

	if not opts.noSecurePostHook then
		function SecurePostHook(tbl, name, hook)
			if World.securePostHookBroken then error("SecurePostHook is not for you") end
			World.hookCalls = World.hookCalls + 1
			local original = tbl[name]
			tbl[name] = function(...)
				local results = { original(...) }
				hook(...)
				return unpack(results)
			end
		end
	end
	return wheel
end

-- ---- the camera, and the client's "screen point meets plane" call --------------------------
-- A pinhole camera at the player's position (raised by World.camera.height, and set back by .back for
-- a third-person view), looking along yaw / pitch (pitch negative is DOWN). The client's call takes a
-- screen point and three world points describing a plane and gives where the camera's ray meets it. A
-- real ray meets a plane on one side only; the call is said to return zeros when it does not, but
-- World.rayBehindReturns makes it return the point BEHIND the camera instead, to see what the add-on
-- does with the worse of the two possible answers.
SPACE_WORLD = 2
GuiRoot = { GetDimensions = function() return 1920, 1080 end }

local function CameraBasis()
	local c = World.camera or { yaw = 0, pitch = 0 }
	local sy, cy, sp, cp = math.sin(c.yaw), math.cos(c.yaw), math.sin(c.pitch), math.cos(c.pitch)
	return {
		forward = { sy * cp, sp, cy * cp },
		right = { cy, 0, -sy },
		up = { -sy * sp, cp, -cy * sp },
	}, c
end
function GetCameraForward(space)
	if World.noCameraForward then error("GetCameraForward is not here") end
	local b = CameraBasis()
	return b.forward[1], b.forward[2], b.forward[3]
end
function HousingEditorGetScreenPointWorldPlaneIntersection(sx, sy, x1, y1, z1, x2, y2, z2, x3, y3, z3)
	local b, c = CameraBasis()
	local p = World.player
	-- a third-person camera is set back along the heading, on the ground plane
	local origin = {
		p.x - math.sin(c.yaw) * (c.back or 0),
		p.y + (c.height or 160),
		p.z - math.cos(c.yaw) * (c.back or 0),
	}
	local tanf, aspect = math.tan(math.rad(30)), 1920 / 1080
	local nx, ny = (sx - 960) / 960, (540 - sy) / 540
	local d = {}
	for i = 1, 3 do d[i] = b.forward[i] + b.right[i] * (nx * aspect * tanf) + b.up[i] * (ny * tanf) end
	local u = { x2 - x1, y2 - y1, z2 - z1 }
	local v = { x3 - x1, y3 - y1, z3 - z1 }
	local n = { u[2] * v[3] - u[3] * v[2], u[3] * v[1] - u[1] * v[3], u[1] * v[2] - u[2] * v[1] }
	local denominator = d[1] * n[1] + d[2] * n[2] + d[3] * n[3]
	if math.abs(denominator) < 1e-9 then return 0, 0, 0 end
	local t = ((x1 - origin[1]) * n[1] + (y1 - origin[2]) * n[2] + (z1 - origin[3]) * n[3]) / denominator
	if t <= 0 and not World.rayBehindReturns then return 0, 0, 0 end
	local function r(value) return math.floor(value + 0.5) end
	return r(origin[1] + d[1] * t), r(origin[2] + d[2] * t), r(origin[3] + d[3] * t)
end

-- ---- the housing editor HUD, its palette, and the dialog system -------------------------
-- As the client builds them (housingeditorhud.lua, zo_keybindstrip, zo_dialog): the HUD object holds
-- the palette list and the strip list; the palette shows the descriptors whose `visible` answers yes
-- (and sorts the list once); a keybind is handled by ONE descriptor, and a second one for the same
-- keybind removes the first. Dialogs open only if a scene is showing, and say nothing when not.
function InstallMockEditor()
	World.browseCalls = 0
	World.stripUpdates = 0
	World.duplicateKeybinds = 0

	local function always() return true end
	local hasTarget = function() return World.target ~= nil end

	local paletteList = {
		{ name = "Select", keybind = "HOUSING_EDITOR_PRIMARY_ACTION", callback = function() end, visible = hasTarget, enabled = hasTarget, order = 10, ethereal = true },
		{ name = "Precision Edit", keybind = "HOUSING_EDITOR_TERTIARY_ACTION", callback = function() end, visible = hasTarget, enabled = hasTarget, order = 20, ethereal = true },
		{ name = "Path", keybind = "HOUSING_EDITOR_QUINARY_ACTION", callback = function() end, visible = function() return false end, order = 30, ethereal = true },
		{ name = "Link", keybind = "HOUSING_EDITOR_BEGIN_FURNITURE_LINKING", callback = function() end, visible = hasTarget, enabled = hasTarget, order = 40, ethereal = true },
	}
	local stripList = {
		{ name = "Browse", keybind = "HOUSING_EDITOR_SECONDARY_ACTION", callback = function() World.browseCalls = World.browseCalls + 1 end, visible = always, enabled = always, order = 10 },
		{ name = "Jump to safe location", keybind = "HOUSING_EDITOR_JUMP_TO_SAFE_LOC", callback = function() end, order = 60 },
	}
	local hud = {
		selectionModeKeybindPaletteGamepadDescriptor = paletteList,
		selectionModeGamepadKeybindStripDescriptor = stripList,
	}
	hud.currentKeybindDescriptor = stripList
	HOUSING_EDITOR_SHARED = hud

	-- ZO_KeybindStrip: one descriptor per keybind. Adding a second runs internalassert and removes the
	-- one registered first (HandleDuplicateAddKeybind). A NON-ethereal descriptor is drawn as a button (when its
	-- `visible` says yes) for as long as it is the one registered; an ethereal one is only ever input.
	local registry = {}
	local function isVisible(d)
		local visible = d.visible
		if type(visible) == "function" then visible = visible(d) end
		return visible ~= false
	end
	-- SetUpButton: the strip asks `visible` and `name` of every button it draws
	local function drawStrip()
		for _, d in pairs(registry) do
			if not d.ethereal then
				isVisible(d)
				if type(d.name) == "function" then d.name() end
			end
		end
	end
	local function register(list)
		for _, d in ipairs(list) do
			if d.keybind then
				local existing = registry[d.keybind]
				if existing and existing ~= d then World.duplicateKeybinds = World.duplicateKeybinds + 1 end
				registry[d.keybind] = d
			end
		end
	end
	local function unregister(list)
		for _, d in ipairs(list) do
			if d.keybind and registry[d.keybind] == d then registry[d.keybind] = nil end
		end
	end

	-- ZO_HousingEditorKeybindPalette: sorts once, DRAWS the descriptors whose `visible` says yes
	-- (whether or not the strip kept them), and registers the whole list with the strip.
	local palette = { shown = {}, current = nil }
	function palette:AddKeybinds(list)
		self:RemoveKeybinds()
		self.current = list
		if not list.sorted then
			table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)
			list.sorted = true
		end
		self.shown = {}
		for _, d in ipairs(list) do
			local visible = d.visible
			if type(visible) == "function" then visible = visible(d) end
			if visible == nil then visible = true end
			if visible then self.shown[#self.shown + 1] = d end
		end
		register(list)
	end
	function palette:RemoveKeybinds()
		if self.current then unregister(self.current) end
		self.current = nil
		self.shown = {}
	end
	function palette:RefreshKeybinds() self:AddKeybinds(self.current or paletteList) end
	function palette:Names()
		local names = {}
		for i, d in ipairs(self.shown) do
			names[i] = type(d.name) == "function" and d.name() or d.name
		end
		return names
	end
	HOUSING_EDITOR_KEYBIND_PALETTE = palette

	-- ZO_HousingEditorHud:UpdateKeybinds: remove both groups, add the palette, THEN the strip
	function hud:UpdateKeybinds()
		palette:RemoveKeybinds()
		unregister(stripList)
		palette:AddKeybinds(paletteList)
		register(stripList)
		drawStrip()
	end
	hud:UpdateKeybinds()

	-- UpdateKeybindButtonGroup: a descriptor of the group that is not the one registered for its keybind
	-- replaces it (an ethereal one is removed, a button is removed and added); then the buttons are set up again
	KEYBIND_STRIP = {
		UpdateKeybindButtonGroup = function(_, list)
			World.stripUpdates = World.stripUpdates + 1
			for _, d in ipairs(list or {}) do
				if d.keybind and registry[d.keybind] and registry[d.keybind] ~= d then
					registry[d.keybind] = d
				end
			end
			drawStrip()
		end,
	}

	-- the target changed: the palette is refreshed, the strip is not (the inspection HUD's handler)
	function TargetChanged() palette:RefreshKeybinds() end
	-- a full rebuild (a link, a placement, a mode change)
	function Rebuild() hud:UpdateKeybinds() end

	-- press a button: the ONE descriptor the strip kept for that keybind (a button that is not drawn does not
	-- handle it: TryHandlingKeybindDown wants the control not to be hidden)
	function PressKey(keybind)
		local d = registry[keybind]
		if not d then return false end
		if not d.ethereal and not isVisible(d) then return false end
		local enabled = d.enabled
		if type(enabled) == "function" then enabled = enabled(d) end
		if enabled == false then return false end
		d.callback()
		return true
	end
	function PalettePress(keybind) return PressKey(keybind) end
	function PaletteNames() return palette:Names() end
	-- what the bottom of the screen says for this button: nothing when the strip does not hold it
	function StripLabel(keybind)
		local d = registry[keybind]
		if not d or d.ethereal or not isVisible(d) then return nil end
		return type(d.name) == "function" and d.name() or d.name
	end
	return hud
end

GAMEPAD_DIALOGS = { PARAMETRIC = 1 }
SI_DIALOG_CANCEL, SI_GAMEPAD_SELECT_OPTION = 5001, 5002
ZO_GamepadEntryData = { New = function(self, text) return { text = text } end }
function ZO_SharedGamepadEntry_OnSetup() end
local dialogs = {}
function ZO_Dialogs_RegisterCustomDialog(name, info) dialogs[name] = info end
function ZO_Dialogs_ShowGamepadDialog(name, data)
	if World.dialogThrows then error("the dialog system is not ready") end
	if World.noDialogScene then return end            -- no scene showing: nothing, and no error
	local info = dialogs[name]
	local dialog = { name = name, data = data, info = info, selected = 1, entryList = {} }
	function dialog.entryList.GetTargetData()
		local row = dialog.rows and dialog.rows[dialog.selected]
		return row and row.entryData
	end
	function dialog.setupFunc() dialog.rows = info.parametricList end
	World.dialog = dialog
	info.setup(dialog, data)
end
-- what the player sees and does on the screen
function DialogTitle() return World.dialog.info.title.text(World.dialog) end
function DialogRows()
	local rows = {}
	for i, row in ipairs(World.dialog.rows) do rows[i] = row.entryData.text end
	return rows
end
local function PressButton(keybind)
	local dialog = World.dialog
	for _, button in ipairs(dialog.info.buttons) do
		if button.keybind == keybind and button.callback then button.callback(dialog) end
	end
	if dialog.info.finishedCallback then dialog.info.finishedCallback(dialog) end
	World.dialog = nil
end
function DialogChoose(i) World.dialog.selected = i; PressButton("DIALOG_PRIMARY") end
function DialogCancel() PressButton("DIALOG_NEGATIVE") end

-- ---- loading the add-on -------------------------------------------------------------
-- Files in manifest order, exactly as the client would load them.
function LoadAddon()
	local list = {}
	for line in io.lines(DIR .. "/PBsFurnitureEditor.addon") do
		if line ~= "" and not line:match("^##") then
			list[#list + 1] = line
		end
	end
	PBS_FURNITURE_EDITOR = nil
	for _, file in ipairs(list) do
		dofile(DIR .. "/" .. file)
	end
	Fire(EVENT_ADD_ON_LOADED, "PBsFurnitureEditor")
	return PBS_FURNITURE_EDITOR
end

function Cmd(text)
	local command, rest = text:match("^(%S+)%s*(.*)$")
	SLASH_COMMANDS[command](rest)
end
