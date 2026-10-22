-- TransmogAtlas: which pieces each class can transmogrify.
--
-- Decided from the item type (C_Item.GetItemInfoInstant: classID, subClassID, equip slot).
-- This is a hand-written table: /tma verify compares it against the Adventure Guide class
-- filter and logs every difference so the table can be corrected.

local ADDON, ns = ...

local Classes = {}
ns.Classes = Classes

local ITEM_CLASS_WEAPON = Enum.ItemClass.Weapon -- 2
local ITEM_CLASS_ARMOR = Enum.ItemClass.Armor   -- 4

local A = Enum.ItemArmorSubclass   -- Generic=0 Cloth=1 Leather=2 Mail=3 Plate=4 Cosmetic=5 Shield=6
local W = Enum.ItemWeaponSubclass  -- Axe1H=0 Axe2H=1 Bows=2 Guns=3 Mace1H=4 Mace2H=5 Polearm=6 Sword1H=7
                                   -- Sword2H=8 Warglaive=9 Staff=10 Unarmed=13 Dagger=15 Crossbow=18 Wand=19

local function set(...)
    local t = {}
    for i = 1, select("#", ...) do t[select(i, ...)] = true end
    return t
end

-- classID -> rules
Classes.rules = {
    [1]  = { armor = A.Plate,   shield = true,  holdable = false, -- Warrior
             weapons = set(W.Axe1H, W.Axe2H, W.Mace1H, W.Mace2H, W.Sword1H, W.Sword2H, W.Polearm, W.Staff, W.Unarmed, W.Dagger, W.Bows, W.Guns, W.Crossbow) },
    [2]  = { armor = A.Plate,   shield = true,  holdable = true,  -- Paladin
             weapons = set(W.Axe1H, W.Axe2H, W.Mace1H, W.Mace2H, W.Sword1H, W.Sword2H, W.Polearm) },
    [3]  = { armor = A.Mail,    shield = false, holdable = false, -- Hunter
             weapons = set(W.Axe1H, W.Axe2H, W.Sword1H, W.Sword2H, W.Polearm, W.Staff, W.Unarmed, W.Dagger, W.Bows, W.Guns, W.Crossbow) },
    [4]  = { armor = A.Leather, shield = false, holdable = false, -- Rogue
             weapons = set(W.Axe1H, W.Mace1H, W.Sword1H, W.Unarmed, W.Dagger) },
    [5]  = { armor = A.Cloth,   shield = false, holdable = true,  -- Priest
             weapons = set(W.Mace1H, W.Dagger, W.Staff, W.Wand) },
    [6]  = { armor = A.Plate,   shield = false, holdable = false, -- Death Knight
             weapons = set(W.Axe1H, W.Axe2H, W.Mace1H, W.Mace2H, W.Sword1H, W.Sword2H, W.Polearm) },
    [7]  = { armor = A.Mail,    shield = true,  holdable = true,  -- Shaman
             weapons = set(W.Axe1H, W.Axe2H, W.Mace1H, W.Mace2H, W.Unarmed, W.Dagger, W.Staff) },
    [8]  = { armor = A.Cloth,   shield = false, holdable = true,  -- Mage
             weapons = set(W.Sword1H, W.Dagger, W.Staff, W.Wand) },
    [9]  = { armor = A.Cloth,   shield = false, holdable = true,  -- Warlock
             weapons = set(W.Sword1H, W.Dagger, W.Staff, W.Wand) },
    [10] = { armor = A.Leather, shield = false, holdable = true,  -- Monk
             weapons = set(W.Axe1H, W.Mace1H, W.Sword1H, W.Unarmed, W.Polearm, W.Staff) },
    [11] = { armor = A.Leather, shield = false, holdable = true,  -- Druid
             weapons = set(W.Mace1H, W.Mace2H, W.Unarmed, W.Dagger, W.Polearm, W.Staff) },
    [12] = { armor = A.Leather, shield = false, holdable = false, -- Demon Hunter
             weapons = set(W.Axe1H, W.Sword1H, W.Unarmed, W.Warglaive) },
    [13] = { armor = A.Mail,    shield = false, holdable = true,  -- Evoker
             weapons = set(W.Axe1H, W.Axe2H, W.Mace1H, W.Mace2H, W.Sword1H, W.Sword2H, W.Unarmed, W.Dagger, W.Staff) },
}

