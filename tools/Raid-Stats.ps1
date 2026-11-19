<#
    Raid-Stats (maintainer tool): one Chronicle raid as a short summary: who was there, damage and
    healing per player, and every death per boss. From Chronicle's public event streams
    (/raidlogs/instances/<slug>/events/<type>: gzip, encounter frames, length-delimited protobuf;
    format in its docs/external-api-event-streams.md).

      Raid-Stats.ps1 -Slug OoSy8IsNEtUmewVE     print one raid's lines and their size
    Dot-source it for Get-RaidStats.

    Lines:
      P|slug|Name:Cl:damage:healing:deaths;...           (players, most damage first)
      X|slug|Boss>Name=secs into the fight=killed by;... (deaths, per boss fight in order)
#>
param([string]$Slug = "", [switch]$KeepFiles)

if (-not ("WdiRaidStream" -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.IO; using System.IO.Compression; using System.Text; using System.Collections.Generic;
public class WdiEvent { public string Enc, Caster, Target, Source, Name, Class; public long Amount, Over, Offset; public long First; }
public static class WdiRaidStream {
    static ulong V(byte[] b, ref int p) { ulong r = 0; int s = 0; while (true) { byte x = b[p++]; r |= (ulong)(x & 127) << s; if ((x & 128) == 0) return r; s += 7; } }
    // kind: damage, heal, slain, combatant_info
    public static List<WdiEvent> Read(byte[] gz, string kind) {
        var ms = new MemoryStream(); using (var g = new GZipStream(new MemoryStream(gz), CompressionMode.Decompress)) g.CopyTo(ms);
        byte[] b = ms.ToArray(); var o = new List<WdiEvent>(); int p = 0;
        while (p < b.Length) {
            int n = (int)V(b, ref p); string enc = Encoding.UTF8.GetString(b, p, n); p += n;
            long first = (long)V(b, ref p); int count = (int)V(b, ref p); int len = (int)V(b, ref p); int end = p + len;
            for (int i = 0; i < count; i++) {
                int m = (int)V(b, ref p); var e = new WdiEvent(); e.Enc = enc; e.First = first;
                Msg(b, p, p + m, kind, e); p += m; o.Add(e);
            }
            p = end;
        }
        return o;
    }
    static void Msg(byte[] b, int p, int end, string kind, WdiEvent e) {
        while (p < end) {
            ulong tag = V(b, ref p); int f = (int)(tag >> 3), w = (int)(tag & 7);
            if (w == 0) { long v = (long)V(b, ref p);
                if (kind == "damage") { if (f == 7) e.Amount = v; else if (f == 11) e.Over = v; }
                else if (kind == "heal") { if (f == 6) e.Amount = v; else if (f == 10) e.Over = v; }
            } else if (w == 2) { int n = (int)V(b, ref p); int q = p; p += n;
                if (f == 1) { int r = q; while (r < q + n) { ulong t = V(b, ref r); int tf = (int)(t >> 3), tw = (int)(t & 7);
                        if (tw == 0) { long v = (long)V(b, ref r); if (tf == 2) e.Offset = v; } else if (tw == 2) { int l = (int)V(b, ref r); r += l; } else if (tw == 1) r += 8; else if (tw == 5) r += 4; else break; }
                    continue; }
                if (kind == "slain" && f == 4) { var a = new WdiEvent(); Msg(b, q, q + n, "damage", a); e.Source = a.Source; continue; }
                string s = Encoding.UTF8.GetString(b, q, n);
                if (kind == "damage") { if (f == 3) e.Caster = s; else if (f == 4) e.Source = s; else if (f == 5) e.Target = s; }
                else if (kind == "heal") { if (f == 3) e.Caster = s; else if (f == 4) e.Target = s; }
                else if (kind == "slain") { if (f == 2) e.Target = s; else if (f == 3) e.Caster = s; }
                else if (kind == "combatant_info") { if (f == 2) e.Target = s; else if (f == 3) e.Name = s; else if (f == 4) e.Class = s; }
            } else if (w == 1) p += 8; else if (w == 5) p += 4; else return;
        }
    }
}
'@
}

$script:RsApi = "https://legacy.chronicleclassic.com/api/external/v1"
$script:RsUA = "WhoDidIt-Sync/1.1 (+https://github.com/bdot89/WhoDidIt)"
$script:RsClass = @{ WARRIOR = "Wa"; PALADIN = "Pa"; HUNTER = "Hu"; ROGUE = "Ro"; PRIEST = "Pr"; SHAMAN = "Sh"; MAGE = "Ma"; WARLOCK = "Wl"; DRUID = "Dr" }

function Get-RsStream($slug, $type) {
    $wc = New-Object Net.WebClient
    $wc.Headers["User-Agent"] = $script:RsUA
    try { return [WdiRaidStream]::Read($wc.DownloadData("$($script:RsApi)/raidlogs/instances/$slug/events/$type"), $type) } finally { $wc.Dispose() }
}

# the summary's lines for one raid; encounter names from the raid's own record
function Get-RaidStats($slug, $inst) {
    $names = @{}
    foreach ($e in @($inst.encounters)) { if ($e.boss) { $names[[string]$e.id] = [string]$e.name } }   # (deaths: boss fights only)
    $players = @{}
    foreach ($c in (Get-RsStream $slug "combatant_info")) {
        if ($c.Target -and $c.Name -and -not $players.ContainsKey($c.Target)) {
            $players[$c.Target] = @{ n = $c.Name; c = $script:RsClass[([string]$c.Class).ToUpper()]; d = 0L; h = 0L; x = 0 }
        }
    }
    foreach ($e in (Get-RsStream $slug "damage")) {
        if ($e.Caster -and $players.ContainsKey($e.Caster) -and -not $players.ContainsKey($e.Target) -and $e.Amount -gt 0) { $players[$e.Caster].d += ($e.Amount - $e.Over) }
    }
    foreach ($e in (Get-RsStream $slug "heal")) {
        if ($e.Caster -and $players.ContainsKey($e.Caster)) { $players[$e.Caster].h += ($e.Amount - $e.Over) }
    }
    $deaths = New-Object System.Collections.ArrayList
    foreach ($e in (Get-RsStream $slug "slain")) {
        if (-not $players.ContainsKey($e.Target)) { continue }
        $p = $players[$e.Target]
        $p.x++
        if (-not $names.ContainsKey($e.Enc)) { continue }
        $src = [string]$e.Source -replace '[|;>=]', ''
        [void]$deaths.Add(@{ enc = $names[$e.Enc]; line = "$($p.n)=$([math]::Floor($e.Offset / 1000))=$src" })
    }
    $list = @($players.Values | Where-Object { $_.c } | Sort-Object { -$_.d })
    $out = @("P|$slug|" + (($list | ForEach-Object { "$($_.n):$($_.c):$($_.d):$($_.h):$($_.x)" }) -join ";"))
    $byBoss = New-Object System.Collections.ArrayList
    $last = $null; $cur = $null
    foreach ($d in $deaths) {
        if ($d.enc -ne $last) { $last = $d.enc; $cur = New-Object System.Collections.ArrayList; [void]$byBoss.Add(@{ n = $last; l = $cur }) }
        [void]$cur.Add($d.line)
    }
    $x = @($byBoss | ForEach-Object { "$($_.n)>" + ($_.l -join ",") })
    if ($x.Count) { $out += "X|$slug|" + ($x -join ";") }
    return $out
}

if ($MyInvocation.InvocationName -ne "." -and $Slug) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $inst = Invoke-RestMethod -Uri "$script:RsApi/raidlogs/instances/$Slug" -UserAgent $script:RsUA -TimeoutSec 60
    $l = Get-RaidStats $Slug $inst
    $l
    "--- $(($l -join "`n").Length) bytes"
}
