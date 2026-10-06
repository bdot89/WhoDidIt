# DopingControl

A raid consumables, class buff, debuff, resistance, hit and enchant checker for
**TurtleWoW / WoW 1.12.1 (Vanilla)**.

One window that answers, before the pull: who has their flask and elixirs up, who is missing
which class buff, who is carrying which debuff, who is short of the hit cap, and whose gear
went into the raid unenchanted.
Its defining trait is **honesty about what it cannot see** — a player the addon cannot read is
shown as *unknown* and is **never counted as missing**, anywhere. Requires
[SuperWoW](https://github.com/balakethelock/SuperWoW) for full raid reads; degrades gracefully
without it.

<img src="screenshots/testmode.png" alt="The full readiness matrix on a simulated raid" width="100%">

*The full readiness matrix (shown here in test mode on a simulated raid): buff icons
in the cells, ready pills per role group, gaps first, unreadable players marked instead of
blamed.*

## What's new — v0.6.4 · 2026-08-30

- **The belt is checked.** The waist slot was never scanned (v0.6.2), is expected equipment
  for every role by default (v0.6.3), and a profile saved before the column existed picks it up
  on the next refresh instead of only at login (v0.6.4).

**Version history** — details in [CHANGELOG.md](CHANGELOG.md):

- **v0.6.4** — the equipment expectation top-up self-heals on every refresh, so a profile
  saved before the waist column existed picks it up without a relogin.
- **v0.6.3** — the waist slot is expected equipment by default for every role.
- **v0.6.2** — fix: the waist slot was never scanned, so a missing belt could not be reported.
- **v0.6.1** — fixes: other players' resistances are reconstructed from their gear (the tab
  showed `?` for everyone but you), the weapon column can report a missing imbue again, six
  consumables whose aura name differs from the item name are matched, "gaps only" no longer
  empties Hit and Resistances, and the coverage number belongs to the tab it is shown on.
- **v0.6.0** — the **Hit tab** (melee, ranged, per-school), hit assembled from items, set
  bonuses, auras, talents and weapon skill with the tooltip showing the addition line by line;
  other players' talents read over this server's inspect protocol; the **Skill books** options
  tab; alternating row shading; scrolling fixed once every group is expanded.
- **v0.5.2** — the **Resistances tab**; equipment semantics finalized (empty slots always count,
  the grid governs enchants only, neck/rings enchantable on this server).
- **v0.5.1** — the Equipment tab covers all sixteen slots.
- **v0.5.0** — first public release.

## Screenshots

<table>
  <tr>
    <td align="center" width="33%">
      <a href="screenshots/classbuffs.png"><img src="screenshots/classbuffs.png" width="260" alt="Class buffs tab"></a><br>
      <sub><b>Class buffs</b> — six slots, the buffer's duty</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshots/debuffs.png"><img src="screenshots/debuffs.png" width="260" alt="Debuffs tab"></a><br>
      <sub><b>Debuffs</b> — columns only for what is present</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshots/resistances.png"><img src="screenshots/resistances.png" width="260" alt="Resistances tab"></a><br>
      <sub><b>Resistances</b> — totals + raid average</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="33%">
      <a href="screenshots/hit.png"><img src="screenshots/hit.png" width="260" alt="Hit tab"></a><br>
      <sub><b>Hit</b> — melee, ranged and one column per school</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshots/hit-tooltip.png"><img src="screenshots/hit-tooltip.png" width="260" alt="Hit breakdown tooltip"></a><br>
      <sub><b>Hit breakdown</b> — every source on its own line</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshots/equipment.png"><img src="screenshots/equipment.png" width="260" alt="Equipment tab"></a><br>
      <sub><b>Equipment</b> — item tiles, enchant corner markers</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="33%">
      <a href="screenshots/options.png"><img src="screenshots/options.png" width="260" alt="Options panel"></a><br>
      <sub><b>Options</b> — expectations per role and class</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshots/skillbooks.png"><img src="screenshots/skillbooks.png" width="260" alt="Skill books options tab"></a><br>
      <sub><b>Skill books</b> — one column per weapon skill</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshots/hit-tooltip-school.png"><img src="screenshots/hit-tooltip-school.png" width="260" alt="School hit tooltip"></a><br>
      <sub><b>School columns</b> — what only that school gets</sub>
    </td>
  </tr>
</table>

*(Click any thumbnail for full size.)*

## The six tabs

**Consumables** — eleven slots per player: Flask, Food buff, Attack power, Strength, Agility,
Spell power, Mana regen, Armor, Stamina, **Fire protection**, and the temporary weapon buff
(oils / stones). Cells show the **actual buff icon** the player has, not just a checkmark — a
Flask of the Titans and a lesser protection potion look different because they are different.

