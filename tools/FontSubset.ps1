# Builds WhoDidIt's Chinese and Korean fonts (maintainer tool, not in the player download;
# the .ttf files it writes are committed).
#
# WoW's English client has no Chinese or Korean letters, and WhoDidIt's own font (Fira Sans
# Condensed) covers the European languages and Russian only. So for Chinese and Korean
# WhoDidIt ships Noto Sans SC / Noto Sans KR (Google, SIL Open Font Licence 1.1, see
# Fonts\OFL-Noto.txt), cut down to the letters it needs: plain Latin, Latin-1, Cyrillic,
# punctuation, and every character the Chinese / Korean column of Locales\*.lua uses.
# Run it again after changing a Chinese or Korean translation: it stops if a character
# the translations use isn't in the font.
#
# The sources are the static Medium (500) cuts Google Fonts serves (pinned below, checked
# by SHA-256; downloaded into tools\.fontcache, which git ignores).
#
#   powershell -ExecutionPolicy Bypass -File tools\FontSubset.ps1 [-Preview sample.png]
param([string]$Preview)
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$cache = Join-Path $PSScriptRoot ".fontcache"
$SOURCES = @(
    @{ lang = "zh"; col = 8; out = "Fonts\WDI-NotoSansSC.ttf"; file = "NotoSansSC-500.ttf"
       url = "https://fonts.gstatic.com/s/notosanssc/v41/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG-3FnYxNbPzT3HI.ttf"
       sha = "b73c6d8469c078094e7821cc0887d3098d34618fab67c728c86f09114bbefcf6" },
    @{ lang = "ko"; col = 9; out = "Fonts\WDI-NotoSansKR.ttf"; file = "NotoSansKR-500.ttf"
       url = "https://fonts.gstatic.com/s/notosanskr/v40/PbyxFmXiEBPT4ITbgNA5Cgms3VYcOA-vvnIzztgyeLTq8H4gReI.ttf"
       sha = "21909862a104c41b1389b3bd89ecc5608f7b8f8a49d7117b1c7bf5a332d0bd3f" }
)

Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Text;
// A small TrueType subsetter: keeps the glyphs of the given characters (and the parts
// composite glyphs are built from), renumbers them, and writes a font with a fresh
// format 4 cmap and no layout tables (WoW doesn't use GSUB / GPOS / vertical metrics).
public static class TtfSubset {
    static int U16(byte[] b, int o) { return (b[o] << 8) | b[o + 1]; }
    static short S16(byte[] b, int o) { return (short)((b[o] << 8) | b[o + 1]); }
    static uint U32(byte[] b, int o) { return (uint)((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]); }
    static void W16(List<byte> l, int v) { l.Add((byte)(v >> 8)); l.Add((byte)v); }
    static void W32(List<byte> l, uint v) { l.Add((byte)(v >> 24)); l.Add((byte)(v >> 16)); l.Add((byte)(v >> 8)); l.Add((byte)v); }
    static void P16(byte[] b, int o, int v) { b[o] = (byte)(v >> 8); b[o + 1] = (byte)v; }
    static void P32(byte[] b, int o, uint v) { b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v; }

    // character -> glyph of a whole font file
    public static Dictionary<int, int> FontCmap(byte[] f) {
        int nt = U16(f, 4);
        for (int i = 0; i < nt; i++) {
            int r = 12 + 16 * i;
            if (Encoding.ASCII.GetString(f, r, 4) != "cmap") continue;
            int off = (int)U32(f, r + 8), len = (int)U32(f, r + 12);
            var x = new byte[len]; Buffer.BlockCopy(f, off, x, 0, len);
            return ReadCmap(x);
        }
        throw new Exception("no cmap table");
    }

