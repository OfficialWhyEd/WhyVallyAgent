# Analisi critica: mette alla prova le conclusioni precedenti invece di confermarle.
#  1. round a impatto zero (0 danno, 0 uccisioni, 0 assist) - la metrica che KAST nasconde
#  2. il "+24,5 punti quando apre" e' davvero suo, o vale per chiunque?
#  3. intervalli di confidenza sui tassi di vittoria per agente
#  4. attacco/difesa: lo scarto e' significativo o rumore?
#  5. deathmatch: mira pura, senza posizionamento ne' compagni
#  6. rango reale degli avversari
#  7. tendenza temporale
$base  = $PSScriptRoot
$cfg   = Get-Content "$base\config.json" -Raw | ConvertFrom-Json
$PUUID = $cfg.puuid

function Wilson($succ, $tot) {
    if ($tot -eq 0) { return @{ basso=0; alto=0 } }
    $z = 1.96; $p = $succ / $tot
    $d = 1 + $z*$z/$tot
    $c = ($p + $z*$z/(2*$tot)) / $d
    $s = $z * [math]::Sqrt(($p*(1-$p) + $z*$z/(4*$tot))/$tot) / $d
    return @{ basso=[math]::Max([double]0,($c-$s))*100; alto=[math]::Min([double]1,($c+$s))*100 }
}

$impatto = @{}   # puuid -> conteggi round
$fbStat  = @{}   # puuid -> round aperti / vinti, e riferimento
$files   = Get-ChildItem "$base\partite\*.json"

$dmStat = [pscustomobject]@{ partite=0; kills=0; deaths=0; hs=0; bs=0; ls=0 }
$ranghi = @{}
$perPartita = @()

foreach ($f in $files) {
    $m = (Get-Content $f.FullName -Raw | ConvertFrom-Json).data
    $me = $m.players.all_players | Where-Object { $_.puuid -eq $PUUID }
    if (-not $me) { continue }

    # ---- deathmatch: mira isolata ----
    if ($m.metadata.mode -eq 'Deathmatch') {
        $dmStat.partite++
        $dmStat.kills  += [int]$me.stats.kills
        $dmStat.deaths += [int]$me.stats.deaths
        $dmStat.hs += [int]$me.stats.headshots; $dmStat.bs += [int]$me.stats.bodyshots; $dmStat.ls += [int]$me.stats.legshots
        continue
    }
    if ($m.metadata.mode -ne 'Competitive') { continue }

    foreach ($pl in $m.players.all_players) {
        $t = $pl.currenttier_patched
        if ($t) { $ranghi[$t] = [int]$ranghi[$t] + 1 }
    }

    $team = @{}
    foreach ($pl in $m.players.all_players) { $team[$pl.puuid] = $pl.team }
    $mioTeam = $team[$PUUID]

    for ($ri = 0; $ri -lt $m.rounds.Count; $ri++) {
        $r  = $m.rounds[$ri]
        $kr = @($m.kills | Where-Object { $_.round -eq $ri })
        $vincitore = $r.winning_team

        foreach ($ps in $r.player_stats) {
            $p = $ps.player_puuid
            if (-not $impatto[$p]) { $impatto[$p] = [pscustomobject]@{ round=0; zero=0; soloDanno=0; conKill=0 } }
            $s = $impatto[$p]
            $s.round++
            $ass = $false
            foreach ($kk in $kr) { if ($kk.assistants -and (@($kk.assistants | Where-Object { $_.assistant_puuid -eq $p }).Count -gt 0)) { $ass = $true; break } }
            $dmg = [int]$ps.damage; $kil = [int]$ps.kills
            if ($kil -gt 0) { $s.conKill++ }
            elseif ($dmg -gt 0 -or $ass) { $s.soloDanno++ }
            else { $s.zero++ }
        }

        # ---- primo duello, per ogni giocatore ----
        if ($kr.Count -gt 0) {
            $primo = $kr | Sort-Object kill_time_in_round | Select-Object -First 1
            foreach ($pl in $m.players.all_players) {
                $p = $pl.puuid
                if (-not $fbStat[$p]) { $fbStat[$p] = [pscustomobject]@{ apre=0; apreVinti=0; base=0; baseVinti=0 } }
                $vinto = ($vincitore -eq $team[$p])
                if ($primo.killer_puuid -eq $p) { $fbStat[$p].apre++; if ($vinto) { $fbStat[$p].apreVinti++ } }
                elseif ($primo.victim_puuid -ne $p) { $fbStat[$p].base++; if ($vinto) { $fbStat[$p].baseVinti++ } }
            }
        }
    }

    $mia = if ($mioTeam -eq 'Red') { $m.teams.red } else { $m.teams.blue }
    $perPartita += [pscustomobject]@{
        data = [datetimeoffset]::FromUnixTimeSeconds($m.metadata.game_start).LocalDateTime
        vinta = [bool]$mia.has_won
        kills = [int]$me.stats.kills
        deaths = [int]$me.stats.deaths
        agente = $me.character
    }
}

$io = $impatto[$PUUID]
$altri = @($impatto.Keys | Where-Object { $_ -ne $PUUID -and $impatto[$_].round -ge 20 } | ForEach-Object { $impatto[$_] })

