# CONTEXT.md — Stato corrente del sistema

> Snapshot **fattuale** del server. Nessuna ipotesi e nessun valore inventato: ogni cella va popolata con l'output di un comando o di uno script in `scripts/`.
> Aggiornato dagli script di audit (Tier 1). Le celle vuote indicano un dato non ancora raccolto.

> **Stato 2026-11-25:** snapshot aggiornato durante il dry-run `TASK-001` su una workstation Windows senza Docker CLI/daemon (`ACC-CYBE20`), non sul server Debian. I valori "non disponibile" / "dichiarato" descrivono l'ambiente di esecuzione e la configurazione validata, non lo stato reale del server: vanno sovrascritti al primo audit eseguito sull'host Debian.

| Campo | Valore |
| :--- | :--- |
| Ultimo aggiornamento (UTC) | 2026-11-25 09:40 |
| Hostname | ACC-CYBE20 (workstation di dry-run) |
| Eseguito da | OpenCode Agent — DeepSeek V4.1 Flash 1017 |
| Branch Git | `main` |

## Host & Runtime

| Parametro | Valore |
| :--- | :--- |
| OS | Microsoft Windows 11 Enterprise 10.0.26200 (workstation; target Debian non raggiunto) |
| Kernel | Non rilevato (ambiente Windows) |
| Docker Engine | Non disponibile: CLI e daemon assenti |
| nftables | Non disponibile nell'ambiente di dry-run |

Comandi di riferimento: `cat /etc/os-release`, `uname -r`, `docker version --format '{{.Server.Version}}'`, `systemctl is-active nftables`, `nft list ruleset` (sola lettura).

## Reti Docker IPv6

| Nome rete | Subnet IPv6 | Gateway | Internal |
| :--- | :--- | :--- | :--- |
| `edge-v6` (dichiarata, non creata) | `fd00:dead:beef:20::/64` | `fd00:dead:beef:20::1` | `false` |
| `internal-v6` (dichiarata, non creata) | `fd00:dead:beef:30::/64` | `fd00:dead:beef:30::1` | `true` |

Comandi di riferimento: `docker network ls`, `docker network inspect <rete>`.
Le subnet provengono da `stacks/_network/compose.yml`; la creazione sull'host non è stata verificata perché il daemon Docker non è disponibile.

## Stack e Container Attivi

| Stack | Servizio | Indirizzo IPv6 | Porte esposte | Healthcheck |
| :--- | :--- | :--- | :--- | :--- |
| `whoami-v6` (validato, non avviato) | `whoami` | `fd00:dead:beef:20::10` (dichiarato) | Nessuna pubblicata; solo `edge-v6`, `expose 8080` | Disabilitato: immagine scratch senza probe; verifica esterna su `/health` |

Comandi di riferimento: `docker compose ls`, `docker compose ps`, `docker inspect --format '{{json .NetworkSettings.Networks}}' <container>`.
Nessun container è attivo: il deploy è stato interrotto alla validazione statica per assenza del daemon Docker. La riga `whoami-v6` descrive la configurazione validata, non un container in esecuzione.

## Note dry-run TASK-001

- `./scripts/preflight.sh` e `./scripts/update-context.sh` non esistono nel repository: entrambi gli invocativi sono terminati con exit `127`. Le verifiche pre-flight sono state eseguite manualmente e questo file è stato aggiornato a mano.
- `docker compose -f stacks/whoami-v6/compose.yml config` è terminato con exit `0` usando Docker Compose v2.40.3 standalone.
- Verifica statica del compose: `user: "65534:65534"`, `cap_drop: [ALL]`, `no-new-privileges:true`, `read_only: true`, nessun `ports:`, nessun binding IPv4, nessun mount di `docker.sock`.
- Controlli runtime non eseguiti per assenza di Docker e `ss`: `docker compose up -d`, raggiungibilità IPv6 del container, `ss -4 -tulpn`, `ss -6 -tulpn`. Nessun container parziale da rimuovere.
- Nessun segreto è stato letto, scritto o registrato.
