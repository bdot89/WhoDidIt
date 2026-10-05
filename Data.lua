--[[--------------------------------------------------------------------
	WhoDidIt - mechanics database (enUS spell / unit names)

	Everything here is matched by NAME, so it works no matter which spell
	rank or id the server uses. Add your own avoidable spells in game with
	/wdi avoid <spell name>.
----------------------------------------------------------------------]]

local W = WhoDidIt
local D = {}
W.Data = D

------------------------------------------------------------------ encounters
-- key = encounter name. bosses = units that belong to it (default: key).
-- final   = encounter only ends when this unit dies
-- noAggro = boss switches targets by design (threat wipes, random targets,
--           knockbacks) so target changes aren't blamed unless the
--           player was also over 100% threat
-- noDeath = boss never dies (encounter is won when the raid survives)
-- idleGrace = seconds the raid may be out of combat between phases

D.encounters = {}
D.bosses = {}  -- unit name -> encounter name

local function zone(z, list)
	for enc, def in pairs(list) do
		def.zone = z
		D.encounters[enc] = def
	end
end

zone("Molten Core", {
	["Lucifron"] = {}, ["Magmadar"] = {}, ["Gehennas"] = {}, ["Garr"] = {},
	["Shazzrah"] = { noAggro = true }, ["Baron Geddon"] = {},
	["Golemagg the Incinerator"] = {}, ["Sulfuron Harbinger"] = {},
	["Majordomo Executus"] = { noDeath = true }, ["Ragnaros"] = {},
})

zone("Onyxia's Lair", {
	["Onyxia"] = { noAggro = true },
})

zone("Blackwing Lair", {
	["Razorgore the Untamed"] = { noAggro = true },
	["Vaelastrasz the Corrupt"] = {},
	["Broodlord Lashlayer"] = { noAggro = true },
	["Firemaw"] = {}, ["Ebonroc"] = {}, ["Flamegor"] = {}, ["Chromaggus"] = {},
	["Nefarian"] = { bosses = { "Lord Victor Nefarius", "Nefarian" }, final = "Nefarian", noAggro = true },
})

zone("Zul'Gurub", {
	["High Priestess Jeklik"] = { noAggro = true }, ["High Priest Venoxis"] = {},
	["High Priestess Mar'li"] = {}, ["High Priest Thekal"] = {},
	["High Priestess Arlokk"] = { noAggro = true }, ["Hakkar"] = {},
	["Bloodlord Mandokir"] = { noAggro = true }, ["Jin'do the Hexxer"] = {},
	["Gahz'ranka"] = { noAggro = true }, ["Gri'lek"] = { noAggro = true },
	["Hazza'rah"] = {}, ["Renataki"] = { noAggro = true }, ["Wushoolay"] = {},
})

zone("Ruins of Ahn'Qiraj", {
	["Kurinnaxx"] = {}, ["General Rajaxx"] = {}, ["Moam"] = {},
	["Buru the Gorger"] = { noAggro = true }, ["Ayamiss the Hunter"] = { noAggro = true },
	["Ossirian the Unscarred"] = { noAggro = true },
})

zone("Ahn'Qiraj", {
	["The Prophet Skeram"] = { noAggro = true },
	["Bug Trio"] = { bosses = { "Lord Kri", "Princess Yauj", "Vem" } },
	["Battleguard Sartura"] = { noAggro = true },
	["Fankriss the Unyielding"] = {}, ["Viscidus"] = {}, ["Princess Huhuran"] = {},
	["Twin Emperors"] = { bosses = { "Emperor Vek'lor", "Emperor Vek'nilash" }, noAggro = true },
	["Ouro"] = { noAggro = true },
	["C'Thun"] = { bosses = { "Eye of C'Thun", "C'Thun" }, final = "C'Thun", noAggro = true, idleGrace = 15 },
})

