# WhyVallyAgent

**Valorant performance analysis from raw match data: download a player's archive, compare every metric against the real lobbies (not global averages), extract positional data from maps, write the report.**

Vally è un agente di Claude Code addestrato su una procedura sola, sempre uguale. Questi sono i suoi script.

| Script | Cosa fa |
|---|---|
| `scarica.ps1` | scarica l'archivio delle partite (API HenrikDev, con limite di richieste rispettato) |
| `analizza.ps1`, `avanzata.ps1` | metriche base e avanzate |
| `confronto.ps1` | ogni metrica contro la media dei 10 giocatori delle **stesse lobby** |
| `kast.ps1` | KAST esatto e delta danni (inflitto meno subito, per round) |
| `posizioni.ps1`, `zone.ps1`, `prova-mappa.ps1` | posizioni di uccisore e vittima, duelli per fascia di distanza, zone della mappa |
| `critica.ps1` | cerca i punti deboli del report prima di consegnarlo |

## Il metodo
- **La lobby è il riferimento**, non la media globale: un numero "nella norma" può essere al 14esimo percentile delle proprie partite.
- **Il rango degli avversari si controlla sempre**: parte di ogni scarto è differenza di rango, non abilità.
- **Round a impatto zero**: la metrica che il KAST nasconde.

Serve un `config.json` accanto agli script con `name`, `tag`, `region` e la chiave HenrikDev (mai nel repo).

---

Parte di **[WhyEcosystem 2023-2026](https://github.com/OfficialWhyEd/WhyEcosystem-2023-2026)**: il percorso di WhyEd, producer e sound engineer che costruisce sistemi AI dirigendo gli agenti.  
Costruito da WhyEd con Claude Code