**Class buffs** — the six raid buffs: Arcane Intellect, Mark of the Wild, Power Word:
Fortitude, Shadow Protection, Emerald Blessing, Soulstone. Emerald Blessing ships with **no**
expectation default — it is a raid quest reward almost nobody carries — so its column stays
hidden until you enable it per role and class, while its +1% spell hit still counts on the Hit
tab. This tab deliberately has **no whisper button**: a
missing class buff is the *buffer's* duty to fix, and whispering the unbuffed player would nag
the wrong person.

**Debuffs** — a warning signal rather than a checklist. Columns are **built dynamically** from
what is actually on the raid: a debuff that nobody has gets no column, and a raid with no
debuffs shows none. The sum column carries the count per player, and clean players stay quiet —
no green wall of "nothing wrong here".

**Resistances** — a display-only tab: five fire/nature/frost/shadow/arcane columns showing each
player's current total, no gaps, no expectation checkboxes, no whisper button. The footer shows
the raid average across readable players only. The client is never told another player's
resistances, so for everyone but yourself the total is **reconstructed from their equipped
items** plus the racial bonus (Dwarf frost, Gnome arcane, Night Elf and Tauren nature, Undead
shadow). That makes it a near-range reading: a raid member the client has not loaded shows `?`,
never a made-up number.

**Equipment** — sixteen slots. Eleven armor slots (head, shoulders, back, chest, wrist, hands,
legs, feet, main hand, off hand, ranged) are enchant slots, checked present/missing with a
corner marker for the enchant state. Neck and both rings can be enchanted on this server (a
custom feature beyond vanilla WoW) and join the same enchant logic — the expectation defaults to
off, so enable it per role/class in the options grid where it matters. Both trinkets are item
tiles instead: the equipped item is shown regardless of any expectation. Empty slots count as a gap everywhere on this tab **except
the two that may legitimately be empty**: an empty off hand (you carry a two-hander) and an
empty ranged slot have nothing to enchant and are marked *not expected* instead. The
expectation grid only governs whether the *enchant* question is tracked. Slots where no enchant exists for that item or class are marked
*not expected* rather than red. Hovering a tile shows the **native item tooltip**, so you see
the exact enchant — not merely that one is present.

**Hit** — melee, ranged and one column **per spell school**, because talents and items raise
schools individually: one "spell hit" number would be wrong for most casters. There is no hit
API in 1.12, so the number is assembled from the equipped items' tooltips, set bonuses, hit
auras, talents and weapon skill. The cell tooltip shows that as a plain **addition** — one row
per source, values in a right-aligned column, so the total can be checked by adding it up. A
source that contributes nothing is still listed at `+0.0%`; a source that could not be *read*
shows `?`, never a zero. The boss's requirement is one flat number (8% melee at 300 weapon
skill, 27% for dual-wield white swings, 16% spell) and does not move with your weapon skill —
skill counts on the player's side, where it belongs. Cells at or above the cap turn green.

Two things about that number are worth stating plainly:

- **Set bonuses count once per set**, not once per piece, and only when their piece threshold
  is met. Their tooltip line is printed on every piece of the set, which is why a naive per-item
  sum would multiply them.
- **Talents of other players are read**, over the inspect protocol this server ships — one
  addon message per player, paced and repeated at most once per half hour, and switchable off
  with `/dc talents off`. Until an answer arrives, the talent row shows `?` and the total says
  it will rise.

A quest weapon-skill book (+3 skill, about 0.6% hit) is the one input that **cannot** be read
off another player — no channel reports foreign weapon skills. It is ticked by hand in the
**Skill books** options tab: one row per scanned player, one column per weapon skill.

## Honest by design

The addon distinguishes three data states — **HAS**, **MISSING** and **UNKNOWN** — plus a
fourth, display-only one: *not expected*, for a slot the player is not asked to fill.

- **UNKNOWN is never counted as MISSING** — not in cells, not in sums, not in ready pills, not
  in reports. A player the addon cannot read produces no accusation.
- A **coverage pill** in the titlebar shows how much of the raid is actually readable right now,
  so you know how much the numbers are worth before you act on them.
- **Last-known display:** when a previously scanned player becomes unreadable, their stale data
  is still shown — half-transparent, with its age. This is display-only; a stale cell still
  *counts* as UNKNOWN everywhere.

A wrong number on a raid-readiness check is worse than no number. The addon would rather say
"I don't know" than guess.