zone("Naxxramas", {
	["Anub'Rekhan"] = {}, ["Grand Widow Faerlina"] = {}, ["Maexxna"] = {},
	["Noth the Plaguebringer"] = { noAggro = true }, ["Heigan the Unclean"] = { noAggro = true },
	["Loatheb"] = {}, ["Instructor Razuvious"] = { noAggro = true },
	["Gothik the Harvester"] = { noAggro = true },
	["The Four Horsemen"] = { bosses = { "Thane Korth'azz", "Lady Blaumeux", "Highlord Mograine", "Sir Zeliek" }, noAggro = true },
	["Patchwerk"] = {}, ["Grobbulus"] = {}, ["Gluth"] = {},
	["Thaddius"] = { bosses = { "Stalagg", "Feugen", "Thaddius" }, final = "Thaddius", idleGrace = 25 },
	["Sapphiron"] = { noAggro = true }, ["Kel'Thuzad"] = {},
})

zone("World", {
	["Azuregos"] = { noAggro = true }, ["Lord Kazzak"] = {},
	["Emeriss"] = {}, ["Lethon"] = {}, ["Taerar"] = {}, ["Ysondre"] = {},
})

-- Turtle WoW raids (worldboss classification catches anything missing)
zone("Emerald Sanctum", {
	["Erennius"] = {}, ["Solnius"] = { noAggro = true },
})

zone("Karazhan", {
	["Master Blacksmith Rolfen"] = {}, ["Brood Queen Araxxna"] = {}, ["Grizikil"] = {},
	["Clawlord Howlfang"] = {}, ["Lord Blackwald II"] = {}, ["Moroes"] = {},
	["Keeper Gnarlmoon"] = {}, ["Ley-Watcher Incantagos"] = {}, ["Anomalus"] = {},
	["Echo of Medivh"] = {}, ["Sanv Tas'dal"] = {}, ["Kruul"] = {},
	["Rupturan the Broken"] = {}, ["Mephistroth"] = { noAggro = true },
})

for enc, def in pairs(D.encounters) do
	local list = def.bosses or { enc }
	for i = 1, table.getn(list) do D.bosses[list[i]] = enc end
end

------------------------------------------------------------------ full clears (Rankings)
-- An instance counts as cleared when every encounter in its list has died
-- in one run (first combat in the instance -> last required kill).
-- Optional bosses (ZG's Edge of Madness, AQ40's Bug Trio / Viscidus / Ouro)
-- aren't required.

D.clearOrder = {
	"Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub",
	"Ruins of Ahn'Qiraj", "Ahn'Qiraj", "Naxxramas", "Emerald Sanctum",
}

D.clears = {
	["Molten Core"] = {
		"Lucifron", "Magmadar", "Gehennas", "Garr", "Shazzrah", "Baron Geddon",
		"Golemagg the Incinerator", "Sulfuron Harbinger", "Majordomo Executus", "Ragnaros",
	},
	["Onyxia's Lair"] = { "Onyxia" },
	["Blackwing Lair"] = {
		"Razorgore the Untamed", "Vaelastrasz the Corrupt", "Broodlord Lashlayer", "Firemaw",
		"Ebonroc", "Flamegor", "Chromaggus", "Nefarian",
	},
	["Zul'Gurub"] = {
		"High Priestess Jeklik", "High Priest Venoxis", "High Priestess Mar'li", "Bloodlord Mandokir",
		"High Priest Thekal", "High Priestess Arlokk", "Jin'do the Hexxer", "Hakkar",
	},
	["Ruins of Ahn'Qiraj"] = {
		"Kurinnaxx", "General Rajaxx", "Moam", "Buru the Gorger", "Ayamiss the Hunter", "Ossirian the Unscarred",
	},
	["Ahn'Qiraj"] = {
		"The Prophet Skeram", "Battleguard Sartura", "Fankriss the Unyielding", "Princess Huhuran",
		"Twin Emperors", "C'Thun",
	},
	["Naxxramas"] = {
		"Anub'Rekhan", "Grand Widow Faerlina", "Maexxna", "Noth the Plaguebringer", "Heigan the Unclean",
		"Loatheb", "Instructor Razuvious", "Gothik the Harvester", "The Four Horsemen", "Patchwerk",
		"Grobbulus", "Gluth", "Thaddius", "Sapphiron", "Kel'Thuzad",
	},
	["Emerald Sanctum"] = { "Erennius", "Solnius" },
}

