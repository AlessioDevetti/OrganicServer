# QUEUE.md — Coda dei task approvati

> Solo i task con stato `APPROVED` possono essere eseguiti dall'agente (Tier 2).
> Un task diventa `APPROVED` esclusivamente con approvazione esplicita dell'operatore umano, registrata nel blocco di dettaglio.
> La tabella è l'indice di sintesi; il blocco sotto riporta il dettaglio operativo.

## Stati

| Stato | Significato |
| :--- | :--- |
| `PROPOSED` | Proposto dall'agente o dall'operatore, in attesa di approvazione. |
| `APPROVED` | Approvato dall'operatore: eseguibile nella prossima sessione. |
| `IN_PROGRESS` | In esecuzione nella sessione corrente. |
| `DONE` | Completato e verificato; riportato in `.ai/REPORT.md`. |
| `BLOCKED` | Fermo per errore, dipendenza o necessità di intervento umano (Tier 3). |

## Indice dei task

| ID | Stato | Stack coinvolto | Descrizione | Criteri di verifica |
| :--- | :--- | :--- | :--- | :--- |
| TASK-001 | DONE | `stacks/whoami-v6` | Stack pilota hardened IPv6-only su `edge-v6`; dry-run con pre-flight, validazione Compose e aggiornamento stato. | `docker compose config` exit `0`; assenza binding IPv4; report e context aggiornati. |
| TASK-002 | PROPOSED | `stacks/` (tooling) | Implementare gli script mancanti `scripts/preflight.sh` e `scripts/update-context.sh`, invocati dal flusso operativo ma assenti nel repository. | Entrambi gli script esistono, sono idempotenti, leggono lo stato senza modificarlo e terminano con exit `0`/`1` documentato. |

## Dettaglio dei task

```markdown
### TASK-001 — Stack pilota whoami-v6 (dry-run IPv6-only)
- **ID:** TASK-001
- **Stato:** DONE
- **Stack coinvolto:** `stacks/whoami-v6`
- **Descrizione:** Creare uno stack pilota leggero e hardened (`traefik/whoami:v1.10.3`) collegato solo a `edge-v6`, eseguire il pre-flight, validare la configurazione Compose e, se il daemon Docker con IPv6 è disponibile, avviarlo e verificarne la raggiungibilità IPv6 senza esposizione IPv4.
- **Criteri di verifica:** `./scripts/preflight.sh` exit `0`; `docker compose -f stacks/whoami-v6/compose.yml config` exit `0`; `ss -4 -tulpn` senza socket Docker; container raggiungibile su IPv6; `.ai/CONTEXT.md` e `.ai/REPORT.md` aggiornati.
- **Approvato da:** Operatore — 2026-11-25 (istruzione di sessione)
- **Note / rischi:** Dry-run completato con esito `PARTIAL`: stack creato e validato staticamente (Compose v2.40.3, exit `0`), ma deploy e controlli runtime non eseguiti perché l'ambiente non dispone di Docker CLI/daemon, `ss` o `systemctl`. Gli script `scripts/preflight.sh` e `scripts/update-context.sh` sono assenti (exit `127`): verifiche e aggiornamento di `.ai/CONTEXT.md` eseguiti manualmente. Deploy reale da riprogrammare sull'host Debian con IPv6 attivo. Rollback: `docker compose -f stacks/whoami-v6/compose.yml down` senza `-v` e ripristino del compose dal commit precedente.

### TASK-002 — Implementare preflight.sh e update-context.sh
- **ID:** TASK-002
- **Stato:** PROPOSED
- **Stack coinvolto:** `stacks/` (tooling di repository)
- **Descrizione:** Aggiungere gli script idempotenti `scripts/preflight.sh` (git status, spazio/inode, daemon Docker, validazione Compose di tutti gli stack) e `scripts/update-context.sh` (raccolta host, reti IPv6 e container in sola lettura), invocati dal flusso operativo ma attualmente assenti.
- **Criteri di verifica:** script eseguibili, shellcheck pulito se disponibile, exit `0` su host conforme e `1` con diagnostica su prerequisito mancante; nessuna modifica a rete, firewall, SSH o volumi.
- **Approvato da:** —
- **Note / rischi:** Solo aggiunta di tooling in sola lettura; nessun impatto sui servizi. Da approvare prima della prossima esecuzione automatizzata.
```
