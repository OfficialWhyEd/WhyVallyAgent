# Calcola KAST esatto e delta danni, per GiocatoreA e per tutti i giocatori delle stesse lobby.
$base  = $PSScriptRoot
$cfg   = Get-Content "$base\config.json" -Raw | ConvertFrom-Json
$PUUID = $cfg.puuid
$TRADE = 4000

$acc = @{}
function A($p) {
    if (-not $acc[$p]) {
        $acc[$p] = [pscustomobject]@{ round=0; kast=0; k=0; a=0; s=0; t=0; inflitto=0; subito=0 }
    }
    $acc[$p]
}

$nComp = 0
foreach ($f in (Get-ChildItem "$base\partite\*.json")) {
    $m = (Get-Content $f.FullName -Raw | ConvertFrom-Json).data
    if ($m.metadata.mode -ne 'Competitive') { continue }
    $nComp++

    $team = @{}
    foreach ($pl in $m.players.all_players) { $team[$pl.puuid] = $pl.team }

    for ($ri = 0; $ri -lt $m.rounds.Count; $ri++) {
        $r = $m.rounds[$ri]
        $killsRound = @($m.kills | Where-Object { $_.round -eq $ri })

        foreach ($ps in $r.player_stats) {
            $p = $ps.player_puuid
            $s = A $p
            $s.round++
            $s.inflitto += [int]$ps.damage

            # danno subito: somma dei damage_events di TUTTI diretti a lui
            foreach ($altro in $r.player_stats) {
                foreach ($de in $altro.damage_events) {
                    if ($de.receiver_puuid -eq $p) { $s.subito += [int]$de.damage }
                }
            }

            # --- componenti KAST ---
            $haK = ([int]$ps.kills -gt 0)
            $haA = $false
            foreach ($kk in $killsRound) {
                if ($kk.assistants -and (@($kk.assistants | Where-Object { $_.assistant_puuid -eq $p }).Count -gt 0)) { $haA = $true; break }
            }
            $miaMorte = @($killsRound | Where-Object { $_.victim_puuid -eq $p })
            $haS = ($miaMorte.Count -eq 0)
            $haT = $false
            if (-not $haS) {
                $md = $miaMorte[0]
                $v = @($killsRound | Where-Object {
                    $_.victim_puuid -eq $md.killer_puuid -and
                    $_.kill_time_in_round -gt $md.kill_time_in_round -and
                    ($_.kill_time_in_round - $md.kill_time_in_round) -le $TRADE -and
                    $team[$_.killer_puuid] -eq $team[$p]
                })
                $haT = ($v.Count -gt 0)
            }

            if ($haK) { $s.k++ }
            if ($haA) { $s.a++ }
            if ($haS) { $s.s++ }
            if ($haT) { $s.t++ }
            if ($haK -or $haA -or $haS -or $haT) { $s.kast++ }
        }
    }
}

$io = $acc[$PUUID]
$altri = @($acc.Keys | Where-Object { $_ -ne $PUUID -and $acc[$_].round -ge 20 } | ForEach-Object { $acc[$_] })

$mioKast = $io.kast / $io.round * 100
$medKast = ($altri | ForEach-Object { $_.kast / $_.round * 100 } | Measure-Object -Average).Average
$mioInf  = $io.inflitto / $io.round
$mioSub  = $io.subito   / $io.round
$medInf  = ($altri | ForEach-Object { $_.inflitto / $_.round } | Measure-Object -Average).Average
$medSub  = ($altri | ForEach-Object { $_.subito   / $_.round } | Measure-Object -Average).Average
$mioDelta = $mioInf - $mioSub
$medDelta = ($altri | ForEach-Object { ($_.inflitto - $_.subito) / $_.round } | Measure-Object -Average).Average
$pcKast  = [math]::Round((@($altri | Where-Object { ($_.kast/$_.round*100) -lt $mioKast }).Count / $altri.Count) * 100)
$pcDelta = [math]::Round((@($altri | Where-Object { (($_.inflitto-$_.subito)/$_.round) -lt $mioDelta }).Count / $altri.Count) * 100)

Write-Host ""
Write-Host "=================================================================="
Write-Host "  KAST E DELTA DANNI  -  $nComp competitive, $($altri.Count) confronti"
Write-Host "=================================================================="
Write-Host ""
Write-Host ("  Round giocati        : {0}" -f $io.round)
Write-Host ""
Write-Host ("  KAST                 : {0,6:N1}%   lobby {1,6:N1}%   percentile {2}o" -f $mioKast, $medKast, $pcKast)
Write-Host ("     round con uccisione : {0,5:N1}%" -f ($io.k/$io.round*100))
Write-Host ("     round con assist    : {0,5:N1}%" -f ($io.a/$io.round*100))
Write-Host ("     round sopravvissuti : {0,5:N1}%" -f ($io.s/$io.round*100))
Write-Host ("     morti ma vendicato  : {0,5:N1}%" -f ($io.t/$io.round*100))
Write-Host ""
Write-Host ("  Danno inflitto/round : {0,6:N1}    lobby {1,6:N1}" -f $mioInf, $medInf)
Write-Host ("  Danno subito/round   : {0,6:N1}    lobby {1,6:N1}" -f $mioSub, $medSub)
Write-Host ("  DELTA DANNI          : {0,6:N1}    lobby {1,6:N1}   percentile {2}o" -f $mioDelta, $medDelta, $pcDelta)
Write-Host ""

[ordered]@{
    round = $io.round
    kast = @{ mio=[math]::Round($mioKast,1); lobby=[math]::Round($medKast,1); percentile=$pcKast
              conUccisione=[math]::Round($io.k/$io.round*100,1); conAssist=[math]::Round($io.a/$io.round*100,1)
              sopravvissuto=[math]::Round($io.s/$io.round*100,1); vendicato=[math]::Round($io.t/$io.round*100,1) }
    danno = @{ inflitto=[math]::Round($mioInf,1); subito=[math]::Round($mioSub,1); delta=[math]::Round($mioDelta,1)
               lobbyInflitto=[math]::Round($medInf,1); lobbySubito=[math]::Round($medSub,1); lobbyDelta=[math]::Round($medDelta,1)
               percentile=$pcDelta }
} | ConvertTo-Json -Depth 6 | Set-Content "$base\kast.json" -Encoding utf8
Write-Host "Salvato in $base\kast.json"
