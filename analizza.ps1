# Analizza l'archivio locale e produce analisi.json + report a schermo.
$base  = $PSScriptRoot
$cfg   = Get-Content "$base\config.json" -Raw | ConvertFrom-Json
$PUUID = $cfg.puuid

$files = Get-ChildItem "$base\partite\*.json" -ErrorAction SilentlyContinue
if (-not $files) { Write-Host "Nessuna partita in archivio. Lancia prima scarica.ps1"; return }

$partite = @()

foreach ($f in $files) {
    $m = (Get-Content $f.FullName -Raw | ConvertFrom-Json).data
    $me = $m.players.all_players | Where-Object { $_.puuid -eq $PUUID }
    if (-not $me) { continue }

    $squadra = $me.team
    $mia  = if ($squadra -eq 'Red') { $m.teams.red } else { $m.teams.blue }
    $sua  = if ($squadra -eq 'Red') { $m.teams.blue } else { $m.teams.red }

    $dmg = 0; $hs = 0; $bs = 0; $ls = 0; $roundGiocati = 0
    $spesa = 0; $abil = 0
    $perEconomia = @{}
    foreach ($r in $m.rounds) {
        $ps = $r.player_stats | Where-Object { $_.player_puuid -eq $PUUID }
        if (-not $ps) { continue }
        $roundGiocati++
        $dmg   += [int]$ps.damage
        $hs    += [int]$ps.headshots
        $bs    += [int]$ps.bodyshots
        $ls    += [int]$ps.legshots
        $spesa += [int]$ps.economy.spent
        $abil  += ([int]$ps.ability_casts.q_casts + [int]$ps.ability_casts.e_casts + [int]$ps.ability_casts.c_casts + [int]$ps.ability_casts.x_casts)

        $lv = [int]$ps.economy.loadout_value
        $fascia = if ($lv -lt 1500) { 'eco' } elseif ($lv -lt 3000) { 'semi' } else { 'full' }
        if (-not $perEconomia[$fascia]) { $perEconomia[$fascia] = @{ round = 0; kills = 0; dmg = 0; vinti = 0 } }
        $perEconomia[$fascia].round++
        $perEconomia[$fascia].kills += [int]$ps.kills
        $perEconomia[$fascia].dmg   += [int]$ps.damage
        if ($r.winning_team -eq $squadra) { $perEconomia[$fascia].vinti++ }
    }

    $fb = 0; $fd = 0
    foreach ($g in ($m.kills | Group-Object round)) {
        $primo = $g.Group | Sort-Object kill_time_in_round | Select-Object -First 1
        if ($primo.killer_puuid -eq $PUUID) { $fb++ }
        if ($primo.victim_puuid -eq $PUUID) { $fd++ }
    }

    $armi = @{}
    foreach ($k in ($m.kills | Where-Object { $_.killer_puuid -eq $PUUID })) {
        $n = if ($k.damage_weapon_name) { $k.damage_weapon_name } else { 'Abilita/Altro' }
        $armi[$n] = [int]$armi[$n] + 1
    }

    $morti = @()
    foreach ($k in ($m.kills | Where-Object { $_.victim_puuid -eq $PUUID })) {
        $morti += [pscustomobject]@{
            x = $k.victim_death_location.x
            y = $k.victim_death_location.y
            round = $k.round
            arma = $k.damage_weapon_name
            uccisore = $k.killer_display_name
        }
    }

    $partite += [pscustomobject]@{
        id           = $m.metadata.matchid
        data         = [datetimeoffset]::FromUnixTimeSeconds($m.metadata.game_start).LocalDateTime
        mappa        = $m.metadata.map
        modalita     = $m.metadata.mode
        durata       = [int]$m.metadata.game_length
        agente       = $me.character
        livello      = $me.level
        squadra      = $squadra
        vinta        = [bool]$mia.has_won
        roundVinti   = [int]$mia.rounds_won
        roundPersi   = [int]$sua.rounds_won
        kills        = [int]$me.stats.kills
        deaths       = [int]$me.stats.deaths
        assists      = [int]$me.stats.assists
        score        = [int]$me.stats.score
        headshots    = $hs
        bodyshots    = $bs
        legshots     = $ls
        danno        = $dmg
        roundGiocati = $roundGiocati
        primoSangue  = $fb
        primaMorte   = $fd
        spesaTotale  = $spesa
        abilita      = $abil
        armi         = $armi
        economia     = $perEconomia
        morti        = $morti
    }
}

