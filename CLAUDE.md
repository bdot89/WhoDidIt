# WhoDidIt - notes for Claude Code

Starter from Shemp's review (6 Oct 2026), extended with what this project taught us.

## Platform
World of Warcraft client 1.12.1 (TurtleWoW / OctoWoW), Lua 5.0, with SuperWoW and Nampower.
- No #t (use table.getn), no % operator (use math.mod).
- No string.match or string.gmatch (use string.find and string.gfind).
- Strings have no methods: s:find() fails, write string.find(s, ...).
- Varargs only through the arg table. Handlers read the globals this, event, arg1..arg9.
- Widget API is 1.12: no SetSize, SetShown, SetColorTexture, HookScript, C_Timer, hooksecurefunc.
- SavedVariables of an addon are loaded after its files and before its ADDON_LOADED.
- UnitBuff(unit, i) returns texture, count, spellId. UnitDebuff has the dispel type before the id.
- A function may reference at most 32 upvalues; a file may have at most 200 top-level locals
  (UI.lua is close: put new things on the UI table instead of new top-level locals).
- gsub callbacks must return a value (nil deletes the match in 5.0).
- The client reads the .toc and Bindings.xml only at start-up: new files need a full restart
  (or ClassicAPI, which makes /reload pick them up).
- ClassicAPI is optional: everything must work without it (check W.env.classicapi).
- Chat: "|" starts a colour / link code, lines max out at 255 bytes, say / yell / channels
  have a spam limit (WhoDidIt sends one line a second there).
- Custom chat channels are split by faction: a master only feeds its own faction.
- math.randomseed is called once at load (Core.lua).
- Windows Script Host reads a .vbs written as UTF-16 with a BOM, so paths with umlauts
  survive; written as ASCII they turn into "?" (tested with cscript).
- Both Karazhan towers report GetRealZoneText() "Tower of Karazhan" (WhoDidIt's fights, RollFor,
  BigWigs, AutoMarker). Chronicle calls them "Lower Tower of Karazhan" (Lower Karazhan Halls,
  10 players) and "Upper Tower of Karazhan" (40). Data.lua D.sharedZones / Board.lua B.RunZone tell
  them apart by GetRaidRosterInfo's 7th return (zone); that value isn't checked in game yet.

## Before every commit
- Every .lua file must load under a real Lua 5.0 interpreter (syntax check). There is no
  interpreter on the maintainer's PC yet; until there is, at least balance-check blocks.
- Never guess an API. Find a call in an addon that is known to work on this client,
  or print the return values in game first and write the result into this file.
- Re-read the diff as a reviewer and try to break it. Say what you checked and what you did not.
- Edits must not halve backslashes: Lua paths are written "Interface\\Icons\\..." in the
  source. Shell heredocs and perl replacements have dropped them before; check after editing.
- The working tree uses CRLF line endings; normalise before exact-text replacements.

## House rules
- Anything that posts to a shared chat channel, changes loot or raid marks, disables
  another addon or deletes data is OFF by default and asks before the first use.
- A plain click shows things in the player's own chat; posting needs Ctrl-click or a button.
- Never touch another addon's SavedVariables or its enabled state without asking the user
  (W:AskHandover).
- Data received from other players or from the web is untrusted: check length and
  characters, and never repeat it in a public channel automatically. Other guilds' names
  only go out after the player has seen the exact text (W:ConfirmSend).
- The master feed is only accepted from the characters in B.MASTERS (Board.lua). A player can
  only remove (and re-add) those; nobody else can be added.
- In a raid only the leader and assistants post or steer the raid (W.CanLead in Core.lua). W:Send
  sends anyone else's posts to their own chat (W.LeadOnly says why, once), claims for automatic
  posts only count leaders, and the loaders wrap DopingControl's report / whispers and RollFor's
  raid chat (master looter allowed) without touching their files.
- A message kind that is accepted without the trusted-sender check must not make anyone else
  send, store or compute without a cooldown and a cap (A and Q in Board.lua are rationed).
- Raid times only come from the master feed and the download: players never send K / C records, B:Receive ignores them, and B:PurgeShared removed the ones received before 1.23.1. Your own recorded times stay on your PC.
- Every table keyed by a GUID, a name or an error text needs an eviction rule.
- Every Lua function may use at most 32 upvalues: check the big ones (FeedReceive, the feed
  ticker in Board.lua) when adding file-level locals they use.
- Code from other repositories enters this one through a reviewed commit, never through a
  bot. Embedded addons are pinned to tested commits (tools/EmbedUpdate.ps1, Pin).
- Event handlers run through pcall. Errors are printed once and kept for bug reports
  (/wdi errors).
- Blame needs evidence. When the data is ambiguous, show it as information with 0 points.
- One feature per commit.
- Raid scaling eras: D.SCALING.at in Data.lua and $ScalingCutoff in tools/WhoDidIt-Sync.ps1 must
  stay equal (6 Oct 2026 04:54 UTC). Boards "kills+" / "clears+" hold the bests since then;
  the helper writes them as C2 / K2 lines and the feed sends them as "c!," / "k!," records
  (older clients skip those). Chronicle's leaderboard can't filter by date, so clears since
  are worked out from the raid logs (bosses every top run killed, time of the last one).