    public static Dictionary<int, int> ReadCmap(byte[] c) {
        int n = U16(c, 2), best = -1, bestRank = 0;
        for (int i = 0; i < n; i++) {
            int r = 4 + 8 * i, pid = U16(c, r), eid = U16(c, r + 2), off = (int)U32(c, r + 4), fmt = U16(c, off);
            int rank = (fmt == 12 && (pid == 3 || pid == 0)) ? 3 : (fmt == 4 && (pid == 3 || pid == 0)) ? 2 : 0;
            if (rank > bestRank) { bestRank = rank; best = off; }
        }
        if (best < 0) throw new Exception("no Unicode cmap");
        var map = new Dictionary<int, int>();
        if (U16(c, best) == 12) {
            int groups = (int)U32(c, best + 12);
            for (int g = 0; g < groups; g++) {
                int p = best + 16 + 12 * g; int s = (int)U32(c, p), e = (int)U32(c, p + 4), gid = (int)U32(c, p + 8);
                for (int cp = s; cp <= e; cp++) map[cp] = gid + (cp - s);
            }
        } else {
            int segs = U16(c, best + 6) / 2, ends = best + 14, starts = ends + 2 * segs + 2, deltas = starts + 2 * segs, ranges = deltas + 2 * segs;
            for (int s = 0; s < segs; s++) {
                int e = U16(c, ends + 2 * s), st = U16(c, starts + 2 * s), d = U16(c, deltas + 2 * s), ro = U16(c, ranges + 2 * s);
                for (int cp = st; cp <= e && cp != 0xFFFF; cp++) {
                    int g;
                    if (ro == 0) g = (cp + d) & 0xFFFF;
                    else { g = U16(c, ranges + 2 * s + ro + 2 * (cp - st)); if (g != 0) g = (g + d) & 0xFFFF; }
                    if (g != 0) map[cp] = g;
                }
            }
        }
        return map;
    }

