# Confronta GiocatoreA#TAG con la media dei 10 giocatori delle SUE lobby.
# Nessun benchmark inventato: il riferimento sono gli avversari e i compagni reali.
$base  = $PSScriptRoot
$cfg   = Get-Content "$base\config.json" -Raw | ConvertFrom-Json
$PUUID = $cfg.puuid

$agg = @{}   # puuid -> statistiche accumulate
function Slot($p) {
    if (-not $agg[$p]) {
        $agg[$p] = [pscustomobject]@{
            round=0; kills=0; deaths=0; assists=0; danno=0
            hs=0; bs=0; ls=0; fb=0; fd=0; partite=0
        }
    }
    return $agg[$p]
}

$files = Get-ChildItem "$base\partite\*.json"
$nComp = 0

foreach ($f in $files) {
    $m = (Get-Content $f.FullName -Raw | ConvertFrom-Json).data
    if ($m.metadata.mode -ne 'Competitive') { continue }
    $nComp++

    # morti per giocatore, dedotte dagli eventi di uccisione
    $morti = @{}
    foreach ($k in $m.kills) { $morti[$k.victim_puuid] = [int]$morti[$k.victim_puuid] + 1 }

    foreach ($pl in $m.players.all_players) {
        $s = Slot $pl.puuid
        $s.partite++
        $s.kills   += [int]$pl.stats.kills
        $s.assists += [int]$pl.stats.assists
        $s.deaths  += [int]$morti[$pl.puuid]
    }

    foreach ($r in $m.rounds) {
        foreach ($ps in $r.player_stats) {
            $s = Slot $ps.player_puuid
            $s.round++
            $s.danno += [int]$ps.damage
            $s.hs    += [int]$ps.headshots
            $s.bs    += [int]$ps.bodyshots
            $s.ls    += [int]$ps.legshots
        }
    }

    foreach ($g in ($m.kills | Group-Object round)) {
        $primo = $g.Group | Sort-Object kill_time_in_round | Select-Object -First 1
        if ($primo.killer_puuid) { (Slot $primo.killer_puuid).fb++ }
        if ($primo.victim_puuid) { (Slot $primo.victim_puuid).fd++ }
    }
}

# --- calcolo delle metriche per giocatore ---
$righe = @()
foreach ($p in $agg.Keys) {
    $s = $agg[$p]
    if ($s.round -lt 20) { continue }          # scarto chi ha pochissimi round
    $colpi = $s.hs + $s.bs + $s.ls
    $righe += [pscustomobject]@{
        puuid   = $p
        io      = ($p -eq $PUUID)
        round   = $s.round
        kpr     = $s.kills   / $s.round
        dpr     = $s.deaths  / $s.round
        apr     = $s.assists / $s.round
        adr     = $s.danno   / $s.round
        hsp     = if ($colpi -gt 0) { $s.hs / $colpi * 100 } else { 0 }
        fbr     = $s.fb / $s.round * 100
        fdr     = $s.fd / $s.round * 100
    }
}

$io  = $righe | Where-Object { $_.io }
$tut = $righe

function Media($campo) { ($tut | Measure-Object $campo -Average).Average }

$ris = [ordered]@{
    partiteCompetitive = $nComp
    giocatoriConfrontati = $tut.Count
    roundMiei = $io.round
    assi = @()
}

$def = @(
    @{ nome='Uccisioni';     campo='kpr'; alto=$true;  fmt='N2'; desc='uccisioni per round' },
    @{ nome='Danno';         campo='adr'; alto=$true;  fmt='N0'; desc='danno per round' },
    @{ nome='Precisione';    campo='hsp'; alto=$true;  fmt='N1'; desc='percentuale headshot' },
    @{ nome='Sopravvivenza'; campo='dpr'; alto=$false; fmt='N2'; desc='morti per round (meno e meglio)' },
    @{ nome='Apertura';      campo='fbr'; alto=$true;  fmt='N1'; desc='primo sangue, % dei round' },
    @{ nome='Supporto';      campo='apr'; alto=$true;  fmt='N2'; desc='assist per round' }
)

Write-Host ""
Write-Host "=================================================================="
Write-Host "  CONFRONTO CON LA LOBBY  -  $nComp competitive, $($tut.Count) giocatori"
Write-Host "  (solo giocatori con almeno 20 round, media reale non stimata)"
Write-Host "=================================================================="
Write-Host ""
Write-Host ("  {0,-14} {1,8} {2,9} {3,8} {4,11}" -f 'ASSE','TU','LOBBY','INDICE','PERCENTILE')
Write-Host ("  " + ("-" * 56))

foreach ($d in $def) {
    $campo = $d.campo
    $mio = $io.$campo
    $med = Media $campo
    $idx = if ($d.alto) { $mio / [math]::Max($med, 0.0001) * 100 } else { $med / [math]::Max($mio, 0.0001) * 100 }
    if ($d.alto) { $sotto = @($tut | Where-Object { $_.$campo -lt $mio }).Count }
    else         { $sotto = @($tut | Where-Object { $_.$campo -gt $mio }).Count }
    $pc = [math]::Round($sotto / $tut.Count * 100)
    Write-Host ("  {0,-14} {1,8} {2,9} {3,8:N0} {4,10}" -f $d.nome, $mio.ToString($d.fmt), $med.ToString($d.fmt), $idx, ("{0}o" -f $pc))
    $ris.assi += [ordered]@{
        nome = $d.nome; descrizione = $d.desc
        mio = [math]::Round($mio,2); lobby = [math]::Round($med,2)
        indice = [math]::Round($idx); percentile = $pc
    }
}

Write-Host ""
Write-Host "  Indice 100 = esattamente la media della lobby."
Write-Host ""

$ris | ConvertTo-Json -Depth 6 | Set-Content "$base\confronto.json" -Encoding utf8
Write-Host "Salvato in $base\confronto.json"