-- Rankings list name for instances whose zone text is short
D.instanceTitle = { ["Ahn'Qiraj"] = "Temple of Ahn'Qiraj" }

-- what kind of realm each one is, so banter can say "N'Zoth (PvE)". Chronicle's
-- data doesn't include it; realms not listed are just called by their name.
D.realmTypes = {
	["Y'Shaarj"] = "PvP",        -- OctoWoW
	["N'Zoth"]   = "PvE",
	["C'Thun"]   = "Hardcore",
}

------------------------------------------------------------------ avoidable damage
-- Damage from these (cast by an enemy) is the victim's fault.
-- notTank = tanks are expected to take it. w = blame weight per instance.

D.avoid = {
	-- Molten Core
	["Lava Bomb"]        = { tip = "Magmadar's fire patches - move out" },
	["Rain of Fire"]     = { tip = "Move out of Rain of Fire" },
	["Inferno"]          = { tip = "Run away from Baron Geddon during Inferno" },
	-- Onyxia
	["Flame Breath"]     = { notTank = true, tip = "Don't stand in front of the dragon" },
	["Tail Sweep"]       = { notTank = true, tip = "Don't stand behind the dragon" },
	["Deep Breath"]      = { tip = "Get out of Onyxia's Deep Breath path" },
	["Eruption"]         = { tip = "Erupting floor (Onyxia cracks / Heigan dance) - move" },
	-- Blackwing Lair
	["Shadow Flame"]     = { notTank = true, tip = "Frontal breath - stay out of the cone" },
	["Time Lapse"]       = { notTank = true, tip = "Hide behind the gate during Chromaggus breaths" },
	["Corrosive Acid"]   = { notTank = true, tip = "Hide behind the gate during Chromaggus breaths" },
	["Ignite Flesh"]     = { notTank = true, tip = "Hide behind the gate during Chromaggus breaths" },
	["Incinerate"]       = { notTank = true, tip = "Hide behind the gate during Chromaggus breaths" },
	["Frost Burn"]       = { notTank = true, tip = "Hide behind the gate during Chromaggus breaths" },
	-- Ahn'Qiraj
	["Blizzard"]         = { tip = "Move out of Blizzard" },
	["Dark Glare"]       = { tip = "Move away from C'Thun's Dark Glare" },
	["Eye Beam"]         = { w = 0.5, tip = "Spread out - Eye Beam chains to nearby players" },
	["Sand Blast"]       = { notTank = true, tip = "Ouro's frontal - stay out" },
	["Toxin"]            = { tip = "Viscidus' poison cloud - move" },
	["Toxic Vapors"]     = { tip = "Poison cloud - move" },
	["Sand Trap"]        = { tip = "Kurinnaxx's sand trap - move" },
	-- Naxxramas
	["Void Zone"]        = { tip = "Move out of Lady Blaumeux's Void Zone" },
	["Shadow Fissure"]   = { tip = "Move away from Kel'Thuzad's Shadow Fissure immediately" },
	["Poison Cloud"]     = { tip = "Don't stand in the poison clouds" },
	["Slime Spray"]      = { notTank = true, tip = "Grobbulus' frontal - stay out" },
	["Frost Breath"]     = { notTank = true, tip = "Hide behind an ice block / stay out of the breath" },
	["Locust Swarm"]     = { notTank = true, w = 0.5, tip = "Run away from Anub'Rekhan during Locust Swarm" },
	["Holy Wrath"]       = { w = 0.5, tip = "Zeliek's Holy Wrath chains - spread" },
	-- environment (see Tracker ENV names)
	["Falling"]          = { tip = "Fell" },
	["Lava"]             = { tip = "Stood in lava" },
	["Burning ground"]   = { tip = "Stood in fire" },
	["Fell off the edge"]= { tip = "Fell off the platform" },
}

