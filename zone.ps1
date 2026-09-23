# Trova le zone in cui muore di piu' e genera le mappe finali (PNG trasparenti).
Add-Type -AssemblyName System.Drawing
$base = $PSScriptRoot
$pos  = Get-Content "$base\posizioni.json" -Raw | ConvertFrom-Json
$dest = "$base\mappe\finali"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$GRIGLIA = 7        # divide la mappa in 7x7 celle
$risultati = @()

foreach ($nome in @('Split','Summit','Lotus','Haven','Ascent','Sunset','Breeze')) {
    $d = $pos.$nome
    if (-not $d -or -not (Test-Path "$base\mappe\$nome.png")) { continue }

    $morti = @($d.morti); $ucc = @($d.uccisioni)
    if ($morti.Count -eq 0) { continue }

    # ---- conteggio per cella ----
    $celle = @{}
    foreach ($p in $morti) {
        $cx = [math]::Min($GRIGLIA-1, [math]::Floor([double]$p[0] * $GRIGLIA))
        $cy = [math]::Min($GRIGLIA-1, [math]::Floor([double]$p[1] * $GRIGLIA))
        $k = "$cx,$cy"
        if (-not $celle[$k]) { $celle[$k] = @{ m=0; u=0; cx=$cx; cy=$cy } }
        $celle[$k].m++
    }
    foreach ($p in $ucc) {
        $cx = [math]::Min($GRIGLIA-1, [math]::Floor([double]$p[0] * $GRIGLIA))
        $cy = [math]::Min($GRIGLIA-1, [math]::Floor([double]$p[1] * $GRIGLIA))
        $k = "$cx,$cy"
        if (-not $celle[$k]) { $celle[$k] = @{ m=0; u=0; cx=$cx; cy=$cy } }
        $celle[$k].u++
    }

    $peggiori = @($celle.Values | Where-Object { $_.m -ge 4 } | Sort-Object { $_.u - $_.m } | Select-Object -First 3)

    $risultati += [pscustomobject]@{
        mappa = $nome; partite = $d.partite
        morti = $morti.Count; uccisioni = $ucc.Count
        zone = $peggiori
    }

    # ---- immagine ----
    $img = [System.Drawing.Image]::FromFile("$base\mappe\$nome.png")
    $S = 620
    $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.DrawImage($img, 0, 0, $S, $S)

    # evidenzia le zone peggiori
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210,190,58,36), 2.5)
    $pen.DashStyle = 'Dash'
    $lato = $S / $GRIGLIA
    $i = 1
    $fnt = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $brNum = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235,190,58,36))
    foreach ($z in $peggiori) {
        $g.DrawRectangle($pen, [single]($z.cx*$lato), [single]($z.cy*$lato), [single]$lato, [single]$lato)
        $g.DrawString("$i", $fnt, $brNum, [single]($z.cx*$lato + 5), [single]($z.cy*$lato + 3))
        $i++
    }

    $brM = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(225,190,58,36))
    $brU = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(225,44,76,116))
    $penB = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150,255,255,255), 1)
    foreach ($p in $morti) {
        $x = [double]$p[0]*$S; $y = [double]$p[1]*$S
        $g.FillEllipse($brM, [single]($x-4.5), [single]($y-4.5), 9, 9)
    }
    foreach ($p in $ucc) {
        $x = [double]$p[0]*$S; $y = [double]$p[1]*$S
        $g.FillEllipse($brU, [single]($x-4.5), [single]($y-4.5), 9, 9)
        $g.DrawEllipse($penB, [single]($x-4.5), [single]($y-4.5), 9, 9)
    }

    $bmp.Save("$dest\$nome.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose(); $img.Dispose()
}

Write-Host ""
Write-Host "=================================================================="
Write-Host "  ZONE PEGGIORI PER MAPPA  (griglia $GRIGLIA x $GRIGLIA)"
Write-Host "=================================================================="
foreach ($r in ($risultati | Sort-Object partite -Descending)) {
    $rap = if ($r.morti -gt 0) { $r.uccisioni / $r.morti } else { 0 }
    Write-Host ""
    Write-Host ("  {0}  ({1} partite)   {2} morti / {3} uccisioni   rapporto {4:N2}" -f $r.mappa, $r.partite, $r.morti, $r.uccisioni, $rap)
    $i = 1
    foreach ($z in $r.zone) {
        $col = @('sinistra','centro-sin','centro','centro-des','destra')
        $rig = @('alto','alto-centro','centro','basso-centro','basso')
        $cx = [int][math]::Round($z.cx / ($GRIGLIA-1) * 4)
        $cy = [int][math]::Round($z.cy / ($GRIGLIA-1) * 4)
        Write-Host ("    zona {0}: {1,3} morti, {2,2} uccisioni   settore {3} / {4}" -f $i, $z.m, $z.u, $rig[$cy], $col[$cx])
        $i++
    }
}

$risultati | ConvertTo-Json -Depth 6 | Set-Content "$base\zone.json" -Encoding utf8
Write-Host ""
Write-Host "Mappe finali in $dest"
