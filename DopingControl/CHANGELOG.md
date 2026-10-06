# Changelog

All notable changes to DopingControl. Versions are the ones actually
released here — a new feature raises the middle number and resets the last
one, the last number is for fixes without new features.

## Unreleased

## v0.6.4

### Equipment expectation top-up now self-heals every refresh, not just once at ADDON_LOADED

Field report after v0.6.3 shipped (WAIST seeded `true` for every role):
after deploying and reloading, the Equipment matrix still showed 16
columns (no WAI) and the owner's own row read "(read failed)" / sum "--".

Offline reproduction against the real captured dump
(`dc_raid_1788070493.txt`, the scan taken right after the reload) and the
real live `db.expectations` shape
(`WTF\...\SavedVariables\DopingControl.lua`, all 20 role/class lines —
`NECK`/`R1`/`R2 = true`, `WAIST` absent everywhere) through the actual
`DC_Gear.Assemble` -> `DC_Model.build` -> `DC_Matrix` pipeline found no
Lua error anywhere — no nil dereference, nothing caught by a `pcall`.
Both symptoms are real, and neither is what it first looked like:

* The "(read failed)"/"--" row is a correct, unrelated read: the dump's
  own `P`/`H`/`X` lines already carry `aurasRead=0`/
  `unreadableReason=read failed` before any render happens —
  `scan/aura.lua`'s "zero USABLE auras this scan => aurasRead=false" rule
  firing on a genuine zero-buff moment. Nothing to do with WAIST or
  equipment.
* The missing WAIST column traces to `core/model.lua`'s `anyClassExpects`:
  it only falls back to the `DC.DEFAULT_EXPECT` seed for a (role, class)
  combo with NO saved line at all — an *existing* class line (any line
  materialized before the v0.6.3 seed change) is trusted as complete, key
  by key. `DC.EnsureExpectations`/`topUpLine` (`core/config.lua`) are
  themselves correct — proven by running them against the exact real
  saved shape above — but they only ran once, at `ADDON_LOADED`. A
  `db.expectations` line materialized before v0.6.3 shipped therefore
  stayed short the new key until a SECOND full reload happened to run
  `EnsureExpectations` again against the current seed.

Fix: `ui/matrix.lua`'s `MX.ExpectTable` — the one resolver both the header
and `MX.Refresh` read the expectation table from — now defensively re-runs
`DC.EnsureExpectations(d)` every time it resolves, i.e. on every
scan/window redraw, not only once at boot. `topUpLine` only ever fills
`nil` keys, so this is idempotent and side-effect-free on an
already-current table; it self-heals a stale class line the moment the
window redraws, without requiring a second reload.

New regression test `tools/luatests/test_expectations_topup.lua`: embeds
the real captured `db.expectations` shape (all 20 role/class lines,
verbatim) and a real gear/hit dump line, reproduces the exact
16-column/no-WAI/`(read failed)` symptom through the unmodified
`DC_Model.build`, then proves `MX.ExpectTable` self-heals it to 17 columns
with WAIST at column 6.

## v0.6.3

### Waist is expected by default for every role

Owner decision, reversing the "confirmed, not a bug" call below: every role
wears an enchantable belt, so WAIST now belongs with the other worn
equipment slots (HEAD, CHST, WRST, ...) instead of the opt-in neck/ring
treatment. `data/expectations.lua`'s seed now carries `WAIST = true` for
all five roles. Existing SavedVariables pick up the flag automatically —
`core/config.lua`'s `topUpLine` already adds any seed slot the saved line
has never seen (`nil`) as `true` on load, the same mechanism that
delivered the neck/ring columns to existing saves; no separate migration
was needed. An explicit `WAIST = false` set for a role/class still hides
the column, same opt-out behavior as any other slot.

### Confirmed: the waist column's off-by-default is intended, not a bug

A field report said the belt was worn but the Equipment tab still showed
16 columns, no WAI, after the v0.6.2 waist-slot fix was deployed and the
UI reloaded. Traced end to end (`core/model.lua` `tabSlots`/
`anyClassExpects`, `ui/matrix.lua`'s `vm.slots` column build, the live
SavedVariables `expectations` table): the gating is working exactly as
v0.6.2 shipped and tested it — the waist enchant column is opt-in per
role/class, the same treatment as neck/rings, and simply had not been
enabled for any role/class yet (unlike neck/rings, which already carry
`= true` in every class line of the reporting player's save from before
this default existed). No code was hiding anything; the column appears
the moment the checkbox is enabled in Options > Equipment.

