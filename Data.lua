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

-- OctoWoW's raid scaling change (patch notes 6 Oct 2026, 04:54 UTC): raids under 30
-- players got harder per player (no more sharp drops below 30), bigger ones a bit
-- easier, and some trash lost its extra small-raid reductions (ZG bats and
-- prowlers, MC Flamewakers / Protectors / Core Ragers). Times from before it
-- aren't comparable, so Rankings marks them and can show only the times since.
-- Keep "at" in step with $ScalingCutoff in tools/WhoDidIt-Sync.ps1.
D.SCALING = {
	at = 1791262440,
	short = "6 Oct",
	name = "the 6 Oct raid scaling change",
	what = "Raids under 30 players got harder per player; bigger raids a little easier.",
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

-- Where each one counts: the same spell name is cast by trash and other
-- bosses elsewhere (Rain of Fire, Blizzard, Poison Cloud...), so a name only
-- counts as avoidable in its own raid. Environment damage and your own
-- /wdi avoid spells count anywhere.
local AVOID_ZONES = {
	["Molten Core"]        = { "Lava Bomb", "Rain of Fire", "Inferno" },
	["Onyxia's Lair"]      = { "Flame Breath", "Tail Sweep", "Deep Breath", "Eruption" },
	["Blackwing Lair"]     = { "Shadow Flame", "Time Lapse", "Corrosive Acid", "Ignite Flesh", "Incinerate", "Frost Burn" },
	["Ahn'Qiraj"]          = { "Blizzard", "Dark Glare", "Eye Beam", "Sand Blast", "Toxin", "Toxic Vapors" },
	["Ruins of Ahn'Qiraj"] = { "Sand Trap", "Toxic Vapors" },
	["Naxxramas"]          = { "Void Zone", "Shadow Fissure", "Poison Cloud", "Slime Spray", "Frost Breath", "Locust Swarm", "Holy Wrath", "Eruption" },
}
for zone, spells in pairs(AVOID_ZONES) do
	for i = 1, table.getn(spells) do
		local rule = D.avoid[spells[i]]
		if rule then
			rule.zones = rule.zones or {}
			rule.zones[zone] = true
		end
	end
end

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

-- Which consumable "slot" each buff fills (one of each slot can be up at a
-- time), the aura names this server really uses (often not the item's name)
-- and spell IDs - from DopingControl by ShempError (MIT licence,
-- octowow.st/git/ShempError/DopingControl), measured on OctoWoW / Turtle.
D.consumeSlot = {
	["Flask of the Titans"] = "FLASK", ["Flask of Supreme Power"] = "FLASK", ["Supreme Power"] = "FLASK",
	["Flask of Distilled Wisdom"] = "FLASK", ["Distilled Wisdom"] = "FLASK", ["Flask of Chromatic Resistance"] = "FLASK",
	["Chromatic Resistance"] = "FLASK", ["Flask of Petrification"] = "FLASK", ["Petrification"] = "FLASK",
	["Well Fed"] = "FOOD", ["Increased Stamina"] = "FOOD", ["Increased Intellect"] = "FOOD", ["Increased Agility"] = "FOOD",
	["Increased Strength"] = "FOOD", ["Dragonbreath Chili"] = "FOOD",
	["Winterfall Firewater"] = "AP", ["Juju Might"] = "AP",
	["Juju Power"] = "STR", ["Elixir of Giants"] = "STR", ["Elixir of the Giants"] = "STR", ["Elixir of Brute Force"] = "STR",
	["Elixir of the Mongoose"] = "AGI", ["Elixir of Greater Agility"] = "AGI", ["Greater Agility"] = "AGI", ["Elixir of Agility"] = "AGI",
	["Rage of Ages"] = "BL", ["R.O.I.D.S."] = "BL", ["Strike of the Scorpok"] = "BL", ["Ground Scorpok Assay"] = "BL",
	["Spirit of Boar"] = "BL", ["Spirit of the Boar"] = "BL", ["Lung Juice Cocktail"] = "BL", ["Infallible Mind"] = "BL",
	["Cerebral Cortex Compound"] = "BL", ["Spiritual Domination"] = "BL", ["Gizzard Gum"] = "BL",
	["Spirit of Zanza"] = "ZANZA", ["Swiftness of Zanza"] = "ZANZA", ["Sheen of Zanza"] = "ZANZA",
	["Greater Arcane Elixir"] = "GAE", ["Arcane Elixir"] = "GAE",
	["Elixir of Shadow Power"] = "SCHOOL", ["Shadow Power"] = "SCHOOL", ["Elixir of Frost Power"] = "SCHOOL", ["Frost Power"] = "SCHOOL",
	["Greater Frost Power"] = "SCHOOL", ["Elixir of Greater Firepower"] = "SCHOOL", ["Greater Firepower"] = "SCHOOL",
	["Elixir of Firepower"] = "SCHOOL",
	["Dreamtonic"] = "DREAMT", ["Dreamshard Elixir"] = "SHARD",
	["Mageblood Potion"] = "MP5", ["Mageblood"] = "MP5", ["Mana Regeneration"] = "MP5",
	["Elixir of Superior Defense"] = "ARM", ["Elixir of Greater Defense"] = "ARM", ["Greater Armor"] = "ARM",
	["Elixir of Fortitude"] = "HPELX", ["Health II"] = "HPELX",
	["Medivh's Merlot"] = "ALC", ["Medivh's Merlot Blue"] = "ALC", ["Medivh's Merlot Blue Label"] = "ALC",
	["Rumsey Rum Black Label"] = "ALC", ["Rumsey Rum"] = "ALC", ["Rumsey Rum Light"] = "ALC", ["Gordok Green Grog"] = "ALC",
	["Kreeg's Stout Beatdown"] = "ALC",
	["Greater Fire Protection"] = "PROT", ["Fire Protection"] = "PROT", ["Greater Frost Protection"] = "PROT",
	["Frost Protection"] = "PROT", ["Greater Nature Protection"] = "PROT", ["Nature Protection"] = "PROT",
	["Greater Shadow Protection"] = "PROT", ["Shadow Protection"] = "PROT", ["Holy Protection"] = "PROT",
	["Greater Arcane Protection"] = "PROT", ["Arcane Protection"] = "PROT",
}
local SLOT_CAT = {
	FLASK = "Flask", FOOD = "Food", ALC = "Food", AP = "Buff", BL = "Buff", ZANZA = "Buff", STR = "Elixir", AGI = "Elixir",
	GAE = "Elixir", SCHOOL = "Elixir", DREAMT = "Elixir", SHARD = "Elixir", MP5 = "Elixir", ARM = "Elixir", HPELX = "Elixir",
	PROT = "Protection",
}
for name, slot in pairs(D.consumeSlot) do
	if not D.consumeBuffs[name] then D.consumeBuffs[name] = SLOT_CAT[slot] end
end

-- spell ID -> aura name, for when the client reports a name we don't know
-- (a trailing space, a different rank name...)
D.consumeById = {
	[17626] = "Flask of the Titans", [17628] = "Flask of Supreme Power", [17627] = "Flask of Distilled Wisdom",
	[17629] = "Flask of Chromatic Resistance", [17624] = "Flask of Petrification", [15852] = "Dragonbreath Chili",
	[17038] = "Winterfall Firewater", [16329] = "Juju Might", [16323] = "Juju Power", [11405] = "Elixir of the Giants",
	[17537] = "Elixir of Brute Force", [17538] = "Elixir of the Mongoose", [11334] = "Greater Agility",
	[11328] = "Elixir of Agility", [10667] = "Rage of Ages", [10669] = "Strike of the Scorpok", [10668] = "Spirit of Boar",
	[10692] = "Infallible Mind", [10693] = "Spiritual Domination", [24382] = "Spirit of Zanza",
	[17539] = "Greater Arcane Elixir", [11390] = "Arcane Elixir", [11474] = "Elixir of Shadow Power",
	[21920] = "Elixir of Frost Power", [56544] = "Greater Frost Power", [26276] = "Elixir of Greater Firepower",
	[7844] = "Elixir of Firepower", [45489] = "Dreamtonic", [45427] = "Dreamshard Elixir", [24363] = "Mageblood Potion",
	[11348] = "Elixir of Superior Defense", [11349] = "Elixir of Greater Defense", [3593] = "Health II",
	[57106] = "Medivh's Merlot", [57107] = "Medivh's Merlot Blue Label", [25804] = "Rumsey Rum Black Label",
	[20875] = "Rumsey Rum", [25037] = "Rumsey Rum Light", [22789] = "Gordok Green Grog", [22790] = "Kreeg's Stout Beatdown",
	[17543] = "Greater Fire Protection", [7233] = "Fire Protection", [17544] = "Greater Frost Protection",
	[7239] = "Frost Protection", [17546] = "Greater Nature Protection", [7254] = "Nature Protection",
	[17548] = "Greater Shadow Protection", [7242] = "Shadow Protection", [7245] = "Holy Protection",
	[17549] = "Greater Arcane Protection",
}
-- names shared with a class buff: only these spell IDs are the consumable
-- (the priest's Shadow Protection is not a Shadow Protection Potion)
D.consumeIdOnly = { ["Shadow Protection"] = { [7242] = true, [17548] = true } }

-- what each role is expected to bring, for the slacker check. Each need is
-- met by any one of its slots ("WPN" = an oil or stone on the main hand).
-- Flasks are only expected in the big raids (D.flaskZones).
D.consumeNeeds = {
	tank   = { { "flask", { "FLASK" } }, { "food", { "FOOD" } }, { "defense elixir", { "ARM", "HPELX" } },
	           { "agility / strength", { "AGI", "STR", "AP", "BL" } } },
	melee  = { { "flask", { "FLASK" } }, { "food", { "FOOD" } }, { "Mongoose / agility", { "AGI" } },
	           { "strength / AP", { "STR", "AP", "BL" } }, { "weapon stone", "WPN" } },
	ranged = { { "food", { "FOOD" } }, { "Mongoose / agility", { "AGI" } } },
	caster = { { "flask", { "FLASK" } }, { "food", { "FOOD" } }, { "arcane elixir", { "GAE" } }, { "wizard oil", "WPN" } },
	healer = { { "flask", { "FLASK" } }, { "food", { "FOOD" } }, { "Mageblood", { "MP5" } }, { "mana oil", "WPN" } },
}
-- shamans use their own weapon imbue, not an oil / stone ("IMBUE" = the
-- main-hand enchant's name must contain one of these). Tanks: Rockbiter,
-- with Windfury / Frostbrand as the accepted exceptions.
D.consumeNeedsClass = {
	SHAMAN = {
		tank  = { { "flask", { "FLASK" } }, { "food", { "FOOD" } }, { "defense elixir", { "ARM", "HPELX" } },
		          { "agility / strength", { "AGI", "STR", "AP", "BL" } },
		          { "Rockbiter weapon", "IMBUE", { "Rockbiter", "Windfury", "Frostbrand" } } },
		melee = { { "flask", { "FLASK" } }, { "food", { "FOOD" } }, { "Mongoose / agility", { "AGI" } },
		          { "strength / AP", { "STR", "AP", "BL" } },
		          { "Windfury weapon", "IMBUE", { "Windfury", "Rockbiter", "Flametongue", "Frostbrand" } } },
	},
}
-- class cooldowns that can stop a death, and their cooldown in seconds
-- (true = a talent, so only if they took it). When someone dies, WhoDidIt
-- freezes which of these (and potion / healthstone) were off cooldown.
D.defensives = {
	WARRIOR = { { "Shield Wall", 1800 }, { "Last Stand", 600, true } },
	PALADIN = { { "Divine Shield", 300 }, { "Blessing of Protection", 300 }, { "Lay on Hands", 3600 } },
	MAGE    = { { "Ice Block", 300, true } },
	ROGUE   = { { "Evasion", 300 }, { "Vanish", 300 } },
	HUNTER  = { { "Feign Death", 30 } },
	PRIEST  = { { "Desperate Prayer", 600, true } },
	DRUID   = { { "Frenzied Regeneration", 180 } },
}
D.defensiveSpell = {}
for _, list in pairs(D.defensives) do
	for i = 1, table.getn(list) do D.defensiveSpell[list[i][1]] = true end
end

-- the kind of a game-saving play, from words in its text (Heroes tab, Hall of Fame)
D.saveTypes = {
	{ "absorbed", "Shield" }, { "healed", "Heal" }, { "taunted", "Taunt" }, { "back off", "Taunt" },
	{ "dispelled", "Dispel" }, { "innervated", "Innervate" }, { "tranquilized", "Tranq" },
	{ "interrupted", "Interrupt" }, { "Blessing of Protection", "Protect" }, { "Lay on Hands", "Protect" },
	{ "resurrect", "Battle res" }, { "Rebirth", "Battle res" }, { "survived", "Survival" },
}

D.flaskZones = {
	["Molten Core"] = true, ["Blackwing Lair"] = true, ["Ahn'Qiraj"] = true, ["Naxxramas"] = true,
	["Emerald Sanctum"] = true, ["Tower of Karazhan"] = true,
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
