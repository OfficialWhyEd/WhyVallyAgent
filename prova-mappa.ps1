# Compone minimappa + punti per verificare visivamente l'allineamento.
param([string]$Mappa = 'Split')
Add-Type -AssemblyName System.Drawing

$base = $PSScriptRoot
$pos  = Get-Content "$base\posizioni.json" -Raw | ConvertFrom-Json
$dati = $pos.$Mappa
if (-not $dati) { Write-Host "mappa non trovata"; return }

$img = [System.Drawing.Image]::FromFile("$base\mappe\$Mappa.png")
$W = 700; $H = 700
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([System.Drawing.Color]::FromArgb(255,18,18,20))
$g.DrawImage($img, 0, 0, $W, $H)

$rosso = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(215,220,45,30))
$verde = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(215,40,190,140))

foreach ($p in $dati.morti) {
    $x = [double]$p[0] * $W; $y = [double]$p[1] * $H
    $g.FillEllipse($rosso, [single]($x-4), [single]($y-4), 8, 8)
}
foreach ($p in $dati.uccisioni) {
    $x = [double]$p[0] * $W; $y = [double]$p[1] * $H
    $g.FillEllipse($verde, [single]($x-4), [single]($y-4), 8, 8)
}

$fnt = New-Object System.Drawing.Font('Consolas', 14, [System.Drawing.FontStyle]::Bold)
$bianco = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$g.DrawString("$Mappa  -  rosso = tue morti ($($dati.morti.Count)), verde = tue uccisioni ($($dati.uccisioni.Count))", $fnt, $bianco, 10, 10)

$out = "$base\mappe\prova_$Mappa.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $img.Dispose()
Write-Host "salvato: $out"
