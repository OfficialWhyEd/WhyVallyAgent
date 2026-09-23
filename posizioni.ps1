# Converte le coordinate di gioco in spazio radar (0-1) e analizza i duelli per distanza.
$base  = $PSScriptRoot
$cfg   = Get-Content "$base\config.json" -Raw | ConvertFrom-Json
$PUUID = $cfg.puuid
$mappe = (Get-Content "$base\raw\mappe.json" -Raw | ConvertFrom-Json).data

$conv = @{}
foreach ($m in $mappe) {
    if ($null -ne $m.xMultiplier -and $m.xMultiplier -ne 0) {
        $conv[$m.displayName] = @{
            xm=[double]$m.xMultiplier; ym=[double]$m.yMultiplier
            xa=[double]$m.xScalarToAdd; ya=[double]$m.yScalarToAdd
            icona=$m.displayIcon
        }
    }
}

function Radar($mapName, $loc) {
    $c = $conv[$mapName]
    if (-not $c -or $null -eq $loc) { return $null }
    # Verificato sovrapponendo i punti alla minimappa reale (non solo controllando
    # che cadano dentro il riquadro): in HenrikDev gli assi sono invertiti rispetto
    # ai nomi dei moltiplicatori, E la coppia va scambiata di nuovo per il disegno.
    #   orizzontale = y * xMultiplier + xScalarToAdd
    #   verticale   = x * yMultiplier + yScalarToAdd
    $oriz = [double]$loc.y * $c.xm + $c.xa
    $vert = [double]$loc.x * $c.ym + $c.ya
    return @{ u = $oriz; v = $vert }
}

$perMappa = @{}
$duelli   = @()     # ogni scontro che lo riguarda: distanza + esito
$duelliAltri = @()

foreach ($f in (Get-ChildItem "$base\partite\*.json")) {
    $m = (Get-Content $f.FullName -Raw | ConvertFrom-Json).data
    if ($m.metadata.mode -ne 'Competitive') { continue }
    $nome = $m.metadata.map
    if (-not $conv[$nome]) { continue }
    if (-not $perMappa[$nome]) { $perMappa[$nome] = @{ morti=@(); uccisioni=@(); mortiLobby=@(); partite=0 } }
    $perMappa[$nome].partite++

    foreach ($k in $m.kills) {
        $posU = ($k.player_locations_on_kill | Where-Object { $_.player_puuid -eq $k.killer_puuid } | Select-Object -First 1).location
        $d = $null
        if ($posU -and $k.victim_death_location) {
            $dx = [double]$posU.x - [double]$k.victim_death_location.x
            $dy = [double]$posU.y - [double]$k.victim_death_location.y
            $d = [math]::Sqrt($dx*$dx + $dy*$dy)
        }

        if ($k.victim_puuid -eq $PUUID) {
            $r = Radar $nome $k.victim_death_location
            if ($r) { $perMappa[$nome].morti += ,@($r.u, $r.v) }
            if ($d) { $duelli += [pscustomobject]@{ dist=$d; vinto=$false; arma=$k.damage_weapon_name } }
        }
        elseif ($k.killer_puuid -eq $PUUID) {
            $r = Radar $nome $k.victim_death_location
            if ($r) { $perMappa[$nome].uccisioni += ,@($r.u, $r.v) }
            if ($d) { $duelli += [pscustomobject]@{ dist=$d; vinto=$true; arma=$k.damage_weapon_name } }
        }
        else {
            $r = Radar $nome $k.victim_death_location
            if ($r) { $perMappa[$nome].mortiLobby += ,@($r.u, $r.v) }
            if ($d) { $duelliAltri += [pscustomobject]@{ dist=$d } }
        }
    }
}

Write-Host ""
Write-Host "=== VERIFICA CONVERSIONE (quanti punti cadono dentro 0-1) ==="
foreach ($n in ($perMappa.Keys | Sort-Object)) {
    $tutti = @($perMappa[$n].morti) + @($perMappa[$n].uccisioni)
    if ($tutti.Count -eq 0) { continue }
    $dentro = @($tutti | Where-Object { $_[0] -ge 0 -and $_[0] -le 1 -and $_[1] -ge 0 -and $_[1] -le 1 }).Count
    Write-Host ("  {0,-9} {1,4} punti, {2,5:N1}% dentro la mappa  ({3} partite)" -f $n, $tutti.Count, ($dentro/$tutti.Count*100), $perMappa[$n].partite)
}

Write-Host ""
Write-Host "=== DUELLI PER DISTANZA ==="
Write-Host "  (distanza in unita' di gioco; ~100 unita' = 1 metro)"
$fasce = @(
  @{n='corpo a corpo'; min=0;    max=600},
  @{n='corta';         min=600;  max=1200},
  @{n='media';         min=1200; max=2000},
  @{n='lunga';         min=2000; max=3200},
  @{n='molto lunga';   min=3200; max=99999}
)
Write-Host ""
Write-Host ("  {0,-15} {1,7} {2,8} {3,9}   {4}" -f 'FASCIA','SCONTRI','VINTI','QUOTA','')
foreach ($fa in $fasce) {
    $s = @($duelli | Where-Object { $_.dist -ge $fa.min -and $_.dist -lt $fa.max })
    if ($s.Count -eq 0) { continue }
    $v = @($s | Where-Object { $_.vinto }).Count
    $q = $v / $s.Count * 100
    $barra = '#' * [int]($q/2)
    Write-Host ("  {0,-15} {1,7} {2,8} {3,8:N1}%   {4}" -f $fa.n, $s.Count, $v, $q, $barra)
}
$tot = @($duelli)
Write-Host ("  {0,-15} {1,7} {2,8} {3,8:N1}%" -f 'TOTALE', $tot.Count, @($tot|Where-Object{$_.vinto}).Count, (@($tot|Where-Object{$_.vinto}).Count/$tot.Count*100))

Write-Host ""
Write-Host "=== DISTANZA MEDIA DEGLI SCONTRI ==="
Write-Host ("  tuoi scontri  : {0,7:N0}" -f (($duelli | Measure-Object dist -Average).Average))
Write-Host ("  quelli altrui : {0,7:N0}" -f (($duelliAltri | Measure-Object dist -Average).Average))
Write-Host ("  vinti da te   : {0,7:N0}" -f ((@($duelli|Where-Object{$_.vinto}) | Measure-Object dist -Average).Average))
Write-Host ("  persi da te   : {0,7:N0}" -f ((@($duelli|Where-Object{-not $_.vinto}) | Measure-Object dist -Average).Average))

Write-Host ""
Write-Host "=== ARMI CHE TI UCCIDONO ==="
$morti = @($duelli | Where-Object { -not $_.vinto })
$morti | Group-Object arma | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object {
    Write-Host ("  {0,-16} {1,4}  {2,5:N1}%" -f $_.Name, $_.Count, ($_.Count/$morti.Count*100))
}

# salva le posizioni per il disegno
$out = @{}
foreach ($n in $perMappa.Keys) {
    $out[$n] = @{
        partite = $perMappa[$n].partite
        morti = $perMappa[$n].morti
        uccisioni = $perMappa[$n].uccisioni
        mortiLobby = $perMappa[$n].mortiLobby
        icona = $conv[$n].icona
    }
}
$out | ConvertTo-Json -Depth 6 -Compress | Set-Content "$base\posizioni.json" -Encoding utf8
Write-Host ""
Write-Host "Posizioni salvate in $base\posizioni.json"