$partite = @($partite | Sort-Object data)
$partite | ConvertTo-Json -Depth 12 | Set-Content "$base\analisi.json" -Encoding utf8

function Riga($t) { Write-Host $t }
$comp = @($partite | Where-Object { $_.modalita -eq 'Competitive' })

Riga ""
Riga "================================================================"
Riga "  $($cfg.name)#$($cfg.tag)  -  archivio di $($partite.Count) partite"
Riga "  dal $($partite[0].data.ToString('dd/MM/yyyy')) al $($partite[-1].data.ToString('dd/MM/yyyy'))"
Riga "================================================================"
Riga ""
Riga "PER MODALITA'"
foreach ($grp in ($partite | Group-Object modalita | Sort-Object Count -Descending)) {
    $v = @($grp.Group | Where-Object { $_.vinta }).Count
    Riga ("  {0,-13} {1,3} partite   {2}V-{3}S" -f $grp.Name, $grp.Count, $v, ($grp.Count - $v))
}

if ($comp.Count -gt 0) {
    $k  = ($comp | Measure-Object kills   -Sum).Sum
    $d  = ($comp | Measure-Object deaths  -Sum).Sum
    $a  = ($comp | Measure-Object assists -Sum).Sum
    $dm = ($comp | Measure-Object danno   -Sum).Sum
    $rg = ($comp | Measure-Object roundGiocati -Sum).Sum
    $h  = ($comp | Measure-Object headshots -Sum).Sum
    $b  = ($comp | Measure-Object bodyshots -Sum).Sum
    $l  = ($comp | Measure-Object legshots  -Sum).Sum
    $colpi = $h + $b + $l
    $v  = @($comp | Where-Object { $_.vinta }).Count
    $rv = ($comp | Measure-Object roundVinti -Sum).Sum
    $rp = ($comp | Measure-Object roundPersi -Sum).Sum
    $fbT = ($comp | Measure-Object primoSangue -Sum).Sum
    $fdT = ($comp | Measure-Object primaMorte  -Sum).Sum

    Riga ""
    Riga "COMPETITIVE  ($($comp.Count) partite, $rg round)"
    Riga ("  Vittorie      : {0}V-{1}S   ({2:N0}%)" -f $v, ($comp.Count-$v), ($v/$comp.Count*100))
    Riga ("  Round         : {0}-{1}   ({2:N0}%)" -f $rv, $rp, ($rv/($rv+$rp)*100))
    Riga ("  K / D / A     : {0} / {1} / {2}" -f $k, $d, $a)
    Riga ("  Rapporto K/D  : {0:N2}" -f ($k/[math]::Max($d,1)))
    Riga ("  KDA           : {0:N2}" -f (($k+$a)/[math]::Max($d,1)))
    Riga ("  Kill per round: {0:N2}" -f ($k/$rg))
    Riga ("  Morti per rd  : {0:N2}" -f ($d/$rg))
    Riga ("  ADR           : {0:N0}" -f ($dm/$rg))
    Riga ("  Headshot %    : {0:N1}%   ({1} testa / {2} corpo / {3} gambe)" -f ($h/[math]::Max($colpi,1)*100), $h, $b, $l)
    Riga ("  Primo sangue  : {0} ({1:N0}% dei round)" -f $fbT, ($fbT/$rg*100))
    Riga ("  Prima morte   : {0} ({1:N0}% dei round)" -f $fdT, ($fdT/$rg*100))
    Riga ("  Abilita' usate: {0:N2} per round" -f (($comp|Measure-Object abilita -Sum).Sum/$rg))

    Riga ""
    Riga "PER AGENTE (competitive)"
    foreach ($grp in ($comp | Group-Object agente | Sort-Object Count -Descending)) {
        $g  = $grp.Group
        $gk = ($g|Measure-Object kills -Sum).Sum
        $gd = ($g|Measure-Object deaths -Sum).Sum
        $gr = ($g|Measure-Object roundGiocati -Sum).Sum
        $gdm= ($g|Measure-Object danno -Sum).Sum
        $gv = @($g | Where-Object { $_.vinta }).Count
        Riga ("  {0,-10} {1,2}p  {2}V-{3}S  K/D {4,5:N2}  ADR {5,3:N0}" -f $grp.Name, $grp.Count, $gv, ($grp.Count-$gv), ($gk/[math]::Max($gd,1)), ($gdm/[math]::Max($gr,1)))
    }

    Riga ""
    Riga "PER MAPPA (competitive)"
    foreach ($grp in ($comp | Group-Object mappa | Sort-Object Count -Descending)) {
        $g  = $grp.Group
        $gk = ($g|Measure-Object kills -Sum).Sum
        $gd = ($g|Measure-Object deaths -Sum).Sum
        $gr = ($g|Measure-Object roundGiocati -Sum).Sum
        $gdm= ($g|Measure-Object danno -Sum).Sum
        $gv = @($g | Where-Object { $_.vinta }).Count
        Riga ("  {0,-10} {1,2}p  {2}V-{3}S  K/D {4,5:N2}  ADR {5,3:N0}" -f $grp.Name, $grp.Count, $gv, ($grp.Count-$gv), ($gk/[math]::Max($gd,1)), ($gdm/[math]::Max($gr,1)))
    }

    Riga ""
    Riga "ARMI PIU' USATE (tutte le modalita')"
    $tot = @{}
    foreach ($p in $partite) {
        foreach ($n in @($p.armi.Keys)) { $tot[$n] = [int]$tot[$n] + [int]$p.armi[$n] }
    }
    foreach ($e in ($tot.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10)) {
        Riga ("  {0,-18} {1,3} uccisioni" -f $e.Key, $e.Value)
    }

    Riga ""
    Riga "RENDIMENTO PER FASCIA ECONOMICA (competitive)"
    $ec = @{}
    foreach ($p in $comp) {
        foreach ($n in @($p.economia.Keys)) {
            if (-not $ec[$n]) { $ec[$n] = @{ round=0; kills=0; dmg=0; vinti=0 } }
            $ec[$n].round += $p.economia[$n].round
            $ec[$n].kills += $p.economia[$n].kills
            $ec[$n].dmg   += $p.economia[$n].dmg
            $ec[$n].vinti += $p.economia[$n].vinti
        }
    }
    foreach ($n in @('eco','semi','full')) {
        if ($ec[$n] -and $ec[$n].round -gt 0) {
            $e = $ec[$n]
            Riga ("  {0,-6} {1,3} round   {2,3:N0}% vinti   {3:N2} kill/rd   ADR {4,3:N0}" -f $n, $e.round, ($e.vinti/$e.round*100), ($e.kills/$e.round), ($e.dmg/$e.round))
        }
    }

    Riga ""
    Riga "ANDAMENTO NEL TEMPO (competitive, in ordine)"
    foreach ($p in $comp) {
        $esito = if ($p.vinta) { "V" } else { "S" }
        Riga ("  {0}  {1,-9} {2,-8} {3}  {4,2}-{5,-2}  {6,2}K {7,2}D {8,2}A   ADR {9,3:N0}" -f $p.data.ToString('dd/MM'), $p.mappa, $p.agente, $esito, $p.roundVinti, $p.roundPersi, $p.kills, $p.deaths, $p.assists, ($p.danno/[math]::Max($p.roundGiocati,1)))
    }
}

Riga ""
Riga "Analisi salvata in $base\analisi.json"
