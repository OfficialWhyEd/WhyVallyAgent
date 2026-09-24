# WhyVallyAgent

**Valorant performance analysis from raw match data: archive every match, compare each metric against the player's real lobbies (not global averages), extract positions from the maps, then attack its own conclusions before writing the report.**

`PowerShell` · `HenrikDev API` · `System.Drawing` · stato: **in uso**

Vally è un agente di Claude Code addestrato su una procedura sola, sempre uguale. Questi sono i suoi script:
trasformano lo storico di un giocatore in numeri che reggono, e in mappe che mostrano dove muore.

## Cosa fa
- **archivia tutte le partite** in locale, in modo cumulativo: quelle già scaricate restano anche quando l'API
  smette di servirle;
- **confronta con la lobby vera**: ogni metrica contro la media dei 10 giocatori delle stesse partite;
- **KAST esatto e delta danni** (inflitti meno subiti, per round), anche per tutti gli altri della lobby;
- **analisi avanzata**: isolamento quando muori, distanza dei duelli, scambi entro 4 secondi, momento della
  morte nel round, peso reale del primo sangue;
- **mappe**: coordinate di gioco convertite sul radar, zone dove muore di più, PNG trasparenti;
- **critica di sé stesso**: round a impatto zero, intervalli di confidenza, attacco contro difesa, deathmatch
  come prova di mira pura.

## Come funziona
```
scarica.ps1 ─► partite/*.json (archivio cumulativo)
                    │
      ┌─────────────┼──────────────┬───────────────┐
analizza.ps1   confronto.ps1    kast.ps1      avanzata.ps1
      └─────────────┴──────┬───────┴───────────────┘
                           ▼
       posizioni.ps1 ─► zone.ps1 ─► mappe/finali/*.png
                           ▼
                     critica.ps1 ─► il report
```

## Struttura
| Script | Cosa fa |
|---|---|
| `scarica.ps1` | scarica lo storico da HenrikDev rispettando il limite di richieste |
| `analizza.ps1` | metriche base, `analisi.json` |
| `confronto.ps1` | ogni metrica contro la media delle stesse lobby |
| `kast.ps1` | KAST esatto e delta danni |
| `avanzata.ps1` | isolamento, distanze, scambi, tempi, primo sangue |
| `posizioni.ps1` | coordinate sul radar e duelli per fascia di distanza |
| `prova-mappa.ps1` | minimappa con i punti sopra, per controllare l'allineamento a occhio |
| `zone.ps1` | zone di morte e mappe finali |
| `critica.ps1` | mette alla prova le conclusioni invece di confermarle |

## Come si avvia
Accanto agli script serve un `config.json` (escluso da git):
```json
{ "name": "Giocatore", "tag": "TAG", "region": "eu", "platform": "pc",
  "puuid": "...", "key": "chiave HenrikDev", "rate": 30 }
```
Poi, in ordine:
```
powershell -File scarica.ps1
powershell -File analizza.ps1
powershell -File confronto.ps1
powershell -File kast.ps1
powershell -File avanzata.ps1
powershell -File posizioni.ps1
powershell -File zone.ps1
powershell -File critica.ps1
```

## Stato
In uso. È la procedura con cui Vally ha scritto i suoi referti, sempre con gli stessi passi.

## Perché è nato
I tracker confrontano con medie globali che non dicono niente. Un numero "nella norma" può stare al 14esimo
percentile delle proprie partite. Il riferimento giusto sono le persone con cui giochi davvero, e parte di ogni
scarto è differenza di rango, non di abilità: per questo il rango degli avversari si controlla sempre.

---

Parte di **[WhyEcosystem 2023-2026](https://github.com/OfficialWhyEd/WhyEcosystem-2023-2026)**: il percorso di WhyEd, producer e sound engineer che costruisce sistemi AI dirigendo gli agenti.  
Costruito da WhyEd con Claude Code
