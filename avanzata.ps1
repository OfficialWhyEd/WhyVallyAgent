# Analisi avanzata: usa i dati posizionali e temporali che i tracker ignorano.
#  - isolamento: quanto sei lontano dal compagno piu' vicino quando muori
#  - distanza dei duelli
#  - scambio (trade): quando muori, un compagno vendica entro 4 secondi?
#  - momento della morte dentro il round
#  - impatto reale del primo sangue sul risultato del round
#  - attacco contro difesa
# Ogni valore e' confrontato con la media degli altri 9 giocatori delle stesse lobby.
$base  = $PSScriptRoot
$cfg   = Get-Content "$base\config.json" -Raw | ConvertFrom-Json
$PUUID = $cfg.puuid
$FINESTRA_TRADE = 4000   # millisecondi

function Dist($a, $b) {
    if (-not $a -or -not $b) { return $null }
    $dx = [double]$a.x - [double]$b.x
    $dy = [double]$a.y - [double]$b.y
    return [math]::Sqrt($dx*$dx + $dy*$dy)
}

$stat = @{}
function S($p) {
    if (-not $stat[$p]) {
        $stat[$p] = [pscustomobject]@{
            morti=0; isolamentoTot=0.0; isolamentoN=0
            distDuelloTot=0.0; distDuelloN=0
            mortiVendicate=0
            tempoMorteTot=0.0; tempoMorteN=0
            uccisioni=0; distUccTot=0.0; distUccN=0
        }
    }
    return $stat[$p]
}

# statistiche solo mie, non confrontabili
$roundConFB   = 0; $roundConFBvinti = 0
$roundConFD   = 0; $roundConFDvinti = 0
$roundNeutri  = 0; $roundNeutriVinti = 0
$attaccoR=0; $attaccoV=0; $difesaR=0; $difesaV=0
$attaccoK=0; $attaccoD=0; $difesaK=0; $difesaD=0
$mortePerFascia = @{ 'primi 15s'=0; '15-30s'=0; '30-60s'=0; 'oltre 60s'=0 }
$multiKill = @{ 0=0; 1=0; 2=0; 3=0; 4=0; 5=0 }
$nComp = 0

foreach ($f in (Get-ChildItem "$base\partite\*.json")) {
    $m = (Get-Content $f.FullName -Raw | ConvertFrom-Json).data
    if ($m.metadata.mode -ne 'Competitive') { continue }
    $nComp++

    $squadraDi = @{}
    foreach ($pl in $m.players.all_players) { $squadraDi[$pl.puuid] = $pl.team }
    $mioTeam = $squadraDi[$PUUID]

    $kills = @($m.kills | Sort-Object round, kill_time_in_round)

    foreach ($k in $kills) {
        # ---- distanza del duello (posizione uccisore ricavata dalle posizioni tracciate) ----
        $posUccisore = ($k.player_locations_on_kill | Where-Object { $_.player_puuid -eq $k.killer_puuid } | Select-Object -First 1).location
        $d = Dist $posUccisore $k.victim_death_location

        if ($k.killer_puuid) {
            $sk = S $k.killer_puuid
            $sk.uccisioni++
            if ($d) { $sk.distUccTot += $d; $sk.distUccN++ }
        }

        if ($k.victim_puuid) {
            $sv = S $k.victim_puuid
            $sv.morti++
            if ($d) { $sv.distDuelloTot += $d; $sv.distDuelloN++ }
            $sv.tempoMorteTot += [double]$k.kill_time_in_round; $sv.tempoMorteN++

            # ---- isolamento: compagno vivo piu' vicino ----
            $team = $squadraDi[$k.victim_puuid]
            $vicino = $null
            foreach ($loc in $k.player_locations_on_kill) {
                if ($squadraDi[$loc.player_puuid] -ne $team) { continue }
                if ($loc.player_puuid -eq $k.victim_puuid) { continue }
                $dd = Dist $loc.location $k.victim_death_location
                if ($dd -and (-not $vicino -or $dd -lt $vicino)) { $vicino = $dd }
            }
            if ($vicino) { $sv.isolamentoTot += $vicino; $sv.isolamentoN++ }

            # ---- vendicato entro la finestra? ----
            $vend = $kills | Where-Object {
                $_.round -eq $k.round -and
                $_.victim_puuid -eq $k.killer_puuid -and
                $_.kill_time_in_round -gt $k.kill_time_in_round -and
                ($_.kill_time_in_round - $k.kill_time_in_round) -le $FINESTRA_TRADE -and
                $squadraDi[$_.killer_puuid] -eq $team
            }
            if ($vend) { $sv.mortiVendicate++ }
        }
    }

    # ---- analisi round per round, solo mia ----
    foreach ($r in $m.rounds) {
        $idx = [array]::IndexOf($m.rounds, $r)
        $nr  = $idx + 1
        $vinto = ($r.winning_team -eq $mioTeam)

        # lato: nei primi 12 round una squadra attacca, poi si invertono
        $primaMeta = ($nr -le 12)
        $attaccoOra = if ($mioTeam -eq 'Red') { $primaMeta } else { -not $primaMeta }

        $ps = $r.player_stats | Where-Object { $_.player_puuid -eq $PUUID }
        $mieK = if ($ps) { [int]$ps.kills } else { 0 }
        $mieD = if (($m.kills | Where-Object { $_.round -eq $idx -and $_.victim_puuid -eq $PUUID })) { 1 } else { 0 }

        if ($attaccoOra) { $attaccoR++; if ($vinto) { $attaccoV++ }; $attaccoK += $mieK; $attaccoD += $mieD }
        else             { $difesaR++;  if ($vinto) { $difesaV++  }; $difesaK += $mieK; $difesaD += $mieD }

        if ($multiKill.ContainsKey($mieK)) { $multiKill[$mieK]++ }

        $primo = @($m.kills | Where-Object { $_.round -eq $idx } | Sort-Object kill_time_in_round | Select-Object -First 1)
        if ($primo.Count -gt 0) {
            if     ($primo[0].killer_puuid -eq $PUUID) { $roundConFB++; if ($vinto) { $roundConFBvinti++ } }
            elseif ($primo[0].victim_puuid -eq $PUUID) { $roundConFD++; if ($vinto) { $roundConFDvinti++ } }
            else   { $roundNeutri++; if ($vinto) { $roundNeutriVinti++ } }
        }
    }

    # ---- fasce temporali delle mie morti ----
    foreach ($k in ($m.kills | Where-Object { $_.victim_puuid -eq $PUUID })) {
        $s = [double]$k.kill_time_in_round / 1000
        if     ($s -lt 15) { $mortePerFascia['primi 15s']++ }
        elseif ($s -lt 30) { $mortePerFascia['15-30s']++ }
        elseif ($s -lt 60) { $mortePerFascia['30-60s']++ }
        else               { $mortePerFascia['oltre 60s']++ }
    }
}