- PackData.lua (WDI_MARKDATA) ships the Auto Marker's raid pack data, converted from AutoMarker's
  NPCList.lua (Weird Vibes) at the pin in tools/MarkDataUpdate.ps1, data only, credited in the
  file and README, not under WhoDidIt's MIT licence, removed if the author asks. Rebuild it only
  with that script from the real upstream file, never from edited copies.
- Players install WhoDidIt by drag and drop only: nothing may tell them to run a CMD/PowerShell
  file (ClassicAPI, a DLL, is the one optional exception). Chronicle\, RollFor\ and DopingControl\
  ship in the repo at the pins in tools/EmbedUpdate.ps1 (maintainer tool: move a pin, run it,
  review, commit), each with WDI_NOTICE.txt. The sync helper and AutoSync are maintainer-only
  (they refuse to run on a PC without a B.MASTERS character).
- The built-in Chronicle logger logs nothing until the player says yes (opts.chronUse). It stands
  down only while a separate ChronicleCompanion is actually loaded. A disabled or deleted one doesn't
  count: WTF keeps "ChronicleCompanion: disabled" after the hand-over or after the folder is deleted.
- 5-man rankings (Dungeons.lua, W.Runs): D.DUNGEONS in Data.lua (level-60 dungeons, final bosses, splits, art). A run =
  first pull after zoning in -> final boss death. Members agree on WDI5 (party/raid addon channel): any opt-out
  (opts.no5man) keeps it private; time = the longest anyone timed; the leader (else first name) names and shares it.
  Channel record "D" (Board.lua hands it to W.Runs:Receive) is only accepted from a member; group names are untrusted
  (R.OkName). Masters write CustomData\WhoDidIt_Runs.txt (R5 lines + |ok) for Publish-RaidTimes and
  tools\Website-Export.ps1 (JSON for the website; upload off until tools\website.json, which is gitignored).
- Character names in the repository (RaidTimes.lua) or an export: the maintainer chose option (b) of review 3's T1
  (9 Oct 2026). rec.ok (Dungeons.lua addOk) holds the members this PC saw share a run themselves: their own WDI5 vote,
  or the run sent by them on the realm channel (the server says who sent it; never what a message claims). Only those
  are named; Publish-RaidTimes takes a run only when every member is in ok, Website-Export shows the rest by class.
  Any other place that would publish names needs the maintainer's decision and a README line.
- The guild's Hall of Fame (GuildFame.lua, W.GuildFame): each saved fight of the guild (rec.guild = Board's RaidGuild)
  becomes a card "recorder:n", swapped on SendAddonMessage "WDIG" GUILD (V = have per recorder, C = card chunks,
  X = card that doesn't count, F = skip). Twin fights (same enc, 5 min, 20 s): the smallest id counts, so every PC
  agrees. Sending your own needs opts.gfame (asked once). 800 cards / 4000 ids / 300 recorders / 3 guilds kept.
- RaidTimes.lua (WDI_RAIDTIMES) ships every guild's raid times from the maintainer's sync
  (tools/Publish-RaidTimes.ps1: C/K/C2/K2/L lines, R5 only when every member is in ok, no PC/PK; refuses [[ ]] in a line, since
  it's a Lua 5.0 long string). B:SeedSnapshot puts it into the saved feed when it's newer, so the
  feed only sends what's newer; FULL_AGE is 21 days so a few-weeks-old snapshot asks for an update.
- The maintainer's sync helper commits and pushes RaidTimes.lua by itself once a week
  (Publish-RaidTimes.ps1 -Auto; it skips when main has unpushed commits). Pull --rebase before
  pushing; never stage RaidTimes.lua with other changes.

## Languages (Locale.lua, Locales\*.lua)
- English is written in the code and is what WhoDidIt saves and sends: fights, boards, the feed,
  addon messages. Text is translated only when it's shown, never before it's stored or sent.
- New text a player sees: W.L("text"), W.LF("format %s", v) (string.format after translating),
  W.LT(sentence) for a sentence a fight saved in English (matched against S(...) patterns).
  Button SetText (UI.Skin), header labels (UI.SinkText), W.Print, W:Prompt, W.ShowPopup and the
  tooltip helpers already translate; W.L of a translated or unknown text returns it unchanged.
- Then add a T("English", de, fr, es, it, pt, ru, zh, ko) line to the matching Locales file (9 strings,
  "" = English). Placeholders the same and in the same order, or numbered (%1$s, %2$d). Keys must be
  the exact English, escapes included ("\n", "\\"), colour codes too (or translate the inner text:
  W.L unwraps one "|cffxxxxxx...|r").
- Locale.lua loads after Core.lua, which has English stand-ins (W.L etc.), so a /reload after an
  update that adds files still works (in English, without flags) until WoW restarts.
- The language is known at ADDON_LOADED: UI.Relabel translates the window built in English, then
  UI.FitAll shrinks labels that don't fit. Changing language = ReloadUI (Loc.Set, not in combat).
- Chinese / Korean use Fonts\WDI-NotoSansSC.ttf / KR.ttf, subsets with only the characters the zh / ko
  columns use: run tools\FontSubset.ps1 after changing those translations (it stops when a character
  is missing). WoW's own tooltip and pop-ups use the client font: WhoDidIt uses W.TT and W.ShowPopup.
- Chat: a translated line can be longer (Chinese / Korean letters are 3 bytes in UTF-8); split at 255
  bytes on a character boundary.
