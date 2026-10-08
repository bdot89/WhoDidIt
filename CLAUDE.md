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
- The master feed is only accepted from the characters in B.MASTERS (Board.lua), as
  changed by the player's own /wdi master add|remove list.
- A message kind that is accepted without the trusted-sender check must not make anyone else
  send, store or compute without a cooldown and a cap (A and Q in Board.lua are rationed).
- A guild's shared times only count from a sender seen in that guild (Board.lua, learnGuild).
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
- The built-in Chronicle logger logs nothing until the player says yes (opts.chronUse), and stays
  off when the separate ChronicleCompanion is installed but disabled (WDI_CHRON_OFF).
- 5-man rankings (Dungeons.lua, W.Runs): D.DUNGEONS in Data.lua (level-60 dungeons, final bosses, splits, art). A run =
  first pull after zoning in -> final boss death. Members agree on WDI5 (party/raid addon channel): any opt-out
  (opts.no5man) keeps it private; time = the longest anyone timed; the leader (else first name) names and shares it.
  Channel record "D" (Board.lua hands it to W.Runs:Receive) is only accepted from a member; group names are untrusted
  (R.OkName). Masters write CustomData\WhoDidIt_Runs.txt (R5 lines) for Publish-RaidTimes and tools\Website-Export.ps1
  (JSON for the website; upload off until tools\website.json, which is gitignored).
- RaidTimes.lua (WDI_RAIDTIMES) ships every guild's raid times from the maintainer's sync
  (tools/Publish-RaidTimes.ps1: C/K/C2/K2/L lines only, no PC/PK; refuses [[ ]] in a line, since
  it's a Lua 5.0 long string). B:SeedSnapshot puts it into the saved feed when it's newer, so the
  feed only sends what's newer; FULL_AGE is 21 days so a few-weeks-old snapshot asks for an update.
- The maintainer's sync helper commits and pushes RaidTimes.lua by itself once a week
  (Publish-RaidTimes.ps1 -Auto; it skips when main has unpushed commits). Pull --rebase before
  pushing; never stage RaidTimes.lua with other changes.
