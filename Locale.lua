--[[--------------------------------------------------------------------
	WhoDidIt - languages

	English is written in the code. Locales\*.lua hold the other languages,
	one line per text, the English first:
	  T("English", "Deutsch", "Français", "Español", "Italiano", "Português", "Русский", "中文", "한국어")
	An empty string shows the English. %s / %d / %.1f in a text: the same ones in
	every language, in the same order - or numbered (%2$s, %1$d) when a
	language needs another order.

	S(...) is the same for a sentence a fight saves in English (a blame reason,
	a best play, a verdict...): fights are kept and shared in English, and
	W.LT finds the sentence by its pattern when it's shown, so every player
	reads it in their own language.

	W.L(text)         the text in the player's language (or as it is)
	W.LF(text, ...)   the same, then string.format with the values
	W.LT(sentence)    a saved English sentence in the player's language

	The language comes from the saved variables (the flags in the window's
	title bar), so it's only known at ADDON_LOADED: the window is built in
	English when the files load and translated then (W.UI.Relabel). Only the
	chosen language's texts are kept; changing it reloads the UI.
----------------------------------------------------------------------]]

local W = WhoDidIt
local Loc = { data = {}, lang = "en", col = 1 }
W.Locale = Loc

local getn = table.getn

-- the flags in the title bar, in this order; col = the column in Locales\*.lua;
-- confirm = what a first click on the flag says (in that language: its texts aren't
-- loaded yet). font: a language WoW's English client and Fira Sans can't show gets
-- its own (tools\FontSubset.ps1 also reads each language's line here)
Loc.LANGS = {
	{ code = "en", col = 1, name = "English", confirm = "Click again: English (reloads the UI)" },
	{ code = "de", col = 2, name = "Deutsch", confirm = "Nochmal klicken: Deutsch (lädt die UI neu)" },
	{ code = "fr", col = 3, name = "Français", confirm = "Cliquez encore : Français (recharge l'interface)" },
	{ code = "es", col = 4, name = "Español", confirm = "Haz clic otra vez: Español (recarga la interfaz)" },
	{ code = "it", col = 5, name = "Italiano", confirm = "Clicca ancora: Italiano (ricarica l'interfaccia)" },
	{ code = "pt", col = 6, name = "Português", confirm = "Clique de novo: Português (recarrega a interface)" },
	{ code = "ru", col = 7, name = "Русский", confirm = "Нажмите ещё раз: Русский (перезагрузка интерфейса)" },
	{ code = "zh", col = 8, name = "中文", confirm = "再点一次：中文（重新加载界面）", font = "Interface\\AddOns\\WhoDidIt\\Fonts\\WDI-NotoSansSC.ttf" },
	{ code = "ko", col = 9, name = "한국어", confirm = "한 번 더 클릭: 한국어 (UI 다시 불러오기)", font = "Interface\\AddOns\\WhoDidIt\\Fonts\\WDI-NotoSansKR.ttf" },
}
Loc.BY = {}
for i = 1, getn(Loc.LANGS) do Loc.BY[Loc.LANGS[i].code] = Loc.LANGS[i] end
function Loc.Flag(code) return "Interface\\AddOns\\WhoDidIt\\Flags\\" .. code end

-- the client's language, for the first start (most private-server clients are enUS)
local CLIENT = { deDE = "de", frFR = "fr", esES = "es", esMX = "es", itIT = "it", ptBR = "pt", ptPT = "pt",
	ruRU = "ru", zhCN = "zh", zhTW = "zh", koKR = "ko" }

local tr = {}          -- English -> the chosen language
local sentences = {}   -- S(...) lines: { pattern, translation, the longest plain part, length }
local cache, nCache = {}, 0

------------------------------------------------------------------ the files' data

-- Locales\*.lua: WhoDidIt.Locale.Add(function(T, S) T(...) ... end)
function Loc.Add(fn) if Loc.data then tinsert(Loc.data, fn) end end

-- an English format text as a Lua pattern: %s -> (.-), numbers -> their digits;
-- also returns its longest plain part (a quick test before the pattern)
local MAGIC = "([%^%$%(%)%.%[%]%*%+%-%?])"
local function toPattern(en)
	local out, longest, i, n = {}, "", 1, string.len(en)
	local plain = ""
	while i <= n do
		local c = string.sub(en, i, i)
		if c == "%" then
			local _, e, spec = string.find(en, "^%%[%-%d%.]*([sdfi%%])", i)
			if not e then return nil end
			if spec == "%" then
				tinsert(out, "%%"); plain = plain .. "%"
			else
				if string.len(plain) > string.len(longest) then longest = plain end
				plain = ""
				tinsert(out, (spec == "s") and "(.-)" or "(%-?[%d%.]+)")
			end
			i = e + 1
		else
			tinsert(out, (string.gsub(c, MAGIC, "%%%1")))
			plain = plain .. c
			i = i + 1
		end
	end
	if string.len(plain) > string.len(longest) then longest = plain end
	return "^" .. table.concat(out) .. "$", longest
end

-- the chosen language's texts from every file; the others are let go
function Loc.Load(code)
	local L = Loc.BY[code] or Loc.BY.en
	Loc.lang, Loc.col, Loc.font = L.code, L.col, L.font
	tr, sentences, cache, nCache = {}, {}, {}, 0
	local col = L.col
	local function pick(a1, a2, a3, a4, a5, a6, a7, a8)
		if col == 2 then return a1 elseif col == 3 then return a2 elseif col == 4 then return a3
		elseif col == 5 then return a4 elseif col == 6 then return a5 elseif col == 7 then return a6
		elseif col == 8 then return a7 elseif col == 9 then return a8 end
	end
	local function T(en, a1, a2, a3, a4, a5, a6, a7, a8)
		local v = pick(a1, a2, a3, a4, a5, a6, a7, a8)
		if v and v ~= "" then tr[en] = v end
	end
	local function S(en, a1, a2, a3, a4, a5, a6, a7, a8)
		local v = pick(a1, a2, a3, a4, a5, a6, a7, a8)
		if not (v and v ~= "") then return end
		tr[en] = v
		local pat, lit = toPattern(en)
		if pat then tinsert(sentences, { pat, v, lit, string.len(lit) }) end
	end
	if col > 1 then
		for i = 1, getn(Loc.data or {}) do
			local ok, err = pcall(Loc.data[i], T, S)
			if not ok then W:Oops("language data", err) end
		end
	end
	-- the most specific sentences first (the longest plain part)
	table.sort(sentences, function(a, b) return a[4] > b[4] end)
	Loc.data = nil
end

------------------------------------------------------------------ lookups

-- "|cffrrggbbText|r": the text inside, when that's what has a translation
local function unwrap(s)
	local _, _, c, inner = string.find(s, "^(|c%x%x%x%x%x%x%x%x)(.*)|r$")
	if inner and tr[inner] then return c, tr[inner] end
end

function W.L(s)
	if type(s) ~= "string" then return s end
	local t = tr[s]
	if t then return t end
	local c, inner = unwrap(s)
	if c then return c .. inner .. "|r" end
	return s
end

-- %1$s style: values by number, for languages that need another order
local function formatNumbered(t, a)
	t = string.gsub(t, "%%%%", "\1")
	t = string.gsub(t, "%%(%d)%$([%-%d%.]*[sdfi])", function(n, spec)
		local v = a[tonumber(n)]
		if v == nil then return "" end
		local ok, r = pcall(string.format, "%" .. spec, v)
		return ok and r or tostring(v)
	end)
	return (string.gsub(t, "\1", "%%"))
end

function W.LF(fmt, ...)
	local t = tr[fmt]
	if not t then
		local c, inner = unwrap(fmt)
		t = c and (c .. inner .. "|r") or fmt
	end
	if t ~= fmt then
		if string.find(t, "%%%d%$") then return formatNumbered(t, arg) end
		local ok, r = pcall(string.format, t, unpack(arg))
		if ok then return r end
	end
	return string.format(fmt, unpack(arg))
end

-- a saved English sentence in the player's language: its translation when it's
-- a known text, else the first S(...) sentence whose pattern fits, with the
-- parts it found (names, numbers, a cause...) put in - the parts translated
-- too when they are texts of their own
local function fill(t, caps, depth)
	for j = 1, getn(caps) do
		local c = caps[j]
		if tr[c] then caps[j] = tr[c]
		elseif depth < 2 and string.find(c, " ") then caps[j] = W.LT(c, depth + 1) end
	end
	if string.find(t, "%%%d%$") then return formatNumbered(t, caps) end
	local k = 0
	t = string.gsub(t, "%%%%", "\1")
	t = string.gsub(t, "%%[%-%d%.]*[sdfi]", function()
		k = k + 1
		return caps[k] or ""
	end)
	return (string.gsub(t, "\1", "%%"))
end

function W.LT(s, depth)
	if type(s) ~= "string" or Loc.col == 1 or s == "" then return s end
	local v = tr[s]
	if v then return v end
	v = cache[s]
	if v then return v end
	v = s
	-- a sentence in a colour: the sentence translated, the colour kept
	local _, _, c, inner = string.find(s, "^(|c%x%x%x%x%x%x%x%x)(.*)|r$")
	if inner and not string.find(inner, "|", 1, true) then
		local t = W.LT(inner, depth)
		if t ~= inner then v = c .. t .. "|r" end
	end
	if v == s then
		for i = 1, getn(sentences) do
			local e = sentences[i]
			if e[4] == 0 or string.find(s, e[3], 1, true) then
				local r = { string.find(s, e[1]) }
				if r[1] then
					local caps = {}
					for j = 3, getn(r) do caps[j - 2] = r[j] end
					v = fill(e[2], caps, depth or 0)
					break
				end
			end
		end
	end
	if nCache >= 4000 then cache, nCache = {}, 0 end
	cache[s] = v
	nCache = nCache + 1
	return v
end

-- a saved text that may hold several sentences or colour codes: each line on its own
function W.LTLines(s)
	if type(s) ~= "string" or Loc.col == 1 then return s end
	if not string.find(s, "\n") then return W.LT(s) end
	return (string.gsub(s, "[^\n]+", function(line) return W.LT(line) end))
end

function W.Lang() return Loc.lang end

-- date() with the month's name in the player's language ("%d %b": 06 Oct)
function W.LDate(fmt, t)
	if Loc.col > 1 and string.find(fmt, "%%b") then
		fmt = string.gsub(fmt, "%%b", (string.gsub(W.L(date("%b", t)), "%%", "%%%%")))
	end
	return date(fmt, t)
end

------------------------------------------------------------------ fonts WoW can't show

-- Chinese and Korean: WhoDidIt's text in the language's own font. WoW's
-- tooltips and pop-ups use the client's font, which on an English client has no
-- Chinese or Korean letters: WhoDidIt shows its tooltips in a copy of its own
-- (W.TT) and gives its pop-ups the font while they're open.
W.TT = GameTooltip

local SIDES = { "Left", "Right" }
local function setFonts(frameName, n, font)
	for i = 1, n do
		for _, side in ipairs(SIDES) do
			local fs = getglobal(frameName .. "Text" .. side .. i)
			if fs and fs.GetFont then
				local _, size, flags = fs:GetFont()
				if fs.wdiFont ~= font then
					fs:SetFont(font, size or 12, flags or "")
					fs.wdiFont = font
				end
			end
		end
	end
end

local function makeTooltip(font)
	local tt = CreateFrame("GameTooltip", "WhoDidItTooltip", UIParent, "GameTooltipTemplate")
	local show = tt.Show
	-- every line in the language's font (lines are added as needed, so on each show)
	tt.Show = function(self)
		setFonts("WhoDidItTooltip", self:NumLines(), font)
		show(self)
	end
	return tt
end

-- pop-ups: StaticPopup_Show with the texts in the player's language; for
-- Chinese / Korean the dialog's text and buttons get the font until it closes
local popupFonts = {}
local function restorePopup()
	for fs, old in pairs(popupFonts) do
		fs:SetFont(old[1], old[2], old[3])
		popupFonts[fs] = nil
	end
end
function W.ShowPopup(which, a1, a2)
	local d = StaticPopupDialogs[which]
	if d then
		if not d.wdiEn then
			d.wdiEn = { d.text, d.button1, d.button2 }
			local onHide = d.OnHide
			d.OnHide = function()
				restorePopup()
				if onHide then onHide() end
			end
		end
		d.text = W.L(d.wdiEn[1])
		d.button1 = d.wdiEn[2] and W.L(d.wdiEn[2])
		d.button2 = d.wdiEn[3] and W.L(d.wdiEn[3])
	end
	local dlg = StaticPopup_Show(which, a1, a2)
	if dlg and Loc.font then
		local name = dlg:GetName()
		for _, part in ipairs({ "Text", "Button1Text", "Button2Text" }) do
			local fs = getglobal(name .. part)
			if fs and fs.GetFont then
				local p, size, flags = fs:GetFont()
				if not popupFonts[fs] then popupFonts[fs] = { p, size, flags } end
				fs:SetFont(Loc.font, size or 13, flags or "")
			end
		end
	end
	return dlg
end

------------------------------------------------------------------ choosing

W:On("ADDON_LOADED", function(name)
	if name ~= "WhoDidIt" then return end
	local o = WhoDidItDB.opts
	if not (o.lang and Loc.BY[o.lang]) then o.lang = CLIENT[GetLocale and GetLocale() or ""] or "en" end
	Loc.Load(o.lang)
	if Loc.font then
		W.TT = makeTooltip(Loc.font)
		-- WhoDidIt's window fonts: its font objects (the text made from them follows)
		-- and the font files the run timer and other frames read when they're built
		local UI = W.UI
		if UI then
			UI.FONT, UI.FONT_BOLD = Loc.font, Loc.font
			for _, fname in pairs(UI.FONTS or {}) do
				local fo = getglobal(fname)
				if fo then
					local _, size, flags = fo:GetFont()
					fo:SetFont(Loc.font, size or 12, flags or "")
				end
			end
		end
	end
	if W.UI and W.UI.Relabel then W.UI.Relabel() end
end)

-- a flag clicked: the language is saved and the UI reloaded (only that language's
-- texts are kept in memory). Not in combat: a reload then would drop the fight.
function Loc.Set(code)
	if not Loc.BY[code] or code == Loc.lang then return end
	if UnitAffectingCombat("player") then
		W.Print(W.L("Change the language after the fight - it reloads the UI."))
		return
	end
	WhoDidItDB.opts.lang = code
	ReloadUI()
end
