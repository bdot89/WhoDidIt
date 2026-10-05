# WhoDidIt

Raid wipe & death analyser for Turtle WoW / OctoWoW (1.12 client). It records every
boss fight automatically and tells you **why** it went wrong and **who** caused it.

Open it with `/whodidit` or `/wdi`.

## Requirements

| Mod | Needed for |
| --- | --- |
| **Nampower** (dll) | damage, healing, swings, debuffs, deaths, consumables. Without it only deaths are tracked. |
| **SuperWoW** (dll) | GUID → name lookups, boss target polling (aggro), cast events (interrupts, activity, tranqs). |
| TWThreat (addon, optional) | If loaded, WhoDidIt reads the same server threat packets. If not, WhoDidIt asks the server itself (`/wdi threat off` to stop). |

WhoDidIt switches on the Nampower CVars it needs (`NP_EnableAutoAttackEvents`,
`NP_EnableSpellHealEvents`, `NP_EnableSpellGoEvents`).

## What it detects

- **Deaths** – full recap of the last 15 s (damage, heals, debuffs, items, HP %), with the cause:
  stood in avoidable damage, killed by a bomb/injection carrier, meleed to death after pulling aggro,
  tank death (no heals / crushing blows / damage vs healing), mind-controlled players, falling/lava, or plain "overwhelmed".
- **Aggro** – every boss target change, from boss melee swings and target polling, with the Turtle server threat % at that moment.
  Non-tanks who pull aggro are blamed (boss mechanics with threat wipes are excused unless they were over 100 %).
- **Mechanics** – avoidable damage (Void Zone, Shadow Fissure, Heigan dance, Chromaggus breaths…),
  carriers who splash the raid (Living Bomb, Detonate Mana, Mutating Injection), stacking marks (Four Horsemen, Firemaw).
- **Raid-wide failures** – uninterrupted heals/frostbolts, slow decurses/dispels, Frenzy not tranquilized,
  Magma Blast / Ball Lightning (nobody in melee), boss enrage timers, healers out of mana at the wipe.
- **Playing badly** – low activity (idle time while alive), DPS far below the raid median, early pulls, near-aggro threat peaks.
- **Meters** – damage, healing, damage taken, activity, and utility (kicks, dispels, tranqs, items used).
- **Pull check** – missing Fortitude / Mark / Intellect and flasks at pull. Boss debuff uptimes (Sunder, curses, Faerie Fire…).

## Demo / test mode

Click **Demo fight** (bottom-left of the window) or type `/wdi demo` to add two scripted sample fights
against a "Grand Demonstrator", with a fake 20-player raid. They run through the real analyser, so every tab and
every feature has something to show:

- **Wipe:** a rogue pulls before the tank, a mage rips aggro at 112% and gets flattened, a Living Bomb carrier
  kills a healer, a warrior dies in Void Zone, a priest stands in Rain of Fire, a mind-controlled priest kills a shaman,
  Dark Mending goes uninterrupted, Frenzy isn't tranqed, Magma Blast, slow decursing, a tank dies with no heals,
  healers run out of mana, the boss enrages, and an AFK mage.
- **Kill:** a cleaner fight with a single death, good interrupts and fast tranqs, to show Big Them Up.

**Shift-click** Demo fight (or `/wdi demo live`) to watch the wipe play out as a LIVE fight at 4x speed (~48s).
Demo fights are labelled *(demo)*. Automatic post-fight messages for demo fights stay in your own chat. Clicking Report, Name & Shame or Big Them Up posts them for real to your shout channel, tagged `DEMO`.
`/wdi demo clear` removes them.

## Heroes

The **Heroes** tab finds game-saving plays and gives hero points:

| Play | Points |
| --- | --- |
| Heal landing on someone under 20% health who then survives | 2 |
| Power Word: Shield / Ice Barrier soaking a hit that would have killed | 3 |
| Tank taunting the boss off a non-tank who then survives | 3 (1.5 without a taunt cast) |
| Lay on Hands / Blessing of Protection on someone under 35% (or BoP on whoever has aggro) | 3 |
| Battle res (Rebirth) | 3 |
| Dispelling mind control | 2 |
| Innervate on someone under 30% mana | 1.5 |
| Interrupting a dangerous cast | 0.5 each (max 3) |
| Tranquilizing a Frenzy within 3s | 1 |
| Last-second potion / healthstone / Shield Wall etc. under 30% health, and surviving | 1 |