    public static byte[] Run(byte[] f, int[] cps) {
        if (U32(f, 0) != 0x00010000) throw new Exception("not a TrueType (glyf) font");
        int nt = U16(f, 4);
        var tab = new Dictionary<string, byte[]>();
        for (int i = 0; i < nt; i++) {
            int r = 12 + 16 * i; string tag = Encoding.ASCII.GetString(f, r, 4);
            int off = (int)U32(f, r + 8), len = (int)U32(f, r + 12);
            var x = new byte[len]; Buffer.BlockCopy(f, off, x, 0, len); tab[tag] = x;
        }
        if (tab.ContainsKey("fvar")) throw new Exception("a variable font: use a static cut");
        byte[] head = tab["head"], maxp = tab["maxp"], hhea = tab["hhea"], hmtx = tab["hmtx"], loca = tab["loca"], glyf = tab["glyf"];
        bool longLoca = S16(head, 50) == 1;
        Func<int, int> at = g => longLoca ? (int)U32(loca, g * 4) : U16(loca, g * 2) * 2;
        var cmap = ReadCmap(tab["cmap"]);

        // the glyphs: .notdef, then the characters' glyphs in character order (so the cmap
        // packs into runs), then the parts composite glyphs use
        var order = new List<int> { 0 }; var newId = new Dictionary<int, int> { { 0, 0 } };
        var pairs = new List<int[]>();
        var sorted = new List<int>(cps); sorted.Sort();
        foreach (int cp in sorted) {
            int g; if (cp > 0xFFFF || !cmap.TryGetValue(cp, out g)) continue;
            if (!newId.ContainsKey(g)) { newId[g] = order.Count; order.Add(g); }
            pairs.Add(new int[] { cp, newId[g] });
        }
        for (int k = 0; k < order.Count; k++) {
            int g = order[k], off = at(g), end = at(g + 1);
            if (end - off < 10 || S16(glyf, off) >= 0) continue;
            int p = off + 10;
            while (true) {
                int fl = U16(glyf, p), part = U16(glyf, p + 2);
                if (!newId.ContainsKey(part)) { newId[part] = order.Count; order.Add(part); }
                p += 4 + (((fl & 1) != 0) ? 4 : 2) + (((fl & 8) != 0) ? 2 : ((fl & 0x40) != 0) ? 4 : ((fl & 0x80) != 0) ? 8 : 0);
                if ((fl & 0x20) == 0) break;
            }
        }

        // glyf + loca (long offsets), composite parts renumbered
        var ng = new List<byte>(); var nl = new List<byte>();
        foreach (int g in order) {
            W32(nl, (uint)ng.Count);
            int off = at(g), len = at(g + 1) - off;
            if (len <= 0) continue;
            var x = new byte[len]; Buffer.BlockCopy(glyf, off, x, 0, len);
            if (len >= 10 && S16(x, 0) < 0) {
                int p = 10;
                while (true) {
                    int fl = U16(x, p); P16(x, p + 2, newId[U16(x, p + 2)]);
                    p += 4 + (((fl & 1) != 0) ? 4 : 2) + (((fl & 8) != 0) ? 2 : ((fl & 0x40) != 0) ? 4 : ((fl & 0x80) != 0) ? 8 : 0);
                    if ((fl & 0x20) == 0) break;
                }
            }
            ng.AddRange(x);
            while (ng.Count % 4 != 0) ng.Add(0);
        }
        W32(nl, (uint)ng.Count);

        // full metrics for every glyph
        int nhm = U16(hhea, 34); var nm = new List<byte>();
        foreach (int g in order) {
            int adv = U16(hmtx, 4 * Math.Min(g, nhm - 1));
            int lsb = g < nhm ? S16(hmtx, 4 * g + 2) : S16(hmtx, 4 * nhm + 2 * (g - nhm));
            W16(nm, adv); W16(nm, lsb & 0xFFFF);
        }
        P16(hhea, 34, order.Count);
        P16(maxp, 4, order.Count);
        P16(head, 50, 1);
        P32(head, 8, 0);

        // cmap: one format 4 table (3, 1), a segment per run of consecutive characters and glyphs
        var segs = new List<int[]>();   // start, end, delta
        foreach (var pr in pairs) {
            var last = segs.Count > 0 ? segs[segs.Count - 1] : null;
            if (last != null && pr[0] == last[1] + 1 && ((pr[1] - pr[0]) & 0xFFFF) == last[2]) last[1] = pr[0];
            else segs.Add(new int[] { pr[0], pr[0], (pr[1] - pr[0]) & 0xFFFF });
        }
        segs.Add(new int[] { 0xFFFF, 0xFFFF, 1 });
        int sc = segs.Count, pow = 1, sel = 0;
        while (pow * 2 <= sc) { pow *= 2; sel++; }
        var cm = new List<byte>();
        W16(cm, 0); W16(cm, 1); W16(cm, 3); W16(cm, 1); W32(cm, 12);
        W16(cm, 4); W16(cm, 16 + 8 * sc); W16(cm, 0); W16(cm, sc * 2); W16(cm, pow * 2); W16(cm, sel); W16(cm, sc * 2 - pow * 2);
        foreach (var s in segs) W16(cm, s[1]);
        W16(cm, 0);
        foreach (var s in segs) W16(cm, s[0]);
        foreach (var s in segs) W16(cm, s[2]);
        foreach (var s in segs) W16(cm, 0);

        // post 3.0: no glyph names
        var post = new byte[32]; Buffer.BlockCopy(tab["post"], 0, post, 0, 32); P32(post, 0, 0x00030000);

        var keep = new SortedDictionary<string, byte[]>(StringComparer.Ordinal);
        keep["head"] = head; keep["hhea"] = hhea; keep["maxp"] = maxp; keep["hmtx"] = nm.ToArray();
        keep["loca"] = nl.ToArray(); keep["glyf"] = ng.ToArray(); keep["cmap"] = cm.ToArray(); keep["post"] = post;
        foreach (var t in new string[] { "OS/2", "name", "cvt ", "fpgm", "prep", "gasp" }) if (tab.ContainsKey(t)) keep[t] = tab[t];

        int n = keep.Count, p2 = 1, es = 0;
        while (p2 * 2 <= n) { p2 *= 2; es++; }
        var o = new List<byte>();
        W32(o, 0x00010000); W16(o, n); W16(o, p2 * 16); W16(o, es); W16(o, n * 16 - p2 * 16);
        int dataAt = 12 + 16 * n, headAt = 0; var body = new List<byte>();
        foreach (var kv in keep) {
            var d = kv.Value; uint sum = 0;
            for (int i = 0; i < d.Length; i += 4) {
                uint w = 0; for (int j = 0; j < 4; j++) w = (w << 8) | (uint)(i + j < d.Length ? d[i + j] : 0); sum += w;
            }
            if (kv.Key == "head") headAt = dataAt + body.Count;
            o.AddRange(Encoding.ASCII.GetBytes(kv.Key)); W32(o, sum); W32(o, (uint)(dataAt + body.Count)); W32(o, (uint)d.Length);
            body.AddRange(d); while (body.Count % 4 != 0) body.Add(0);
        }
        o.AddRange(body);
        var font = o.ToArray(); uint total = 0;
        for (int i = 0; i < font.Length; i += 4) total += U32(font, i);
        P32(font, headAt + 8, 0xB1B0AFBA - total);
        return font;
    }
}
'@