Added a regression test (`tools/luatests/test_model.lua`, section 8d)
that exercises the real production path — `core/model.lua`'s `M.build`
through `tabSlots`/`anyClassExpects`, the same function `ui/matrix.lua`
renders from — instead of the static `DC.SLOTS_EQUIPMENT` array the
layout test uses. It pins both halves: WAIST absent from `vm.slots`
under the default seed, and present + classifying correctly (HAS/
MISSING/UNKNOWN) once a role/class expectation is switched on. This
closes the gap that let the "is it really gated correctly" question go
unanswered by the existing suite.

## v0.6.2

A fix release.

### The waist slot was never scanned

No equipment read — the raid dump, the Equipment tab, the Hit tab's
belt contribution — ever covered the waist (inventory slot 6). The slot
list that drives every `GetInventoryItemLink` read was borrowed from the
Equipment tab's enchant-tracking column list, which had no waist column;
that list never included the waist at all, so it was silently skipped in
every read that reused it, not only display.

The waist turns out to be enchantable on this server (a custom "Belt
Buckle" item line, the same kind of addition that already made the neck
and both rings enchantable beyond stock behaviour), so it now gets its
own Equipment-tab column — off by default, like the neck and ring
columns, until enabled per role/class in the options grid.

## v0.6.1

A fix release. Everything here is something that was supposed to work
already — most of it found by running the addon in a real 26-man raid and
then checking what it had actually read.

### Resistances of other players are readable at last

The Resistances tab shipped in v0.6.0 and showed `?` for everyone but you.
That was not a display bug: this client is never told other players'
resistances. Both read paths return `0` for a raid member standing next to
you, fully loaded — including their armour value, which is the giveaway
that the field is simply not transmitted rather than genuinely zero.

The numbers are now **reconstructed from the equipped items' tooltips** —
the same route the Hit tab already takes — and `Equip: +N All Resistances`
counts on all five schools. On top of that comes the **racial bonus**,
which is written in no item: Dwarf +10 Frost, Gnome +10 Arcane, Night Elf
and Tauren +10 Nature, Undead +10 Shadow. Goblin and High Elf get nothing
added, because no resistance racial for them could be confirmed — an
invented bonus would be worse than a missing one.

This stays a near-range reading. A raid member the client has not loaded
has no readable equipment at all, and their column stays `?`.

### The weapon-buff column could never report a missing buff

For another player, the client returns *nothing* for the weapon
enchantment when there is no imbue — not an empty string, as the code
expected. So everyone without a weapon buff was shown as `?` instead of as
a gap, and was left out of the gap count, the footer and the whisper.
Measured in a 26-man raid: **14 of 25** players were mislabelled that way —
precisely the case a buff checker exists to report.

The fix distinguishes by readability: if the main hand can be read and
there is no imbue, that is a gap. If the player cannot be read, it stays
unknown. Unknown is still never silently turned into missing.

### Consumables that were being discarded

Six buffs were tracked in the tables but never recognised, because the
aura carries a different name than the item: **Elixir of the Giants**,
**Elixir of Greater Agility**, **Elixir of Fortitude**, **Strike of the
Scorpok**, **Rage of Ages** and **Elixir of Greater Frost Power**. In one
raid, `Elixir of the Giants` alone was thrown away 38 times.

Aura names also arrive from the client with trailing spaces on occasion,
which defeated the name match; they are trimmed now.

### "Gaps only" no longer empties Hit and Resistances

Those two tabs are numeric — no cell there can be *missing*, so the filter
hid every row. It now also counts the unknown cells, which is what there is
to see on those tabs.

### The coverage number belongs to the tab it is shown on

The pill counted the players whose **auras** could be read — and showed
that number on every tab. Auras are readable raid-wide, equipment and hit
only nearby, resistances only for yourself. In the same raid the pill
claimed `26/26` while the Hit tab really knew 15 of 26 and the Resistances
tab 1 of 26.

Each tab now reports its own reading, and says which one it is:
`26/26 readable` on the aura tabs, `15/26 gear read`, `15/26 hit read`,
`1/26 resist read`. The report line in chat carries the same number. As a
side effect the word "readable" now means one thing instead of two.

## v0.6.0

### Hit

A new **Hit** tab, and with it the addon's second numeric tab after
Resistances. Eight columns: melee, ranged, and one per spell school —
because talents and items raise schools individually, so one "spell hit"
number would be wrong for most casters.

There is **no hit API in 1.12**. The number is assembled from what can
actually be read:

- **items** — parsed out of the equipped items' tooltips
- **set bonuses** — counted **once per set**, only when the piece
  threshold is met (the bonus line is printed on every piece of the set,
  so adding it per item would multiply it)