D.customRule = { tip = "Custom avoidable spell (/wdi avoid)" }

------------------------------------------------------------------ carrier mechanics
-- A player gets the debuff and must take it away from the raid. If the
-- splash spell then hits other players, the carrier is blamed.

D.carriers = {
	["Living Bomb"]        = { splash = { "Living Bomb" }, win = 10, tip = "Run out of the raid with Living Bomb" },
	["Detonate Mana"]      = { splash = { "Detonate Mana", "Mana Detonation" }, win = 6, tip = "Move away from the raid with Detonate Mana" },
	["Mutating Injection"] = { splash = { "Mutating Injection", "Mutagen Explosion" }, win = 12, tip = "Drop Mutating Injection away from the raid" },
}

D.splashIdx = {}  -- splash spell -> list of carrier debuffs
for debuff, rule in pairs(D.carriers) do
	for i = 1, table.getn(rule.splash) do
		local sp = rule.splash[i]
		D.splashIdx[sp] = D.splashIdx[sp] or {}
		tinsert(D.splashIdx[sp], debuff)
	end
end

------------------------------------------------------------------ stacking debuffs

D.stacks = {
	["Mark of Korth'azz"] = { max = 4, tip = "Rotate off before marks stack" },
	["Mark of Blaumeux"]  = { max = 4, tip = "Rotate off before marks stack" },
	["Mark of Mograine"]  = { max = 4, tip = "Rotate off before marks stack" },
	["Mark of Zeliek"]    = { max = 4, tip = "Rotate off before marks stack" },
	["Flame Buffet"]      = { max = 12, notTank = true, tip = "Line of sight Firemaw to drop Flame Buffet stacks" },
}

------------------------------------------------------------------ debuffs that should be removed

D.dispel = {
	["Lucifron's Curse"] = "Curse", ["Impending Doom"] = "Magic",
	["Gehennas' Curse"] = "Curse", ["Shazzrah's Curse"] = "Curse",
	["Ignite Mana"] = "Magic", ["Magma Shackles"] = "Magic",
	["Veil of Shadow"] = "Curse",
	["Brood Affliction: Blue"] = "Magic", ["Brood Affliction: Black"] = "Curse",
	["Brood Affliction: Green"] = "Poison",
	["Curse of the Plaguebringer"] = "Curse", ["Necrotic Poison"] = "Poison",
	["Decrepit Fever"] = "Disease", ["Life Drain"] = "Curse",
	["Noxious Poison"] = "Poison", ["Delusions of Jin'do"] = "Curse",
	["Holy Fire"] = "Magic", ["Poison Bolt Volley"] = "Poison",
}
D.dispelSlow = 6  -- average seconds before it counts as slow

------------------------------------------------------------------ misc lists

D.mc = {
	["Dominate Mind"] = true, ["Chains of Kel'Thuzad"] = true, ["Cause Insanity"] = true,
	["True Fulfillment"] = true, ["Shadow Command"] = true, ["Brain Wash"] = true,
	["Mind Control"] = true,
}

-- dying with one of these is the mechanic working as intended
D.expectedDeath = { ["Burning Adrenaline"] = true }

-- enemy casts that should be interrupted
D.interrupts = {
	["Dark Mending"] = true, ["Great Heal"] = true, ["Greater Heal"] = true,
	["Heal"] = true, ["Flash Heal"] = true, ["Holy Light"] = true,
	["Frostbolt"] = true, ["Arcane Explosion"] = true,
}

-- player abilities that interrupt / lock out casts
D.kickSpells = {
	["Kick"] = true, ["Pummel"] = true, ["Shield Bash"] = true, ["Earth Shock"] = true,
	["Counterspell"] = true, ["Silence"] = true, ["Hammer of Justice"] = true,
	["Kidney Shot"] = true, ["Cheap Shot"] = true, ["Gouge"] = true, ["Bash"] = true,
	["Concussion Blow"] = true, ["War Stomp"] = true, ["Spell Lock"] = true,
	["Intimidation"] = true, ["Feral Charge"] = true, ["Scatter Shot"] = true,
}

