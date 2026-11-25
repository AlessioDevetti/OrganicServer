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
| TASK-001 | DONE | `stacks/whoami` | Stack pilota hardened dual-stack su `edge`; dry-run con pre-flight, validazione Compose e aggiornamento stato. | `docker compose config` exit `0`; hardening preservato; report e context aggiornati. |
| TASK-002 | DONE | `scripts/` (tooling) | Implementare gli script `scripts/preflight.sh` e `scripts/update-context.sh`, invocati dal flusso operativo. | Script presenti, idempotenti, in sola lettura, exit `0`/`1` documentato. |
| TASK-003 | DONE | intera repository | Migrazione dell'architettura da IPv6-only a dual-stack (IPv4 + IPv6) e allineamento documentale. | Guardrail, playbook, template e config coerenti con il dual-stack; reti `edge`/`internal`. |

## Dettaglio dei task

```markdown
### TASK-001 — Stack pilota whoami (dry-run dual-stack)
- **ID:** TASK-001
- **Stato:** DONE
- **Stack coinvolto:** `stacks/whoami`
- **Descrizione:** Creare uno stack pilota leggero e hardened (`traefik/whoami:v1.10.3`) collegato solo a `edge`, eseguire il pre-flight, validare la configurazione Compose e, se il daemon Docker è disponibile, avviarlo e verificarne la raggiungibilità dual-stack.
- **Criteri di verifica:** `./scripts/preflight.sh` exit `0`; `docker compose -f stacks/whoami/compose.yml config` exit `0`; hardening preservato; `.ai/CONTEXT.md` e `.ai/REPORT.md` aggiornati.
- **Approvato da:** Operatore — 2026-11-25 (istruzione di sessione)
- **Note / rischi:** Dry-run completato con esito `PARTIAL` (ambiente senza Docker). Migrato a dual-stack in `TASK-003`. Deploy reale da riprogrammare sull'host Debian.

### TASK-002 — Implementare preflight.sh e update-context.sh
- **ID:** TASK-002
- **Stato:** DONE
- **Stack coinvolto:** `scripts/` (tooling di repository)
- **Descrizione:** Aggiungere gli script idempotenti `scripts/preflight.sh` (stato git, daemon Docker, validazione Compose, hardening) e `scripts/update-context.sh` (raccolta host, reti dual-stack e container in sola lettura).
- **Criteri di verifica:** script eseguibili con `set -euo pipefail`, exit `0`/`1` documentato; nessuna modifica a rete, firewall, SSH o volumi; `update-context.sh` non legge né scrive `Config.Env`.
- **Approvato da:** Operatore — 2026-11-25 (istruzione di sessione)
- **Note / rischi:** Solo tooling in sola lettura; nessun impatto sui servizi.

### TASK-003 — Migrazione dual-stack e coerenza
- **ID:** TASK-003
- **Stato:** DONE
- **Stack coinvolto:** intera repository
- **Descrizione:** Passare da architettura IPv6-only a dual-stack (IPv4 + IPv6 paritari): reti `edge`/`internal` con subnet IPv4 (RFC 1918) + IPv6; aggiornare guardrail (`AGENTS.md`), `NETWORK.md`, `RUNBOOK.md`, playbook, template, `daemon.json.example`, `nftables.example`, `.env.example` e stato.
- **Criteri di verifica:** nessun riferimento residuo a `edge-v6`/`internal-v6`/`IPv6-only`; `preflight.sh` non flagga più `0.0.0.0`; template e playbook coerenti con il dual-stack.
- **Approvato da:** Operatore — 2026-11-25 (istruzione di sessione)
- **Note / rischi:** Nessun impatto Tier 3: modificati solo file di repository e `.example`; l'applicazione di `daemon.json`/`nftables` sull'host resta Tier 3 (solo operatore).
```