# ============ CONFRONTO ============
$io = $stat[$PUUID]
$altri = @($stat.Keys | Where-Object { $_ -ne $PUUID -and $stat[$_].morti -ge 15 } | ForEach-Object { $stat[$_] })

function MediaAltri($sel) { ($altri | ForEach-Object { & $sel $_ } | Where-Object { $_ -ne $null } | Measure-Object -Average).Average }

$mioIsol   = $io.isolamentoTot / [math]::Max($io.isolamentoN,1)
$medIsol   = MediaAltri { param($s) if ($s.isolamentoN -gt 0) { $s.isolamentoTot/$s.isolamentoN } }
$mioDuello = $io.distDuelloTot / [math]::Max($io.distDuelloN,1)
$medDuello = MediaAltri { param($s) if ($s.distDuelloN -gt 0) { $s.distDuelloTot/$s.distDuelloN } }
$mioTrade  = $io.mortiVendicate / [math]::Max($io.morti,1) * 100
$medTrade  = MediaAltri { param($s) if ($s.morti -gt 0) { $s.mortiVendicate/$s.morti*100 } }
$mioTempo  = $io.tempoMorteTot / [math]::Max($io.tempoMorteN,1) / 1000
$medTempo  = MediaAltri { param($s) if ($s.tempoMorteN -gt 0) { $s.tempoMorteTot/$s.tempoMorteN/1000 } }