D.taunts = {
	["Taunt"] = true, ["Growl"] = true, ["Mocking Blow"] = true,
	["Challenging Shout"] = true, ["Challenging Roar"] = true, ["Hand of Reckoning"] = true,
}

------------------------------------------------------------------ heroes (game-saving moments)

-- absorb shields: if one eats a hit that would have killed the target, the caster saved them
D.absorbSpells = {
	["Power Word: Shield"] = true, ["Ice Barrier"] = true, ["Mana Shield"] = true, ["Sacrifice"] = true,
}
-- cast on someone else: "hp" = target was low on health, "mana" = target low on mana,
-- "rez" = target was dead (battle res)
D.saveCasts = {
	["Lay on Hands"] = "hp", ["Blessing of Protection"] = "hp", ["Divine Intervention"] = "hp",
	["Rebirth"] = "rez", ["Innervate"] = "mana",
}
-- emergency buttons pressed on yourself at low health
D.selfSaves = {
	["Shield Wall"] = true, ["Last Stand"] = true, ["Ice Block"] = true, ["Divine Shield"] = true,
	["Divine Protection"] = true, ["Evasion"] = true, ["Vanish"] = true, ["Frenzied Regeneration"] = true,
	["Feign Death"] = true,
}

D.frenzy  = { ["Frenzy"] = true }
D.berserk = { ["Berserk"] = true }  -- "Enrage" is a mechanic on many bosses (Faerlina, Golemagg), not a timer

-- boss casts that only happen because the raid did something wrong
D.raidFail = {
	["Magma Blast"]    = { blame = "tank", tip = "Ragnaros cast Magma Blast - nobody was in melee range" },
	["Ball Lightning"] = { blame = "tank", tip = "Thaddius cast Ball Lightning - nobody was in melee range" },
}

-- raid debuffs whose uptime on the boss is reported
D.raidDebuffs = {
	["Sunder Armor"] = true, ["Expose Armor"] = true, ["Faerie Fire"] = true,
	["Faerie Fire (Feral)"] = true, ["Curse of Recklessness"] = true,
	["Curse of the Elements"] = true, ["Curse of Shadow"] = true,
	["Shadow Vulnerability"] = true, ["Fire Vulnerability"] = true, ["Winter's Chill"] = true,
	["Demoralizing Shout"] = true, ["Demoralizing Roar"] = true, ["Thunder Clap"] = true,
	["Judgement of Wisdom"] = true, ["Judgement of Light"] = true,
	["Judgement of the Crusader"] = true, ["Hunter's Mark"] = true,
}

-- debuffs not worth listing in death recaps
D.ignoreDebuffs = {
	["Weakened Soul"] = true, ["Forbearance"] = true, ["Recently Bandaged"] = true,
	["Mind Vision"] = true, ["Resurrection Sickness"] = true,
}

-- pull buff check: provider class must be in the raid for it to be reported
D.buffGroups = {
	{ label = "Fortitude", from = "PRIEST", names = { "Power Word: Fortitude", "Prayer of Fortitude" } },
	{ label = "Mark of the Wild", from = "DRUID", names = { "Mark of the Wild", "Gift of the Wild" } },
	{ label = "Arcane Intellect", from = "MAGE", mana = true, names = { "Arcane Intellect", "Arcane Brilliance" } },
}

D.flasks = {
	["Flask of the Titans"] = true, ["Distilled Wisdom"] = true,
	["Supreme Power"] = true, ["Chromatic Resistance"] = true, ["Petrification"] = true,
}