# every string of one column (8 = zh, 9 = ko) of the T(...) / S(...) lines in Locales\*.lua,
# and the language's line in Locale.lua's LANGS (its name and the flag's "click again")
function Get-Column([int]$col, [string]$lang) {
    $sb = New-Object Text.StringBuilder
    foreach ($f in Get-ChildItem (Join-Path $root "Locales") -Filter *.lua) {
        foreach ($line in [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)) {
            if ($line -notmatch '^\s*[TS]\(') { continue }
            $m = [regex]::Matches($line, '"((?:[^"\\]|\\.)*)"')
            if ($m.Count -ge $col) { [void]$sb.Append($m[$col - 1].Groups[1].Value) }
        }
    }
    $found = $false
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $root "Locale.lua"), [Text.Encoding]::UTF8)) {
        if ($line -match "^\s*\{ code = `"$lang`"") { [void]$sb.Append($line); $found = $true }
    }
    if (-not $found) { throw "${lang}: no line in Locale.lua's LANGS" }
    return $sb.ToString()
}

$base = New-Object Collections.Generic.HashSet[int]
foreach ($r in @(@(0x20, 0x7E), @(0xA0, 0xFF), @(0x100, 0x17F), @(0x400, 0x45F), @(0x2010, 0x2027), @(0x2030, 0x203A), @(0x2190, 0x2193),
        @(0x2212, 0x2212), @(0x25A0, 0x25CF), @(0x3000, 0x303F), @(0xFF01, 0xFF5E))) {
    for ($c = $r[0]; $c -le $r[1]; $c++) { [void]$base.Add($c) }
}

if (-not (Test-Path $cache)) { New-Item -ItemType Directory $cache | Out-Null }
foreach ($s in $SOURCES) {
    $src = Join-Path $cache $s.file
    if (-not (Test-Path $src)) { "downloading $($s.file)"; Invoke-WebRequest -UseBasicParsing -Uri $s.url -OutFile $src }
    $sha = (Get-FileHash $src -Algorithm SHA256).Hash.ToLower()
    if ($sha -ne $s.sha) { throw "$($s.file): SHA-256 $sha isn't the pinned one" }
    $bytes = [IO.File]::ReadAllBytes($src)
    $text = Get-Column $s.col $s.lang
    $want = New-Object Collections.Generic.HashSet[int] (, $base)
    $need = New-Object Collections.Generic.HashSet[int]
    for ($i = 0; $i -lt $text.Length; $i++) {
        $cp = [int]$text[$i]
        if ($cp -ge 0xD800 -and $cp -le 0xDFFF) { throw "$($s.lang): a character outside the BMP in the translations" }
        if ($cp -gt 0x7E) { [void]$need.Add($cp) }
        [void]$want.Add($cp)
    }
    # every character the translations use must be in the font
    $srcMap = [TtfSubset]::FontCmap($bytes)
    $missing = @($need | Where-Object { -not $srcMap.ContainsKey($_) } | ForEach-Object { [char]$_ })
    if ($missing.Count -gt 0) { throw "$($s.lang): not in $($s.file): $($missing -join ' ')" }
    $arr = New-Object int[] $want.Count; $want.CopyTo($arr)
    $outBytes = [TtfSubset]::Run($bytes, $arr)
    # check the result before writing it: every wanted character the source has maps in it
    $chk = [TtfSubset]::FontCmap($outBytes)
    $lost = @($arr | Where-Object { $srcMap.ContainsKey($_) -and -not $chk.ContainsKey($_) })
    if ($lost.Count -gt 0) { throw "$($s.lang): $($lost.Count) characters lost in the subset" }
    [IO.File]::WriteAllBytes((Join-Path $root $s.out), $outBytes)
    "{0}: {1} characters from the translations, {2} in the font, {3:N0} KB -> {4}" -f $s.lang, $need.Count, $chk.Count, ($outBytes.Length / 1KB), $s.out
}

if ($Preview) {
    Add-Type -AssemblyName System.Drawing
    $pfc = New-Object System.Drawing.Text.PrivateFontCollection
    $bmp = [System.Drawing.Bitmap]::new(900, 150)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.Clear([System.Drawing.Color]::FromArgb(20, 20, 24))
    $g.TextRenderingHint = "AntiAliasGridFit"
    $y = 8
    foreach ($s in $SOURCES) {
        $pfc = New-Object System.Drawing.Text.PrivateFontCollection
        $pfc.AddFontFile((Join-Path $root $s.out))
        $font = New-Object System.Drawing.Font($pfc.Families[0], 15)
        $sample = (Get-Column $s.col $s.lang)
        if ($sample.Length -gt 60) { $sample = $sample.Substring(0, 60) }
        $g.DrawString("$($s.lang): Ragnaros 3:12  $sample", $font, [System.Drawing.Brushes]::White, 8, $y)
        $y += 34
    }
    $bmp.Save($Preview, [System.Drawing.Imaging.ImageFormat]::Png)
    "preview: $Preview"
}