Write-Host ""
Write-Host "=================================================================="
Write-Host "  1. ROUND A IMPATTO ZERO"
Write-Host "     (nessuna uccisione, nessun assist, ZERO danno inflitto)"
Write-Host "=================================================================="
$mioZero = $io.zero / $io.round * 100
$medZero = ($altri | ForEach-Object { $_.zero / $_.round * 100 } | Measure-Object -Average).Average
$pcZero  = [math]::Round((@($altri | Where-Object { ($_.zero/$_.round*100) -gt $mioZero }).Count / $altri.Count)*100)
Write-Host ("  Tu    : {0,4} round su {1} = {2,5:N1}%" -f $io.zero, $io.round, $mioZero)
Write-Host ("  Lobby : {0,5:N1}%" -f $medZero)
Write-Host ("  Percentile: {0}o  (quanti stanno peggio di te)" -f $pcZero)
Write-Host ("  Round con danno ma senza uccisione : {0,5:N1}%" -f ($io.soloDanno/$io.round*100))
Write-Host ("  Round con almeno un'uccisione      : {0,5:N1}%" -f ($io.conKill/$io.round*100))

Write-Host ""
Write-Host "=================================================================="
Write-Host "  2. IL '+24,5 PUNTI QUANDO APRE' REGGE?"
Write-Host "     confronto con lo stesso calcolo su tutti gli altri"
Write-Host "=================================================================="
$mioFb = $fbStat[$PUUID]
$mioGuad = ($mioFb.apreVinti/[math]::Max($mioFb.apre,1)*100) - ($mioFb.baseVinti/[math]::Max($mioFb.base,1)*100)
$guadagni = @()
foreach ($p in $fbStat.Keys) {
    if ($p -eq $PUUID) { continue }
    $s = $fbStat[$p]
    if ($s.apre -lt 10 -or $s.base -lt 30) { continue }
    $guadagni += ($s.apreVinti/$s.apre*100) - ($s.baseVinti/$s.base*100)
}
$medGuad = ($guadagni | Measure-Object -Average).Average
$ci = Wilson $mioFb.apreVinti $mioFb.apre
Write-Host ("  Tuoi round aperti : {0}   vinti {1,5:N1}%" -f $mioFb.apre, ($mioFb.apreVinti/[math]::Max($mioFb.apre,1)*100))
Write-Host ("  Intervallo di confidenza 95% : da {0:N1}% a {1:N1}%   <-- AMPIO" -f $ci.basso, $ci.alto)
Write-Host ("  Tuo guadagno rispetto al tuo riferimento : {0,6:N1} punti" -f $mioGuad)
Write-Host ("  Stesso guadagno per gli altri ({0} giocatori): {1,6:N1} punti" -f $guadagni.Count, $medGuad)
Write-Host ("  DIFFERENZA REALE : {0,6:N1} punti" -f ($mioGuad - $medGuad))

Write-Host ""
Write-Host "=================================================================="
Write-Host "  3. AGENTI: I TASSI DI VITTORIA SONO DISTINGUIBILI?"
Write-Host "=================================================================="
$comp = $perPartita
foreach ($g in ($comp | Group-Object agente | Sort-Object Count -Descending)) {
    $v = @($g.Group | Where-Object { $_.vinta }).Count
    $w = Wilson $v $g.Count
    Write-Host ("  {0,-9} {1,2}p  {2,5:N0}%   intervallo 95%: {3,5:N0}% - {4,5:N0}%   ampiezza {5,3:N0} punti" -f $g.Name, $g.Count, ($v/$g.Count*100), $w.basso, $w.alto, ($w.alto-$w.basso))
}
$vTot = @($comp | Where-Object { $_.vinta }).Count
$wTot = Wilson $vTot $comp.Count
Write-Host ("  {0,-9} {1,2}p  {2,5:N0}%   intervallo 95%: {3,5:N0}% - {4,5:N0}%" -f 'TOTALE', $comp.Count, ($vTot/$comp.Count*100), $wTot.basso, $wTot.alto)

Write-Host ""
Write-Host "=================================================================="
Write-Host "  4. DEATHMATCH: MIRA SENZA POSIZIONAMENTO"
Write-Host "=================================================================="
$colpi = $dmStat.hs + $dmStat.bs + $dmStat.ls
Write-Host ("  Partite : {0}" -f $dmStat.partite)
Write-Host ("  K/D     : {0,5:N2}   ({1} uccisioni / {2} morti)" -f ($dmStat.kills/[math]::Max($dmStat.deaths,1)), $dmStat.kills, $dmStat.deaths)
Write-Host ("  Headshot: {0,5:N1}%  ({1} testa / {2} corpo / {3} gambe)" -f ($dmStat.hs/[math]::Max($colpi,1)*100), $dmStat.hs, $dmStat.bs, $dmStat.ls)

Write-Host ""
Write-Host "=================================================================="
Write-Host "  5. CHI SONO DAVVERO GLI AVVERSARI"
Write-Host "=================================================================="
$tot = ($ranghi.Values | Measure-Object -Sum).Sum
foreach ($e in ($ranghi.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 12)) {
    Write-Host ("  {0,-16} {1,4}  {2,5:N1}%" -f $e.Key, $e.Value, ($e.Value/$tot*100))
}

Write-Host ""
Write-Host "=================================================================="
Write-Host "  6. STA MIGLIORANDO? prime 12 contro ultime 12"
Write-Host "=================================================================="
$ord = @($perPartita | Sort-Object data)
$primaMeta = $ord[0..([int]($ord.Count/2)-1)]
$secMeta   = $ord[([int]($ord.Count/2))..($ord.Count-1)]
foreach ($blocco in @(@{n='Prime 12';d=$primaMeta}, @{n='Ultime 12';d=$secMeta})) {
    $d = $blocco.d
    $v = @($d | Where-Object { $_.vinta }).Count
    $k = ($d | Measure-Object kills -Sum).Sum
    $m = ($d | Measure-Object deaths -Sum).Sum
    Write-Host ("  {0,-10} {1,2}p  {2,5:N0}% vinte   K/D {3,5:N2}   ({4}K / {5}D)" -f $blocco.n, $d.Count, ($v/$d.Count*100), ($k/[math]::Max($m,1)), $k, $m)
}
Write-Host ""