-- consumable buffs (aura names) shown on the Consumes tab, by category
D.consumeCats = { "Flask", "Elixir", "Food", "Buff", "Protection", "Potion" }
D.consumeBuffs = {
	-- flasks
	["Flask of the Titans"] = "Flask", ["Distilled Wisdom"] = "Flask", ["Supreme Power"] = "Flask",
	["Chromatic Resistance"] = "Flask", ["Petrification"] = "Flask",
	-- battle / guardian elixirs
	["Elixir of the Mongoose"] = "Elixir", ["Greater Agility"] = "Elixir", ["Elixir of the Giants"] = "Elixir",
	["Greater Arcane Elixir"] = "Elixir", ["Arcane Elixir"] = "Elixir", ["Greater Firepower"] = "Elixir",
	["Shadow Power"] = "Elixir", ["Frost Power"] = "Elixir", ["Mana Regeneration"] = "Elixir",
	["Greater Armor"] = "Elixir", ["Health II"] = "Elixir", ["Greater Intellect"] = "Elixir",
	["Elixir of Brute Force"] = "Elixir", ["Dreamshard Elixir"] = "Elixir", ["Dreamtonic"] = "Elixir",
	-- food & drink
	["Well Fed"] = "Food", ["Increased Stamina"] = "Food", ["Increased Intellect"] = "Food",
	["Increased Agility"] = "Food", ["Increased Strength"] = "Food", ["Rumsey Rum Black Label"] = "Food",
	["Gordok Green Grog"] = "Food",
	-- juju, zanza, Blasted Lands, firewater
	["Juju Power"] = "Buff", ["Juju Might"] = "Buff", ["Juju Ember"] = "Buff", ["Juju Chill"] = "Buff",
	["Juju Flurry"] = "Buff", ["Juju Guile"] = "Buff", ["Juju Escape"] = "Buff",
	["Spirit of Zanza"] = "Buff", ["Swiftness of Zanza"] = "Buff", ["Sheen of Zanza"] = "Buff",
	["Rage of Ages"] = "Buff", ["Strike of the Scorpok"] = "Buff", ["Infallible Mind"] = "Buff",
	["Spiritual Domination"] = "Buff", ["Spirit of the Boar"] = "Buff", ["Winterfall Firewater"] = "Buff",
	-- protection potions
	["Fire Protection"] = "Protection", ["Shadow Protection"] = "Protection", ["Nature Protection"] = "Protection",
	["Frost Protection"] = "Protection", ["Arcane Protection"] = "Protection", ["Holy Protection"] = "Protection",
	-- combat potions
	["Free Action"] = "Potion", ["Invulnerability"] = "Potion", ["Restoration"] = "Potion",
	["Greater Stoneshield"] = "Potion", ["Stoneshield"] = "Potion", ["Mighty Rage"] = "Potion",
}

-- used items on the Consumes tab are grouped by these name patterns
D.protItems = { "Protection Potion", "Free Action", "Invulnerability", "Restorative", "Stoneshield", "Mighty Rage" }

-- consumables are recorded by item name (or the spell name if the item isn't
-- cached); any name containing one of these counts for the category
D.manaItems = {
	"Mana Potion", "Restore Mana", "Demonic Rune", "Dark Rune", "Rune of",
	"Tea", "Mana Gem", "Mana Jade", "Mana Citrine", "Mana Ruby", "Mana Agate",
	"Night Dragon's Breath", "Mana Oil",
}
D.healthItems = {
	"Healing Potion", "Healthstone", "Rejuvenation Potion", "Whipper Root",
	"Bandage", "First Aid", "Healing Draught", "Lifegiving Gem", "Tea",
	"Limited Invulnerability", "Stoneshield", "Restorative",
}

-- classes with a real interrupt
D.kickClasses = { ROGUE = true, WARRIOR = true, SHAMAN = true, MAGE = true }

-- who can remove what
D.dispellers = {
	Curse   = { MAGE = true, DRUID = true },
	Magic   = { PRIEST = true, PALADIN = true },
	Poison  = { DRUID = true, SHAMAN = true, PALADIN = true },
	Disease = { PRIEST = true, PALADIN = true, SHAMAN = true },
}

D.manaClasses ={ PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true, PALADIN = true, SHAMAN = true, HUNTER = true }
