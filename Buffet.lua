
----------------------
--      Locals      --
----------------------

local myname, ns = ...

local defaults = {macroHP = "#showtooltip\n%MACRO%", macroMP = "#showtooltip\n%MACRO%"}
local ids, bests, allitems, items, dirty = LibStub("tekIDmemo"), {}, {}, {}
for i,v in pairs(ns) do items[i] = v end

------------------------------
--      Util Functions      --
------------------------------

local function TableStuffer(...)
	local t = {}
	for i=1,select("#", ...) do
		local id, v = string.split(":", (select(i, ...)))
		if id and id ~= "" then
			t[tonumber(id)] = tonumber(v) or 0
			allitems[tonumber(id)] = tonumber(v) or 0
		end
	end
	return t
end
for i,v in pairs(items) do bests[i], items[i] = {}, TableStuffer(string.split("\n", v)) end

local PT3 = LibStub('LibPeriodicTable-3.1', true)
if PT3 then
	local sets = {
		bandage   = "Consumable.Bandage.Basic",
		hstone    = "Consumable.Cooldown.Stone.Health.Warlock",
		mstone    = "Consumable.Cooldown.Stone.Mana.Mana Stone",
		hppot     = "Consumable.Cooldown.Potion.Health.Basic",
		mppot     = "Consumable.Cooldown.Potion.Mana.Basic",
		water     = "Consumable.Water.Basic",
		food      = "Consumable.Food.Edible.Basic.Non-Conjured",
		conjfood  = "Consumable.Food.Edible.Basic.Conjured",
		bonusfood = "Consumable.Food.Bonus",
		conjwater = "Consumable.Food.Edible.Combo.Conjured",
		percfood  = "Consumable.Food.Percent.Basic",
		percwater = "Consumable.Water.Percentage",
		pvpwater  = nil,
	}
	for set, pt3set in pairs(sets) do
		for id, v in PT3:IterateSet(pt3set) do
			if not allitems[id] then
				if v == true then
					v = 0
				end
				items[set][id] = v
				allitems[id] = v
			end
		end
	end
end

local function FindHerbalsimLevel(...)
	for i = 1, select('#', ...) do
		local index = select(i, ...)
		if type(index) == "number" then
			local _, icon, level = GetProfessionInfo(index)
			if icon == [[Interface\Icons\Trade_Herbalism]] then
				return level
			end
		end
	end
	return 0
end

local herbalismLevel
local function GetHerbalismLevel(...)
	if not herbalismLevel then
		herbalismLevel = FindHerbalsimLevel(GetProfessions())
	end
	return herbalismLevel
end

-----------------------------
--      Event Handler      --
-----------------------------

Buffet = CreateFrame("frame")
Buffet:SetScript("OnEvent", function(self, event, ...) if self[event] then return self[event](self, event, ...) end end)
Buffet:RegisterEvent("ADDON_LOADED")
function Buffet:Print(...) ChatFrame1:AddMessage(string.join(" ", "|cFF33FF99Buffet|r:", ...)) end


function Buffet:ADDON_LOADED(event, addon)
	if addon:lower() ~= "buffet" then return end

	BuffetDB = setmetatable(BuffetDB or {}, {__index = defaults})
	self.db = BuffetDB

	self:UnregisterEvent("ADDON_LOADED")
	self.ADDON_LOADED = nil

	if IsLoggedIn() then self:PLAYER_LOGIN() else self:RegisterEvent("PLAYER_LOGIN") end
end


function Buffet:PLAYER_LOGIN()
	self:RegisterEvent("PLAYER_LOGOUT")

	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("BAG_UPDATE")
	self:RegisterEvent("PLAYER_LEVEL_UP")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("SKILL_LINES_CHANGED")

	self:Scan()

	self:UnregisterEvent("PLAYER_LOGIN")
	self.PLAYER_LOGIN = nil
end

function Buffet:SKILL_LINES_CHANGED()
	herbalismLevel = nil
	return self:BAG_UPDATE()
end

function Buffet:PLAYER_LOGOUT()
	for i,v in pairs(defaults) do if self.db[i] == v then self.db[i] = nil end end
end


function Buffet:PLAYER_REGEN_ENABLED()
	if dirty then self:Scan() end
end


function Buffet:BAG_UPDATE()
	dirty = true
	if not InCombatLockdown() then self:Scan() end
end
Buffet.PLAYER_LEVEL_UP = Buffet.BAG_UPDATE

function Buffet:Scan()
	for _,t in pairs(bests) do for i in pairs(t) do t[i] = nil end end
	local mylevel = UnitLevel("player")

	allitems[63122] = GetHerbalismLevel() >= 425

	for bag=0,4 do
		for slot=1,GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			local id = link and ids[link]
			local reqlvl = link and select(5, GetItemInfo(link)) or 0
			if id and allitems[id] and reqlvl <= mylevel then
				local _, stack = GetContainerItemInfo(bag,slot)
				for set,setitems in pairs(items) do
					local thisbest, val = bests[set], setitems[id]
					if val then
						if set == 'percfood' then
							thisbest, val = bests.food, UnitHealthMax('player')*val/100
						elseif set == 'percmana' then
							thisbest, val = bests.water, UnitManaMax('player')*val/100
						end
						if not thisbest.val or (thisbest.val < val or thisbest.val == val and thisbest.stack > stack) then
							thisbest.id, thisbest.val, thisbest.stack = id, val, stack
						end
					end
				end
			end
		end
	end

	local food, hpot, water, mpot
	if select(2, IsInInstance()) == "arena" then
		food = bests.conjfood.id or bests.hstone.id
		water = bests.conjwater.id or bests.pvpwater.id or bests.mstone.id
	else
		food = bests.conjfood.id or bests.food.id or bests.bonusfood.id or bests.hstone.id or bests.hppot.id
		hpot = bests.hppot.id
		water = bests.conjwater.id or bests.water.id or bests.mstone.id or bests.mppot.id
		mpot = bests.mppot.id
	end

	self:Edit("AutoHP", self.db.macroHP, food, hpot, bests.hstone.id, bests.bandage.id)
	self:Edit("AutoMP", self.db.macroMP, water, mpot, bests.mstone.id)

	dirty = false
end

Buffet.PLAYER_ENTERING_WORLD = Buffet.Scan

function Buffet:Edit(name, substring, food, pot, stone, shift)
	local macroid = GetMacroIndexByName(name)
	if not macroid then return end

	local body = "/use "
	if shift then body = body .. "[mod:shift,target=player] item:"..shift.."; " end
	if (pot and not stone) or (stone and not pot) then body = body .. "[combat] item:"..(pot or stone).."; " end
	body = body .. (pot and stone and "[nocombat] " or "").."item:"..(food or "6948")

	if pot and stone then body = body .. "\n/castsequence [combat,nomod] reset="..(stone == 22044 and "120/" or "").."combat item:"..stone..", item:"..pot end

	EditMacro(macroid, name, "INV_Misc_QuestionMark", substring:gsub("%%MACRO%%", body), 1)
end