-- Armor slots where the armor type (cloth/leather/mail/plate) matters.
local ARMOR_TYPED_SLOTS = set("INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_ROBE",
    "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND")

-- Class restriction coming from transmog sets. Class-specific pieces (tier sets, class sets) belong
-- to a transmog set whose classMask lists the classes allowed to use it. A mask of 0 means the set
-- has no class restriction. Several sets can contain the same source: their masks are combined.
function Classes.SetClassMask(sourceID)
    local sets = C_TransmogSets.GetSetsContainingSourceID(sourceID)
    if not sets or #sets == 0 then return 0 end
    local mask = 0
    for _, setID in ipairs(sets) do
        local info = C_TransmogSets.GetSetInfo(setID)
        if info then
            if info.classMask == 0 then return 0 end -- one unrestricted set is enough
            mask = bit.bor(mask, info.classMask)
        end
    end
    return mask
end

local function ClassInMask(mask, classID)
    return mask == 0 or bit.band(mask, bit.lshift(1, classID - 1)) ~= 0
end

-- meta = { c = classID, s = subClassID, e = equipLoc, m = set class mask (optional) }
-- Returns true/false for the given class, using only the item type (and the mask if present).
function Classes.CanUse(meta, classID)
    local rules = Classes.rules[classID]
    if not rules or not meta then return true end
    if meta.m and not ClassInMask(meta.m, classID) then return false end
    local itemClass, sub, loc = meta.c, meta.s, meta.e

    if itemClass == ITEM_CLASS_WEAPON then
        return rules.weapons[sub] == true
    end

    if itemClass == ITEM_CLASS_ARMOR then
        if loc == "INVTYPE_SHIELD" or sub == A.Shield then return rules.shield end
        if loc == "INVTYPE_HOLDABLE" then return rules.holdable end
        if loc == "INVTYPE_CLOAK" or loc == "INVTYPE_BODY" or loc == "INVTYPE_TABARD" then return true end
        if ARMOR_TYPED_SLOTS[loc] then
            if sub == A.Generic or sub == A.Cosmetic then return true end
            return sub == rules.armor
        end
        return true
    end

    return true
end

-- Same as CanUse but for a scanned source. Fills the set class mask lazily, so data scanned before
-- the mask existed gets it the first time it is needed (no rescan required).
function Classes.CanUseSource(sourceID, classID)
    local meta = ns.db.src[sourceID]
    if not meta then return true end
    if meta.m == nil then
        local mask = Classes.SetClassMask(sourceID)
        -- Only cache once the set data is known to be loaded (see Stats warm-up); an early empty
        -- answer must not be stored as "no restriction" forever.
        if ns.Stats and ns.Stats.warmed then meta.m = mask end
        if mask ~= 0 then
            local copy = { c = meta.c, s = meta.s, e = meta.e, m = mask }
            return Classes.CanUse(copy, classID)
        end
    end
    return Classes.CanUse(meta, classID)
end

-- Classes available in the client: { {id = 1, name = "Warrior", file = "WARRIOR"}, ... }
function Classes.List()
    local list = {}
    for classID = 1, GetNumClasses() do
        local info = C_CreatureInfo.GetClassInfo(classID)
        if info then list[#list + 1] = { id = classID, name = info.className, file = info.classFile } end
    end
    return list
end

function Classes.Name(classID)
    local info = C_CreatureInfo.GetClassInfo(classID)
    return info and info.className or ("Class " .. tostring(classID))
end

function Classes.PlayerClassID()
    return select(3, UnitClass("player"))
end