Write-Host ""
Write-Host "=============================================================="
Write-Host "  ANALISI AVANZATA  -  $nComp competitive, $($altri.Count) giocatori di confronto"
Write-Host "=============================================================="
Write-Host ""
Write-Host "POSIZIONE E CONTESTO DELLA MORTE"
Write-Host ("  Isolamento quando muori   : {0,7:N0}  |  altri {1,7:N0}  |  indice {2,3:N0}" -f $mioIsol, $medIsol, ($mioIsol/$medIsol*100))
Write-Host   "    (distanza dal compagno vivo piu' vicino, unita' di gioco - piu' alto = piu' solo)"
Write-Host ("  Distanza del duello       : {0,7:N0}  |  altri {1,7:N0}  |  indice {2,3:N0}" -f $mioDuello, $medDuello, ($mioDuello/$medDuello*100))
Write-Host ("  Morti vendicate entro 4s  : {0,6:N1}%  |  altri {1,6:N1}%  |  indice {2,3:N0}" -f $mioTrade, $medTrade, ($mioTrade/$medTrade*100))
Write-Host ("  Secondo in cui muori      : {0,7:N1}  |  altri {1,7:N1}  |  indice {2,3:N0}" -f $mioTempo, $medTempo, ($mioTempo/$medTempo*100))
Write-Host ""
Write-Host "QUANDO MUORI NEL ROUND"
$totM = ($mortePerFascia.Values | Measure-Object -Sum).Sum
foreach ($k in @('primi 15s','15-30s','30-60s','oltre 60s')) {
    $n = $mortePerFascia[$k]
    Write-Host ("  {0,-12} {1,4}  {2,5:N1}%  {3}" -f $k, $n, ($n/$totM*100), ('#' * [int]($n/$totM*50)))
}
Write-Host ""
Write-Host "IMPATTO DEL PRIMO DUELLO SUL ROUND"
Write-Host ("  Round in cui apri tu      : {0,4} round  ->  {1,5:N1}% vinti" -f $roundConFB, ($roundConFBvinti/[math]::Max($roundConFB,1)*100))
Write-Host ("  Round in cui cadi per primo: {0,3} round  ->  {1,5:N1}% vinti" -f $roundConFD, ($roundConFDvinti/[math]::Max($roundConFD,1)*100))
Write-Host ("  Round senza tuo primo duello: {0,2} round  ->  {1,5:N1}% vinti" -f $roundNeutri, ($roundNeutriVinti/[math]::Max($roundNeutri,1)*100))
Write-Host ""
Write-Host "ATTACCO CONTRO DIFESA"
Write-Host ("  Attacco : {0,3} round  {1,5:N1}% vinti   {2,5:N2} kill/rd   {3,5:N2} morti/rd" -f $attaccoR, ($attaccoV/[math]::Max($attaccoR,1)*100), ($attaccoK/[math]::Max($attaccoR,1)), ($attaccoD/[math]::Max($attaccoR,1)))
Write-Host ("  Difesa  : {0,3} round  {1,5:N1}% vinti   {2,5:N2} kill/rd   {3,5:N2} morti/rd" -f $difesaR,  ($difesaV/[math]::Max($difesaR,1)*100),  ($difesaK/[math]::Max($difesaR,1)),  ($difesaD/[math]::Max($difesaR,1)))
Write-Host ""
Write-Host "ROUND PER NUMERO DI UCCISIONI"
$totR = ($multiKill.Values | Measure-Object -Sum).Sum
foreach ($n in 0..5) {
    if ($multiKill[$n] -gt 0) {
        Write-Host ("  {0} kill : {1,4} round  {2,5:N1}%  {3}" -f $n, $multiKill[$n], ($multiKill[$n]/$totR*100), ('#' * [int]($multiKill[$n]/$totR*50)))
    }
}

$ris = [ordered]@{
    partite = $nComp
    confronto = $altri.Count
    isolamento = @{ mio=[math]::Round($mioIsol); altri=[math]::Round($medIsol); indice=[math]::Round($mioIsol/$medIsol*100) }
    distanzaDuello = @{ mio=[math]::Round($mioDuello); altri=[math]::Round($medDuello); indice=[math]::Round($mioDuello/$medDuello*100) }
    trade = @{ mio=[math]::Round($mioTrade,1); altri=[math]::Round($medTrade,1); indice=[math]::Round($mioTrade/$medTrade*100) }
    tempoMorte = @{ mio=[math]::Round($mioTempo,1); altri=[math]::Round($medTempo,1); indice=[math]::Round($mioTempo/$medTempo*100) }
    fasceMorte = $mortePerFascia
    primoDuello = @{
        apri=@{ round=$roundConFB; vinti=[math]::Round($roundConFBvinti/[math]::Max($roundConFB,1)*100,1) }
        cadi=@{ round=$roundConFD; vinti=[math]::Round($roundConFDvinti/[math]::Max($roundConFD,1)*100,1) }
        neutro=@{ round=$roundNeutri; vinti=[math]::Round($roundNeutriVinti/[math]::Max($roundNeutri,1)*100,1) }
    }
    lato = @{
        attacco=@{ round=$attaccoR; vinti=[math]::Round($attaccoV/[math]::Max($attaccoR,1)*100,1); kpr=[math]::Round($attaccoK/[math]::Max($attaccoR,1),2) }
        difesa=@{ round=$difesaR; vinti=[math]::Round($difesaV/[math]::Max($difesaR,1)*100,1); kpr=[math]::Round($difesaK/[math]::Max($difesaR,1),2) }
    }
    multiKill = $multiKill
}
$ris | ConvertTo-Json -Depth 8 | Set-Content "$base\avanzata.json" -Encoding utf8
Write-Host ""
Write-Host "Salvato in $base\avanzata.json"