- **hit auras** — buffs that grant hit
- **talents** — for your own character, and for other players over the
  inspect protocol this server ships (see below)
- **weapon skill** — every point above 300 is worth 0.2% hit against a
  +3-level boss

The cell tooltip shows that as a plain **addition**: one row per source,
values in a right-aligned column, so the total can be checked by adding it
up. Sources that contribute nothing are still listed at `+0.0%` — a missing
row would look like a forgotten source. A source that could not be **read**
shows `?`, never `+0.0%`: unknown is not zero.

The boss's requirement is stated as one flat number (`Cap vs a +3-level
boss`). It does not move with your weapon skill — skill counts on the
player's side of the comparison, where it belongs.

Caps: melee 8% at 300 weapon skill, dual-wield white swings 27%, spell 16%.
A cell at or above its cap is marked green.

### Reading other players' talents

Talents raise hit by up to several percent, so a hit number without them is
systematically low. WoW 1.12 has no foreign-talent channel and this server
transmits none either — but it ships **its own inspect protocol**, a plain
addon-message conversation: we ask by name, the target's client answers with
its talent tree.

DopingControl uses exactly that, for the players the scan already shows.
One request per player, at most one every five seconds, and each name at
most once per half hour. It can be switched off entirely with
`/dc talents off`.

### Weapon skill books

A quest weapon-skill book grants +3 skill — about 0.6% hit — and **cannot be
detected on another player**: no channel reports foreign weapon skills. So
it is entered by hand, in a new **Skill books** options tab: a grid with one
row per scanned player and one column per weapon skill, with a checkbox
wherever that class could own a book for it.

### Whisper on the Hit tab

The hit tab now offers the per-player whisper button, unlike the other
display tab: being short of the hit cap is something that player can fix,
a resistance total is not. The whisper carries both numbers —
`Melee hit 5.0/8.0` — so the reader knows the distance, not just the fact.

It only ever mentions the columns that **role** is asked about: a melee
player is never told about his shadow hit, and healers are never whispered
at all (heals cannot miss). Every column stays visible with its own cap
marking on the tab — the display hides nothing, only the whisper is
selective.

### Class buffs

A sixth slot: **Emerald Blessing**. It ships with no expectation default —
it is a raid quest reward almost nobody carries — so its column stays
hidden until you enable it per role and class. Its +1% spell hit counts on
the Hit tab either way.

### Tables

- **Alternating row shading** in every table (main window, both options
  grids), so a row can be followed across a wide grid.
- The **options window width follows the selected tab** instead of being
  fixed to the widest one.
- The options column headers now use the **same header tiles as the main
  window** — three-letter label over a sub-line, in a bordered strip.

### Fixed

- **Could not scroll to the bottom** of the main window once every role
  group was expanded. The content height was right; the scrollbar was
  never told about it, so it kept the maximum it had when the group was
  still collapsed.
- An unreadable equipment row was labelled **"out of range"** even when
  distance was not the cause. It now states what was actually observed —
  that no equipment slot returned an item link — and prints the measured
  distance separately.
- **"Not expected for role X"** was shown for cells decided by class or by
  the item (a shaman has no ranged enchant slot; an empty exemptable slot),
  and pointed at an options switch that cannot change them. Those cells now
  give the real reason.
- The hit-column header claimed the number was summed from items alone,
  while it also contained auras and talents.

### Test mode

`/dc test` now simulates a **40-player raid** in eight subgroups instead of
25 players, including deliberately unreadable players and a completely
unreadable group.

## v0.5.2

New **Resistances tab**: display-only totals for all five schools per
player with a readable-players raid average in the footer. Equipment
semantics finalized: an empty slot counts as a gap unless it is one that may
legitimately be empty (off hand, ranged), the expectation grid governs
enchants only, and neck/rings joined the enchant logic (enchantable
on this server; expectation defaults to off). Expectation storage now
distinguishes a deliberate uncheck from a never-seen slot, so slots added in
future versions appear automatically.

## v0.5.1

The Equipment tab now covers all sixteen slots: neck and both rings joined
as item tiles (quality border, tooltip, empty slot counts as a gap — no
enchant exists for them in vanilla, so they carry no corner marker).

## v0.5.0

First public release: the four-tab readiness matrix (Consumables / Class
buffs / Debuffs / Equipment), the HAS–MISSING–UNKNOWN honesty model with
coverage pill and last-known display, the five-role system with
auto-suggestion and per-character confirmation, the role × class
expectations grid, per-player whispers with cooldown, the raid report with
mandatory preview, ready-check and window-open scan automation, and the
deterministic test mode.
