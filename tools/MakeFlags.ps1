# Draws the language flags for WhoDidIt's title bar into Flags\<lang>.tga
# (maintainer tool, not in the player download: the .tga files are committed).
#
# Each flag is drawn 8 times bigger with smoothing, then shrunk to 64x32: a power
# of two, which WoW 1.12 needs. The game shows them at 3:2, so the drawing is
# stretched to fill 64x32 and comes out the right shape on screen.
# TGA: uncompressed 32-bit, rows bottom-up (header like RollFor's / DopingControl's
# textures, which the client loads).
#
#   powershell -ExecutionPolicy Bypass -File tools\MakeFlags.ps1 [-Preview flags.png]
param([string]$Preview)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "Flags"
if (-not (Test-Path $out)) { New-Item -ItemType Directory $out | Out-Null }

$W, $H, $SS = 64, 32, 8
function C([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
function Brush([string]$hex) { New-Object System.Drawing.SolidBrush (C $hex) }

# a canvas in the flag's own units (w x h), stretched over the whole texture
function New-Canvas([double]$fw, [double]$fh) {
    $bmp = [System.Drawing.Bitmap]::new([int]($W * $SS), [int]($H * $SS))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"
    $g.ScaleTransform(($W * $SS) / $fw, ($H * $SS) / $fh)
    return @{ bmp = $bmp; g = $g }
}
function Rect($g, [string]$col, [double]$x, [double]$y, [double]$w, [double]$h) {
    $g.FillRectangle((Brush $col), [single]$x, [single]$y, [single]$w, [single]$h)
}
function Stripes($g, [string[]]$cols, [double]$w, [double]$h, [switch]$Vertical) {
    for ($i = 0; $i -lt $cols.Count; $i++) {
        if ($Vertical) { Rect $g $cols[$i] ($i * $w / $cols.Count) 0 ($w / $cols.Count + 0.01) $h }
        else { Rect $g $cols[$i] 0 ($i * $h / $cols.Count) $w ($h / $cols.Count + 0.01) }
    }
}
# a five-pointed star: centre, outer radius, the angle its top point faces (degrees, 0 = up)
function Star($g, [string]$col, [double]$cx, [double]$cy, [double]$r, [double]$rot) {
    $pts = New-Object 'System.Drawing.PointF[]' 10
    for ($i = 0; $i -lt 10; $i++) {
        $rr = if ($i % 2 -eq 0) { $r } else { $r * 0.382 }
        $a = ($rot + $i * 36) * [math]::PI / 180
        $pts[$i] = New-Object System.Drawing.PointF ([single]($cx + $rr * [math]::Sin($a))), ([single]($cy - $rr * [math]::Cos($a)))
    }
    $g.FillPolygon((Brush $col), $pts)
}
function Line($g, [string]$col, [double]$width, [double]$x1, [double]$y1, [double]$x2, [double]$y2) {
    $p = New-Object System.Drawing.Pen (C $col), ([single]$width)
    $g.DrawLine($p, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
}

$flags = [ordered]@{}

# English: the Union Jack (60 x 30)
$flags["en"] = {
    $c = New-Canvas 60 30; $g = $c.g
    Rect $g "#012169" 0 0 60 30
    Line $g "#FFFFFF" 6 0 0 60 30; Line $g "#FFFFFF" 6 60 0 0 30
    # the red diagonals, offset clockwise (counterchanged) as on the real flag
    $g.SetClip((New-Object System.Drawing.RectangleF 0, 0, 30, 15)); Line $g "#C8102E" 2 0 1 30 16
    $g.SetClip((New-Object System.Drawing.RectangleF 30, 15, 30, 15)); Line $g "#C8102E" 2 30 14 60 29
    $g.SetClip((New-Object System.Drawing.RectangleF 30, 0, 30, 15)); Line $g "#C8102E" 2 61 0 31 15
    $g.SetClip((New-Object System.Drawing.RectangleF 0, 15, 30, 15)); Line $g "#C8102E" 2 29 15 -1 30
    $g.ResetClip()
    Rect $g "#FFFFFF" 25 0 10 30; Rect $g "#FFFFFF" 0 10 60 10
    Rect $g "#C8102E" 27 0 6 30; Rect $g "#C8102E" 0 12 60 6
    $c
}
$flags["de"] = { $c = New-Canvas 5 3; Stripes $c.g @("#000000", "#DD0000", "#FFCE00") 5 3; $c }
$flags["fr"] = { $c = New-Canvas 3 2; Stripes $c.g @("#0055A4", "#FFFFFF", "#EF4135") 3 2 -Vertical; $c }
$flags["es"] = {
    $c = New-Canvas 3 2; $g = $c.g
    Rect $g "#AA151B" 0 0 3 2; Rect $g "#F1BF00" 0 0.5 3 1
    $c
}
$flags["it"] = { $c = New-Canvas 3 2; Stripes $c.g @("#009246", "#F1F2F1", "#CE2B37") 3 2 -Vertical; $c }
# Portuguese (Brazil, WoW's ptBR): green, the yellow rhombus, the blue globe and its white band (20 x 14)
$flags["pt"] = {
    $c = New-Canvas 20 14; $g = $c.g
    Rect $g "#009C3B" 0 0 20 14
    $pts = @((New-Object System.Drawing.PointF 1.7, 7), (New-Object System.Drawing.PointF 10, 1.7),
        (New-Object System.Drawing.PointF 18.3, 7), (New-Object System.Drawing.PointF 10, 12.3))
    $g.FillPolygon((Brush "#FFDF00"), [System.Drawing.PointF[]]$pts)
    $g.FillEllipse((Brush "#002776"), [single]6.5, [single]3.5, [single]7, [single]7)
    $g.SetClip((New-Object System.Drawing.RectangleF 6.5, 3.5, 7, 7))
    $pen = New-Object System.Drawing.Pen (C "#FFFFFF"), ([single]0.55)
    $g.DrawArc($pen, [single]2.2, [single]5.6, [single]15, [single]12, [single]205, [single]110)
    $g.ResetClip()
    $c
}
$flags["ru"] = { $c = New-Canvas 3 2; Stripes $c.g @("#FFFFFF", "#0039A6", "#D52B1E") 3 2; $c }
# Chinese: the big star and four small ones, each turned to face it (30 x 20)
$flags["zh"] = {
    $c = New-Canvas 30 20; $g = $c.g
    Rect $g "#EE1C25" 0 0 30 20
    Star $g "#FFFF00" 5 5 3 0
    foreach ($s in @(@(10, 2), @(12, 4), @(12, 7), @(10, 9))) {
        $rot = [math]::Atan2(5 - $s[1], 5 - $s[0]) * 180 / [math]::PI + 90
        Star $g "#FFFF00" $s[0] $s[1] 1 $rot
    }
    $c
}
# Korean: the red / blue taegeuk on the diagonal and the four black trigrams (3 x 2)
$flags["ko"] = {
    $c = New-Canvas 3 2; $g = $c.g
    Rect $g "#FFFFFF" 0 0 3 2
    $ang = [math]::Atan2(2, 3) * 180 / [math]::PI
    $st = $g.Save()
    $g.TranslateTransform(1.5, 1); $g.RotateTransform([single]$ang)
    $R = 0.5
    # red above the diagonal, blue below; the red head on the left, the blue one on the right
    $g.FillPie((Brush "#CD2E3A"), [single](-$R), [single](-$R), [single](2 * $R), [single](2 * $R), [single]180, [single]180)
    $g.FillPie((Brush "#0047A0"), [single](-$R), [single](-$R), [single](2 * $R), [single](2 * $R), [single]0, [single]180)
    $g.FillEllipse((Brush "#CD2E3A"), [single](-$R), [single](-$R / 2), [single]$R, [single]$R)
    $g.FillEllipse((Brush "#0047A0"), [single]0, [single](-$R / 2), [single]$R, [single]$R)
    $g.Restore($st)
    # trigrams: bars across the diagonal; $broken lists which of the 3 bars have a gap
    $len = 0.5; $th = 0.085; $gap = 0.045
    $tri = @(
        @{ dx = -1; dy = -1; broken = @($false, $false, $false) },   # geon (upper left)
        @{ dx = 1; dy = -1; broken = @($true, $false, $true) },      # gam (upper right)
        @{ dx = -1; dy = 1; broken = @($false, $true, $false) },     # ri (lower left)
        @{ dx = 1; dy = 1; broken = @($true, $true, $true) }         # gon (lower right)
    )
    $d = 0.95
    foreach ($tg in $tri) {
        $ux = (3 / [math]::Sqrt(13)) * $tg.dx; $uy = (2 / [math]::Sqrt(13)) * $tg.dy
        $cx = 1.5 + $ux * $d; $cy = 1 + $uy * $d
        $st = $g.Save()
        $g.TranslateTransform([single]$cx, [single]$cy)
        $g.RotateTransform([single]([math]::Atan2($uy, $ux) * 180 / [math]::PI + 90))
        for ($i = 0; $i -lt 3; $i++) {
            $y = ($i - 1) * ($th + $gap) - $th / 2
            if ($tg.broken[$i]) {
                Rect $g "#000000" (-$len / 2) $y (($len - $gap) / 2) $th
                Rect $g "#000000" ($gap / 2) $y (($len - $gap) / 2) $th
            } else { Rect $g "#000000" (-$len / 2) $y $len $th }
        }
        $g.Restore($st)
    }
    $c
}

function Write-Tga([System.Drawing.Bitmap]$small, [string]$path) {
    $bytes = New-Object byte[] (18 + $W * $H * 4)
    $bytes[2] = 2; $bytes[12] = $W; $bytes[14] = $H; $bytes[16] = 32; $bytes[17] = 8
    $o = 18
    for ($y = $H - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $W; $x++) {
            $p = $small.GetPixel($x, $y)
            $bytes[$o] = $p.B; $bytes[$o + 1] = $p.G; $bytes[$o + 2] = $p.R; $bytes[$o + 3] = 255
            $o += 4
        }
    }
    [IO.File]::WriteAllBytes($path, $bytes)
}

$sheet = if ($Preview) { [System.Drawing.Bitmap]::new([int](($W * 2 + 8) * $flags.Count), [int]($H * 2)) } else { $null }
$i = 0
foreach ($k in $flags.Keys) {
    $c = & $flags[$k]
    # shrink by averaging each 8x8 block (sharper stripe edges than bicubic)
    $small = [System.Drawing.Bitmap]::new([int]$W, [int]$H)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $c.bmp.Width, $c.bmp.Height
    $data = $c.bmp.LockBits($rect, "ReadOnly", "Format32bppArgb")
    $buf = New-Object byte[] ($data.Stride * $c.bmp.Height)
    [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $buf.Length)
    $c.bmp.UnlockBits($data)
    for ($y = 0; $y -lt $H; $y++) {
        for ($x = 0; $x -lt $W; $x++) {
            $r = 0; $gg = 0; $b = 0
            for ($j = 0; $j -lt $SS; $j++) {
                $o = ($y * $SS + $j) * $data.Stride + $x * $SS * 4
                for ($k2 = 0; $k2 -lt $SS; $k2++) { $b += $buf[$o]; $gg += $buf[$o + 1]; $r += $buf[$o + 2]; $o += 4 }
            }
            $n = $SS * $SS
            $small.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, [int]($r / $n), [int]($gg / $n), [int]($b / $n)))
        }
    }
    Write-Tga $small (Join-Path $out "$k.tga")
    if ($sheet) {
        # the preview at the shape the game shows (3:2)
        $pg = [System.Drawing.Graphics]::FromImage($sheet)
        $pg.InterpolationMode = "HighQualityBicubic"
        $pg.DrawImage($small, (New-Object System.Drawing.Rectangle ($i * ($W * 2 + 8)), 0, 96, 64))
    }
    "Flags\$k.tga"
    $i++
}
if ($sheet) { $sheet.Save($Preview, [System.Drawing.Imaging.ImageFormat]::Png); "preview: $Preview" }
