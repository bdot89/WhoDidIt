<div align="center">

# WhoDidIt

**Raid wipe & death analyser for World of Warcraft 1.12**
<br>OctoWoW · Turtle WoW · vanilla

Records every boss fight, then tells you **why** the raid wiped and **who** did it.

![WoW 1.12.1](https://img.shields.io/badge/WoW-1.12.1-c79c6e?style=flat-square)
![Lua 5.0](https://img.shields.io/badge/Lua-5.0-2c2d72?style=flat-square)
![Nampower](https://img.shields.io/badge/needs-Nampower-8a2be2?style=flat-square)
![SuperWoW](https://img.shields.io/badge/needs-SuperWoW-1e90ff?style=flat-square)
![TWThreat](https://img.shields.io/badge/optional-TWThreat-555?style=flat-square)

<img src="docs/summary.jpg" alt="WhoDidIt summary: why the raid wiped and the blame board" width="100%">

<sub>Type <code>/wdi</code> in game · click <b>Demo fight</b> to try every feature without raiding</sub>

</div>

---

## Highlights

- 🔍 **Why did it go wrong?** A ranked list of wipe causes: tank deaths, healers out of mana, enrage timers, mechanics, aggro pulls, missed interrupts. Click any cause for the full breakdown: who healed the tank in their last 5 seconds, or each healer's mana and potions.
- ☠️ **Death recaps.** The last 15 seconds before every death (hits, heals, debuffs, items, health %), with the cause worked out for you.
- 🎯 **Aggro & threat.** Every time the boss switched target, with the server's threat % at that moment. Non-tanks who rip aggro get blamed.
- 📋 **Blame board.** Points for standing in fire, pulling aggro, bombing the raid, idling and low DPS, with a "Most to blame" verdict.
- 🦸 **Heroes.** Game-saving plays: clutch heals, shields that ate a killing blow, taunt rescues, Blessing of Protection, battle res, Innervate, dispelled mind control.
- 🧪 **Consumes.** Every player's flask, elixirs, food, juju and protection potions, plus every potion, rune, tea and healthstone they used.
- 📣 **Shout-outs.** *Name & Shame* and *Big Them Up* awards, reports and per-player posts, sent to any channel in colour.
- 📊 **Meters & timeline.** Damage, healing, taken, activity and utility, plus a full timeline of the fight.

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="docs/live.jpg" alt="Live fight"><br><b>Live view.</b> The report builds itself while you fight.</td>
    <td width="50%"><img src="docs/breakdown.jpg" alt="Cause breakdown"><br><b>Cause breakdown.</b> Click any cause. Here: which healers died and when, and each survivor's healing and mana consumables.</td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/deaths.jpg" alt="Deaths"><br><b>Deaths.</b> Every death with its cause and killing blow. Deaths after the wipe point are greyed out.</td>
    <td width="50%"><img src="docs/death.jpg" alt="Death recap"><br><b>Death recap.</b> Click a death for its last seconds: every hit, heal and crushing blow, with a health bar.</td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/mistakes.jpg" alt="Mistakes"><br><b>Mistakes.</b> Every mistake with its time and blame points, worst first.</td>
    <td width="50%"><img src="docs/threat.jpg" alt="Threat"><br><b>Threat.</b> Who the boss attacked and why (tank swap, pulled aggro, opened early), plus peak threat per player.</td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/meters.jpg" alt="Meters"><br><b>Meters.</b> Damage, healing, taken, activity and utility, with roles marked.</td>
    <td width="50%"><img src="docs/timeline.jpg" alt="Timeline"><br><b>Timeline.</b> Everything that happened in the fight, in order.</td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/consumes.jpg" alt="Consumes"><br><b>Consumes.</b> Flask / food overview, then each player's buffs and items used, colour-coded by type.</td>
    <td width="50%"><img src="docs/chat.jpg" alt="Coloured chat posts"><br><b>Coloured chat posts.</b> A Report and a Consumes post: names in class colour, times in blue, numbers in white. Long lines split instead of losing their colours.</td>
  </tr>
</table>

## Install

1. Download the [latest code](https://github.com/bdot89/WhoDidIt/archive/refs/heads/main.zip) (or `git clone`).
2. Extract it into `Interface/AddOns/` and **rename the folder to `WhoDidIt`**. GitHub names it `WhoDidIt-main`, and the game won't load it under that name.
3. Make sure **Nampower** and **SuperWoW** are installed (see below), then log in and type `/wdi`.

### Requirements

| Mod | What WhoDidIt uses it for |
| --- | --- |
| **Nampower** (dll) | Damage, healing, swings, buffs/debuffs, deaths and consumables. Without it, only deaths are tracked. |
| **SuperWoW** (dll) | Player and mob names from GUIDs, who the boss is targeting, cast events (interrupts, activity, tranqs, saves). |
| TWThreat (addon, optional) | If it's loaded, WhoDidIt reads the same server threat packets. If not, WhoDidIt asks the server itself (`/wdi threat off` to stop). |

WhoDidIt switches on the Nampower CVars it needs (`NP_EnableAutoAttackEvents`, `NP_EnableSpellHealEvents`, `NP_EnableSpellGoEvents`).

## Quick start

1. Type **`/wdi`** and click **Demo fight** (bottom-left). Two sample fights load, a messy wipe and a cleaner kill, and every tab has something to show. **Shift-click** it to watch the wipe play out live at 4× speed.
2. Mark your main tanks: **`/wdi tank <name>`**, or right-click a name in the window. Tanks are auto-detected, but setting them makes aggro blame much more accurate.
3. Pick where posts go with the **To:** button (top-right): Raid, Raid Warning, Party, Guild, Officer, Say, Yell, Only me, or a custom channel (`/wdi channel <name>`).
4. Raid. Fights are recorded automatically when your group engages a boss. **Keep the boss targeted** so threat % gets recorded.

## The window

| Tab | What it shows |
| --- | --- |
| **Summary** | The verdict, the ranked wipe causes (click for details), the blame board, the top heroes and raid notes (missing buffs, boss debuff uptime) |
| **Deaths** | Every death with its cause. Hover for the recap, click for the second-by-second timeline with health bars |
| **Mistakes** | Every finding with its time and blame points |
| **Heroes** | The hero board and every game-saving moment |
| **Threat** | Boss target changes with threat % and a verdict, plus peak threat per player |
| **Meters** | Damage, Healing, Taken, Activity, Utility (interrupts, dispels, tranqs, items) |
| **Timeline** | Everything that happened, in order |
| **Consumes** | Raid flask/food overview, then each player's buffs and items used. **Post summary / missing / everyone** buttons |

### Clicking names

Every player name in the window (blame board, Heroes, Meters, Consumes) works the same way:

| Click | Does |
| --- | --- |
| **Click** | Post that player's overview for the current tab (blame, hero plays, stats or consumes) to your channel |
| **Ctrl-click** | Preview that post in your own chat only |
| **Shift-click** | Name & Shame just them |
| **Alt-click** | Big them up |
| **Right-click** | Mark / unmark as a tank |

## Rankings

The **Rankings** button (title bar, or `/wdi rankings`) shows kill times and full clears for every raid:

- **Kill times:** your personal best, your guild's best and rank, and the fastest guild on the realm for every boss. Click a boss for its full leaderboard.
- **Full clears:** first combat inside the instance to the last required boss, all in one run. Optional bosses (ZG's Edge of Madness, AQ40's Bug Trio / Viscidus / Ouro) aren't required. A run in progress shows which bosses are down.
- **Closest to you first:** it opens on your current instance, realm and faction, with your own and your guild's times pinned at the top. **Realm** and **Faction** switch the view.
- **Every guild on your realm:** each guild's best times are shared with other WhoDidIt users over a hidden realm channel (`WDIBoard`). So the board fills up with every guild that has at least one WhoDidIt user. **Sharing** turns it off (`/wdi share off`). Shared times are self-reported: they're sanity-checked but can't be verified.

A kill or clear counts for the raid's majority guild (at least half the raid). Personal bests are kept per character.

**Realm** cycles your realm → **All realms** (every guild on the server ranked together, with realm names) → each
other realm. Every leaderboard time is compared with your guild's ("1:38.6 faster" / "3:51.1 slower"). The left column
shows your guild's clear, its rank (gold / silver / bronze) and a green bar for how close you are to #1.

### Banter

After every boss kill and full clear, WhoDidIt posts a fun line to your shout channel. It compares the time with your
guild's previous best and with the other guilds on the realm, then picks a random message type so it doesn't get
repetitive:
- new guild best (and by how much)
- slower than our best ("…{d} of sightseeing")
- beat another guild ("Sorry not sorry, Care Bears")
- behind the guild just ahead
- #1 on the realm
- our rank

It trolls you when you're slow and bigs you up when you're fast. Toggle it with **Kill banter / Clear banter** in
Rankings or `/wdi banter kills|clears on|off`, and preview a line with **Test banter** or `/wdi banter test`.

### Every guild's times from Chronicle (optional helper)

WoW addons can't go online, so a small helper does it for them. `tools\WhoDidIt-Sync.cmd` (PowerShell, built into
Windows) uses Chronicle's public [External API](https://legacy.chronicleclassic.com/developers/api) to pull:

- **full clears** from Chronicle's speedrun leaderboards
- **boss kill times** from every uploaded raid log on your server (OctoWoW: C'Thun, N'Zoth, Y'Shaarj)

It writes them to `CustomData\WhoDidIt_Chronicle.txt`, and WhoDidIt reads that file live through Nampower, with no
`/reload`. Rankings then shows every guild's Chronicle times next to the WhoDidIt-shared ones (hover a row to see its
source), plus Turtle's custom bosses and the Karazhan towers.

```
tools\WhoDidIt-Sync.cmd                    sync now, then every 10 minutes (close the window to stop)
tools\WhoDidIt-Sync.cmd -Once              sync once and exit
tools\WhoDidIt-Sync.cmd -Days 30           only raids from the last 30 days (default 90)
tools\WhoDidIt-Sync.cmd -Server "Kronos"   another Chronicle server
```

- **First sync:** reads every raid log from the last 90 days once, about 45 minutes for OctoWoW. Data appears in game as it goes.
- **Later syncs:** only fetch new uploads.
- **Rate limit:** the helper stays within Chronicle's limit (about one request a second) and caches what it has read in `CustomData\WhoDidIt_ChronicleCache.json`.
- **Faction:** comes from the raiders' races. OctoWoW raids cross-faction, so many guilds show as **M** (mixed).

The API is marked experimental by Chronicle, so it may change.

## Chronicle logs

The **Logs** button (or `/wdi logs`) controls the [ChronicleCompanion](https://chronicleclassic.com) addon, which writes the combat logs you upload to chronicleclassic.com:

- **Start logging / Stop & save**, **Save now**, **Archive log** (between lockouts) and **Delete log**
- Chronicle's auto-logging settings (raids, dungeons, save after combat, one file per realm)
- WhoDidIt extras: **start logging when a boss is pulled** and **save after every boss fight**
- Live status: logging on/off, the log file, unsaved lines, and what was saved this session
- Step-by-step upload instructions. The upload itself is done on the website.

## Shout-outs

<table>
<tr>
<td width="50%" valign="top">

**🔴 Name & Shame**

- *Most to blame*: the top of the blame board
- *Threat Junkie*: the most aggro pulls
- *Floor Inspector*: the first to die, and why
- *Fire Enthusiast*: the most avoidable damage taken
- *Bomb Squad*: whose bomb hit the most raiders
- *AFK Award*: the lowest activity
- *Participation Trophy*: DPS under half the raid median

</td>
<td width="50%" valign="top">

**🟢 Big Them Up**

- *Lifesaver*: the top hero and their best save
- *Damage King*: top DPS and % of raid damage
- *Top Healer*: top healing and % of all healing
- *Iron Wall*: the tank who never went down
- *Kick Master / Cleanser / Tranq Sniper*
- *Never Stops*: the highest activity
- *Flawless*: everyone who made zero mistakes

</td>
</tr>
</table>

**Auto shout-outs** (left panel) can post them after every fight. `smart` shames on wipes and praises on kills. Lines are sent 0.3 s apart so chat flood protection doesn't kick in.

### Chat colours

Every post (Report, shout-outs, Consumes, Heroes, per-player posts) uses the same scheme:

| Part | Colour |
| --- | --- |
| `[WhoDidIt]` tag | red |
| Post kind (`REPORT`, `BIG UPS`, …) and line labels (`Verdict:`, `Blame:`, `Flasks:`) | gold |
| Player names | their class colour |
| Times | light blue |
| Numbers and % | white |
| WIPE / KILL | red / green |

If your server doesn't allow coloured chat, WhoDidIt notices and switches to plain text (`/wdi colors on|off`).

## How the verdict works

<details>
<summary><b>Blame points</b></summary>

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

</details>

<details>
<summary><b>Hero points</b></summary>

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

</details>

<details>
<summary><b>What gets detected</b></summary>

- **Deaths:** stood in avoidable damage, killed by a bomb/injection carrier, meleed to death after pulling aggro, tank deaths (no heals / crushing blows / damage vs healing), mind control, falling / lava, or plain "overwhelmed".
- **Mechanics:** avoidable damage (Void Zone, Shadow Fissure, Heigan's dance, Chromaggus breaths…), carriers splashing the raid (Living Bomb, Detonate Mana, Mutating Injection) and stacking marks (Four Horsemen, Firemaw). Covers MC, Onyxia, BWL, ZG, AQ20, AQ40 and Naxxramas.
- **Raid-wide failures:** uninterrupted heals and Frostbolts, slow decurses/dispels, Frenzy not tranquilized, Magma Blast / Ball Lightning (nobody in melee range), enrage timers, healers out of mana.
- **Playing badly:** idle time while alive, DPS far below the raid median, early pulls, near-aggro threat peaks.
- **At the pull:** missing Fortitude / Mark of the Wild / Arcane Intellect and flasks. Boss debuff uptimes (Sunder Armor, curses, Faerie Fire…).

</details>

## Commands

<details>
<summary><b>All slash commands</b> (<code>/wdi</code> or <code>/whodidit</code>)</summary>

```
/wdi                       open / close the window
/wdi rankings              kill times & full clears
/wdi share on|off          share your guild's times with WhoDidIt users on the realm
/wdi logs                  Chronicle log controls
/wdi log start|stop|save   control Chronicle logging
/wdi demo                  add two sample fights (a wipe and a kill)
/wdi demo live             watch the wipe play out live at 4x speed
/wdi demo clear            remove demo fights
/wdi tank <name>           mark a main tank (or right-click a name)
/wdi untank <name>
/wdi tanks                 list tanks
/wdi avoid <spell>         add your own "don't stand in it" spell (exact name)
/wdi unavoid <spell> | avoids
/wdi report                post the latest fight summary to the shout channel
/wdi shame [name]          Name & Shame (whole raid, or one player)
/wdi bigup [name]          Big Them Up (whole raid, or one player)
/wdi channel <raid|rw|party|guild|officer|say|yell|self|custom name>
/wdi autoshout off|smart|shame|praise|both
/wdi announce self|channel|off   summary after each fight
/wdi colors on|off         coloured chat posts
/wdi trash on|off          also track elite trash pulls
/wdi threat on|off         ask the server for threat when TWThreat isn't loaded
/wdi start | stop          manually track your target / end tracking
/wdi status | clear
```

</details>

## Demo mode

**Demo fight** adds two scripted fights against a *Grand Demonstrator* with a fake 20-player raid. They go through the real analyser, so they show exactly what a real fight would:

- **Wipe:**
  - a rogue opens before the tank, and a mage rips aggro at 112% and gets flattened
  - a Living Bomb carrier kills a healer, and players die in Void Zone and Rain of Fire
  - a mind-controlled priest kills a shaman
  - Dark Mending goes uninterrupted, Frenzy isn't tranqed, and decurses are slow
  - a tank dies with no heals, healers run out of mana, and the boss enrages
  - one mage is AFK
  - the heroes save the day where they can
- **Kill:** a cleaner fight with a single death, good interrupts, fast tranqs and a battle res.

Demo fights are labelled *(demo)*. Automatic post-fight messages for them stay in your own chat. Clicking a post button sends it for real, tagged `DEMO`.

## Notes

- Spell and boss names are matched in English (enUS client).
- Threat comes from the Turtle server for **your current target**, so keep the boss targeted.
- Turtle's custom raids (Karazhan, Emerald Sanctum) are detected as world bosses, but their mechanics aren't in the database yet. Add avoidable spells with `/wdi avoid <spell>`, or edit [`Data.lua`](Data.lua). Pull requests with mechanics are welcome!
- Weapon oils and sharpening stones can't be seen on other players in the 1.12 client, so they don't show on the Consumes tab.
