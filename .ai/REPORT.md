# REPORT.md — Log cronologico delle esecuzioni

> Registro append-only: una voce per sessione, in ordine cronologico, dalla più vecchia alla più recente.
> Ogni voce riporta azioni, esito, errori esatti e follow-up. Le richieste che richiedono intervento umano vanno in `## Pending Human Approval`.

| Campo | Valore |
| :--- | :--- |
| Formato data | `YYYY-MM-DD HH:MM` (fuso del server, variabile `TZ`) |
| Retry massimo | 2 tentativi per comando o servizio |
| Responsabile Tier 3 | operatore umano |

## Pending Human Approval

> Modifiche Tier 3 richieste dall'agente: l'agente si ferma e attende l'operatore.
> Per ogni richiesta indicare comandi proposti, motivazione e rischio.

_Nessuna richiesta pendente._

## Esecuzioni

### 2026-11-25 09:40 — Dry-run stack pilota IPv6-only (`TASK-001`)
- **Agente:** OpenCode Agent — DeepSeek V4.1 Flash 1017 (OpenCode / provider `deepseek` / model `deepseek-flash`)
- **Scope:** `TASK-001` — `stacks/whoami-v6`
- **Azioni:**
  1. `TASK-001` registrato in `.ai/QUEUE.md` come `IN_PROGRESS` e poi chiuso `DONE`.
  2. Creato `stacks/whoami-v6/compose.yml` da `stacks/_template/compose.yml`: `traefik/whoami:v1.10.3`, `user: "65534:65534"`, `cap_drop: [ALL]`, `no-new-privileges:true`, `read_only: true`, `tmpfs` limitati, solo rete `edge-v6` con `ipv6_address: fd00:dead:beef:20::10`, nessun `ports:`.
  3. Eseguito `./scripts/preflight.sh`: file assente, exit `127`.
  4. Pre-flight equivalente manuale: `git status --short` pulito, `df -h /c` al 54%, `command -v docker` fallito, `systemctl` e `ss` non disponibili.
  5. `docker compose -f stacks/whoami-v6/compose.yml config` con Docker Compose v2.40.3 standalone: exit `0`.
  6. `docker compose ... up -d` non eseguito: daemon Docker assente, quindi fermato alla validazione come previsto dal task condizionale. Nessun container parziale creato.
  7. Eseguito `./scripts/update-context.sh`: file assente, exit `127`; `.ai/CONTEXT.md` aggiornato manualmente.
- **Controlli di sicurezza:**
  - **IPv4 exposure:** verifica runtime `ss -4 -tulpn` non eseguibile (comando assente). Verifica statica sul compose superata: nessun `ports:`, nessuna occorrenza di `0.0.0.0`.
  - **cap_drop:** `ALL` presente e confermato dall'output di `compose config`.
  - **read_only:** `true` presente e confermato dall'output di `compose config`.
  - **Utente:** `65534:65534` (non-root), confermato dall'output di `compose config`.
  - **Docker socket:** nessun mount di `docker.sock`.
  - **Healthcheck:** disabilitato esplicitamente perché l'immagine `traefik/whoami` è scratch (nessuna shell/probe interna); l'endpoint `/health` va verificato dall'esterno su IPv6.
- **Esito:** `PARTIAL` — stack creato e validato staticamente; deploy e verifiche runtime rinviati per assenza di Docker con IPv6 nell'ambiente di esecuzione.
- **Errori:**
  - `./scripts/preflight.sh: No such file or directory` (exit `127`).
  - `./scripts/update-context.sh: No such file or directory` (exit `127`).
  - `docker`: comando non trovato; `systemctl`: comando non trovato; `ss`: comando non trovato.
- **Follow-up:** `TASK-002` proposto in `.ai/QUEUE.md` per implementare gli script mancanti. Eseguire il deploy reale e i controlli `ss -4` / `ss -6` sull'host Debian con Docker e IPv6 attivi. Nessuna modifica Tier 3 effettuata (`/etc/docker/daemon.json` intatto).
- **Commit:** `feat(pilot): add hardened ipv6-only whoami stack and log execution report` — SHA non auto-referenziabile nel contenuto del commit; verificare con `git log -1 --format=%H`.

---

### 2026-11-25 — Migrazione dual-stack e implementazione script (`TASK-002`, `TASK-003`)
- **Agente:** OpenCode Agent — DeepSeek
- **Scope:** intera repository
- **Azioni:**
  1. Implementati `scripts/preflight.sh` e `scripts/update-context.sh` (`TASK-002`, gap CRITICAL dell'audit: script referenziati ma assenti).
  2. Migrazione IPv6-only → dual-stack (`TASK-003`): reti rinominate `edge`/`internal` con subnet IPv4 (RFC 1918) + IPv6; `daemon.json.example` e `nftables.example` aggiornati per entrambe le famiglie.
  3. Aggiornati guardrail e documentazione (`AGENTS.md` §6, `NETWORK.md`, `RUNBOOK.md`, 4 playbook, template, `README.md`, `.env.example`, stato).
  4. Stack pilota rinominato `stacks/whoami-v6` → `stacks/whoami`, con `ipv4_address` + `ipv6_address` statici (`.20`/`::20`).
  5. Corretto il tag flottante `alpine:3` → `alpine:3.20.3` in `stacks/_network/compose.yml` e il meccanismo dell'anchor.
  6. Fix audit: scan segreti non esclude più `.ai/*`; `git check-ignore` non include più `logs/`; aggiunto grep `disable: true` per gli healthcheck.
- **Controlli di sicurezza:**
  - Hardening preservato su tutti i compose (`cap_drop: ALL`, `no-new-privileges`, `read_only`, `user` non-root, nessun `docker.sock`/`privileged`/`network_mode: host`).
  - Nessun segreto tracciato.
- **Esito:** `DONE` (dry-run; deploy reale da eseguire sull'host Debian con Docker dual-stack).
- **Follow-up:** applicare `daemon.json.example` e `nftables.example` (Tier 3, solo operatore); eseguire il deploy reale e i controlli `ss -4`/`ss -6` sull'host.
- **Commit:** commit atomico successivo (`feat(network): migrate to dual-stack and add preflight/update-context scripts`).

---
