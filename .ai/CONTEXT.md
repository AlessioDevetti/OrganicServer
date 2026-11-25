# CONTEXT.md — Stato corrente del sistema

> Snapshot **fattuale** del server. Nessuna ipotesi e nessun valore inventato: ogni cella va popolata con l'output di un comando o di uno script in `scripts/`.
> Aggiornato da `scripts/update-context.sh` (Tier 1). Le celle vuote indicano un dato non ancora raccolto.

> **Stato 2026-11-25:** snapshot aggiornato durante il dry-run `TASK-001` su una workstation Windows senza Docker CLI/daemon (`ACC-CYBE20`), non sul server Debian. I valori "non disponibile" / "dichiarato" descrivono l'ambiente di esecuzione e la configurazione validata, non lo stato reale del server: vanno sovrascritti al primo audit eseguito sull'host Debian.

| Campo | Valore |
| :--- | :--- |
| Ultimo aggiornamento (UTC) | 2026-11-25 09:40 |
| Hostname | ACC-CYBE20 (workstation di dry-run) |
| Eseguito da | OpenCode Agent — DeepSeek |
| Branch Git | `main` |

## Host & Runtime

| Parametro | Valore |
| :--- | :--- |
| OS | Microsoft Windows 11 Enterprise 10.0.26200 (workstation; target Debian non raggiunto) |
| Kernel | Non rilevato (ambiente Windows) |
| Docker Engine | Non disponibile: CLI e daemon assenti |
| nftables | Non disponibile nell'ambiente di dry-run |

Comandi di riferimento: `cat /etc/os-release`, `uname -r`, `docker version --format '{{.Server.Version}}'`, `systemctl is-active nftables`, `nft list ruleset` (sola lettura).

## Reti Docker (dual-stack)

| Nome rete | Subnet IPv4 | Subnet IPv6 | Internal |
| :--- | :--- | :--- | :--- |
| `edge` (dichiarata, non creata) | `172.20.0.0/24` | `fd00:dead:beef:20::/64` | `false` |
| `internal` (dichiarata, non creata) | `172.30.0.0/24` | `fd00:dead:beef:30::/64` | `true` |

Comandi di riferimento: `docker network ls`, `docker network inspect <rete>`.
Le subnet provengono da `stacks/_network/compose.yml`; la creazione sull'host non è stata verificata perché il daemon Docker non è disponibile. La subnet IPv6 di `edge` è un placeholder ULA: va sostituita con una slice del prefisso provider in produzione.

## Stack e Container Attivi

| Stack | Servizio | Indirizzi | Porte esposte | Healthcheck |
| :--- | :--- | :--- | :--- | :--- |
| `whoami` (validato, non avviato) | `whoami` | `172.20.0.20` / `fd00:dead:beef:20::20` (dichiarati) | Nessuna pubblicata; solo `edge`, `expose 8080` | Disabilitato: immagine scratch senza probe; verifica esterna su `/health` |

Comandi di riferimento: `docker compose ls`, `docker compose ps`, `docker inspect --format '{{json .NetworkSettings.Networks}}' <container>`.
Nessun container è attivo: il deploy è stato interrotto alla validazione statica per assenza del daemon Docker. La riga `whoami` descrive la configurazione validata, non un container in esecuzione.

## Note dry-run TASK-001

- `scripts/preflight.sh` e `scripts/update-context.sh` sono ora presenti nel repository (implementati in `TASK-002`); su questo host senza Docker terminano con esito non-bloccante.
- `docker compose -f stacks/whoami/compose.yml config` è stato validato staticamente (Compose v2.40.3, exit `0`).
- Verifica statica del compose: `user: "65534:65534"`, `cap_drop: [ALL]`, `no-new-privileges:true`, `read_only: true`, `ipv4_address` + `ipv6_address` statici, nessun mount di `docker.sock`, nessun `privileged`.
- Controlli runtime non eseguiti per assenza di Docker e `ss`: `docker compose up -d`, raggiungibilità dual-stack del container, `ss -4 -tulpn`, `ss -6 -tulpn`. Nessun container parziale da rimuovere.
- Nessun segreto è stato letto, scritto o registrato.
