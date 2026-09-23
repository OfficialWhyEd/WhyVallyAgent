# Scarica tutto lo storico disponibile da HenrikDev e lo archivia in locale.
# L'archivio e' cumulativo: le partite gia' scaricate non vengono perse
# anche quando l'API smettera' di servirle.
$base = $PSScriptRoot
$cfg  = Get-Content "$base\config.json" -Raw | ConvertFrom-Json
$H    = @{ "Authorization" = $cfg.key }
$pausa = [math]::Ceiling(60 / $cfg.rateRpm) + 1   # margine sul limite di 30/min

New-Item -ItemType Directory -Force -Path "$base\raw","$base\partite" | Out-Null

function Chiama($url, $etichetta) {
    for ($t = 1; $t -le 3; $t++) {
        try { return Invoke-RestMethod -Uri $url -Headers $H -TimeoutSec 60 }
        catch {
            $code = $_.Exception.Response.StatusCode.value__
            if ($code -eq 429) { Write-Host "  [$etichetta] limite raggiunto, attendo 30s..."; Start-Sleep 30 }
            else { Write-Host "  [$etichetta] errore $code : $($_.Exception.Message)"; return $null }
        }
    }
    return $null
}

Write-Host "=== 1. PROFILO E RANGO ===" -ForegroundColor Cyan
$mmr = Chiama "https://api.henrikdev.xyz/valorant/v3/mmr/$($cfg.region)/$($cfg.platform)/$($cfg.name)/$($cfg.tag)" "mmr"
if ($mmr) {
    $mmr | ConvertTo-Json -Depth 15 | Set-Content "$base\raw\mmr.json" -Encoding utf8
    Write-Host "  $($mmr.data.current.tier.name) - $($mmr.data.current.rr) RR"
}
Start-Sleep $pausa

Write-Host "=== 2. ELENCO PARTITE ===" -ForegroundColor Cyan
$tutte = @()
$pagina = 1
do {
    $r = Chiama "https://api.henrikdev.xyz/valorant/v1/lifetime/matches/$($cfg.region)/$($cfg.name)/$($cfg.tag)?page=$pagina&size=20" "pag$pagina"
    if (-not $r) { break }
    $tutte += $r.data
    $totale = $r.results.total
    Write-Host "  pagina $pagina : $($r.data.Count) partite (totale $totale)"
    $pagina++
    Start-Sleep $pausa
} while ($tutte.Count -lt $totale -and $pagina -le 20)

$tutte | ConvertTo-Json -Depth 15 | Set-Content "$base\raw\partite-elenco.json" -Encoding utf8
Write-Host "  scaricate $($tutte.Count) partite" -ForegroundColor Green

Write-Host "=== 3. DETTAGLIO ROUND PER ROUND ===" -ForegroundColor Cyan
Write-Host "  (salto quelle gia' presenti nell'archivio)"
$nuove = 0; $saltate = 0
foreach ($m in $tutte) {
    $id = $m.meta.id
    if (-not $id) { continue }
    $dest = "$base\partite\$id.json"
    if (Test-Path $dest) { $saltate++; continue }
    $d = Chiama "https://api.henrikdev.xyz/valorant/v2/match/$id" "match"
    if ($d) {
        $d | ConvertTo-Json -Depth 25 | Set-Content $dest -Encoding utf8
        $nuove++
        Write-Host "  + $($m.meta.map.name) $($m.meta.started_at)"
    }
    Start-Sleep $pausa
}
Write-Host "  nuove: $nuove   gia' in archivio: $saltate" -ForegroundColor Green

Write-Host ""
Write-Host "Archivio in $base" -ForegroundColor Cyan
Write-Host "  partite in dettaglio: $((Get-ChildItem "$base\partite" -Filter *.json -ErrorAction SilentlyContinue).Count)"