## Roles and expectations

Players are grouped into five roles — **Tanks / Melee / Ranged / Casters / Healers** — because a
healer without a Mongoose elixir is not a problem and a tank without armor elixirs is.

- Roles are **auto-suggested** with a stated reason (visible on the badge's tooltip).
- **Left-click** a role badge to confirm the suggestion; **right-click** cycles through the
  roles plausible for that class. Confirmed roles are saved per character name.
- An **unassigned counter** in the titlebar shows how many players still run on suggestions.

What each role is expected to bring is fully configurable — as a **role × class grid** in the
options panel, since a caster's "spell power" means something different for a mage than for a
shadow priest. Every role is configurable per performing class, and each role row has a bulk
toggle to switch a whole expectation on or off at once.

## Actions

- **Per-player whisper button** — tells a player exactly what they are missing on the current
  tab. 30-second cooldown per player, and offered only for *readable* players with actual gaps;
  the addon never whispers anyone based on data it does not have. On the **Hit** tab it carries
  both numbers (`Melee hit 5.0/8.0`) and only mentions the columns that role is asked about — a
  melee player is never told about his shadow hit, and healers are never whispered at all
  (heals cannot miss).
- **Raid report with preview** — composes a summary for raid chat and shows it to you first.
  **Nothing is ever sent without an explicit click.**
- **Scanning** — on demand (`/dc scan` or the toolbar button), automatically when the window
  opens if there is no scan yet or the last one is over a minute old (never in test mode), and
  automatically on a ready check. The two ready-check reactions — scan, and open the window —
  can be switched off separately; the window-open scan is not optional.

## Test mode

`/dc test` swaps the live group for a **deterministic simulated 40-player raid** — same roster,
same gaps, every time. The full UI (all six tabs, roles, pills, report preview) can be
inspected and configured without being in a group, and all chat output is disabled while test
mode is on, so nothing simulated can ever reach another player.

## Demo mode

`/dc demo` (or the button in the options panel) shows the same simulated raid, but with **all
six school protection columns at once** — fire, frost, nature, shadow, holy and arcane — even
though five of them are switched off by default. It is a viewing mode, nothing else: your saved
expectations are never modified, and the mode itself is not saved either, so a reload ends it.

## Install

**Option A — download (simplest):**

1. Grab **`DopingControl-vX.Y.Z.zip`** from
   [**Releases**](https://github.com/ShempError/DopingControl/releases).
   *(Use the Release zip, not "Code → Download ZIP" — that names the folder
   `DopingControl-main`, which WoW won't load.)*
2. Extract the **`DopingControl`** folder into `Interface\AddOns\`.
3. Restart the client.

**Option B — git (auto-updatable):**

```
cd Interface/AddOns
git clone https://github.com/ShempError/DopingControl.git DopingControl
```

`main` is the stable release channel — git-based addon managers stay current with a
`git pull`.

## Usage

| Command | Does |
| --- | --- |
| `/dc` or `/doping` | toggles the main window |
| `/dc scan` | scans the group now |
| `/dc options` | opens the options panel (also: right-click the minimap button) |
| `/dc report` | opens the raid report preview |
| `/dc test` | toggles test mode (simulated 40-player raid, chat output disabled) |
| `/dc demo` | toggles demo mode (the simulated raid with all six protection columns shown; your expectations stay untouched, the mode is not saved) |
| `/dc probe [range <name>]` | dumps raw scan-API returns to a file for debugging data-source gaps (SuperWoW required) |
| `/dc talents [on\|off\|clear]` | shows how many players' talents are in, or stops asking for them |
| `/dc unknown` | lists buff names the scanner saw but could not classify — useful for reporting gaps in the data tables |

The minimap button toggles the window on left-click, opens options on right-click, and can be
dragged to reposition.

## Requirements

- A **TurtleWoW** client (WoW 1.12.1) with
  **[SuperWoW](https://github.com/balakethelock/SuperWoW)** — used for buff *identity* (knowing
  which buff a cell shows, not just its icon) and for reading other players' equipment.
- Optional: **UnitXP_SP3** — distance diagnostics; flags players out of scan range. Distance
  never changes any cell state or sum.
- Optional: **nampower** — when present, its aura descriptor supplies the spell **IDs** of other
  players' buffs and debuffs, which the tooltip path does not deliver on this client; both
  sources are merged. Without it, buff identity rests on names alone.

**Degrades gracefully:** without SuperWoW, cells for other players show *not readable* instead
of a guess, and the coverage pill tells you so. Your own character remains fully readable
either way.

## Licence

MIT.