The top hero shows on the Summary, and as **Lifesaver** in Big Them Up. **Post heroes** shares the board.

## Consumes

The **Consumes** tab lists every player's consumable buffs during the fight (flask, elixirs, food, juju/zanza,
protection potions…) and every item they used. Three post buttons share it:
- **Post summary:** counts, protection potions, items used, the most prepared players
- **Post missing:** who had no flask, food or elixirs
- **Post everyone:** one line per player

## Chat colours

Every post uses the same scheme:
- the `[WhoDidIt]` tag in red, with the post's kind (REPORT, NAME & SHAME, BIG UPS, CONSUMES, HEROES) in gold
- line labels (`Verdict:`, `Blame:`, `Flasks:`…) in gold
- player names in their class colour, times in light blue, numbers in white
- WIPE / KILL in red / green

## Shout-outs

Two buttons in the top-right of the window post data-driven awards to your **designated channel**
(the `To:` button below them: Raid, Raid Warning, Party, Guild, Officer, Say, Yell, Only me, or a custom channel).

**Name & Shame** – the hall of shame for the selected fight:
- *Most to blame* – the top of the blame board, with their top two reasons
- *Threat Junkie* – the most aggro pulls (or the highest non-tank threat %)
- *Floor Inspector* – the first person to die, and why
- *Fire Enthusiast* – the most avoidable damage taken, and from what
- *Bomb Squad* – whose bomb/injection hit the most raiders
- *AFK Award* – the lowest activity
- *Participation Trophy* – DPS under half the raid median

**Big Them Up** – the stars of the fight:
- *Damage King* – DPS and % of raid damage
- *Top Healer* – total healing and % of all healing
- *Iron Wall* – the tank who took the most damage and never died
- *Kick Master* / *Cleanser* / *Tranq Sniper* – the most interrupts / dispels / Tranquilizing Shots
- *Never Stops* – the highest activity
- *Flawless* – everyone with no deaths, no avoidable damage, no aggro pulls and no blame

Shift-click a name on the Summary blame board to shame just that player. Shift-click a name in Meters to
big just them up. **Auto shout-outs** (left panel) can post them after every fight. `smart` shames
on wipes and praises on kills. Lines are sent 0.3s apart so chat flood protection doesn't kick in.

## Blame points

| Mistake | Points |
| --- | --- |
| Pulled boss aggro (non-tank) | 4 (+2 if they died) |
| Opened on the boss before the tank | 3 on a wipe (1 on a kill, 0 for hunters) |
| Died to avoidable damage / the environment | 1 + 3 |
| Your bomb/injection hit others | 2 + 1 per victim (+3 per kill) |
| Each separate hit by avoidable damage | 1 (0.5 for spread mechanics, max 6) |
| Too many stacks | 2 |
| Very low activity / low activity | 3 / 1.5 |
| DPS under 40 % of the raid median | 1.5 |
| Dying | 1 (0.25 once the wipe was already happening) |

The wipe point is when 40 % of the raid is dead. Deaths after it barely count.

## Commands

```
/wdi                     open / close
/wdi tank <name>         mark a main tank (or right-click a name in Meters)
/wdi untank <name>
/wdi avoid <spell>       add your own "don't stand in it" spell (exact name)
/wdi report              post the latest fight summary to the shout channel
/wdi shame [name]        Name & Shame (whole raid, or one player)
/wdi bigup [name]        Big Them Up (whole raid, or one player)
/wdi channel <raid|rw|party|guild|officer|say|yell|self|custom name>
/wdi autoshout off|smart|shame|praise|both
/wdi announce self|channel|off   summary after each fight: your chat, the shout channel, or nothing
/wdi trash on|off        also track elite trash pulls
/wdi threat on|off       ask the server for threat when TWThreat isn't loaded
/wdi start | stop        manually track your target / end tracking
/wdi status | clear
```

Tanks are auto-detected (tank-capable classes that held boss aggro for a while), but
setting them with `/wdi tank` makes aggro blame much more accurate.

## Notes

- Spell and boss names are matched in English (enUS client).
- Threat comes from the Turtle server for **your current target**, so keep the boss targeted for threat data.
- Custom Turtle raids (Karazhan, Emerald Sanctum) are detected as world bosses. Their mechanics aren't
  in the database yet. Add avoidable spells with `/wdi avoid`, or edit `Data.lua`.
