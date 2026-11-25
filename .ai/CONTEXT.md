# CONTEXT.md — Stato corrente del sistema

> Snapshot **fattuale** del server. Nessuna ipotesi e nessun valore inventato: ogni cella va popolata con l'output di un comando o di uno script in `scripts/`.
> Aggiornato dagli script di audit (Tier 1). Le celle vuote indicano un dato non ancora raccolto.

| Campo | Valore |
| :--- | :--- |
| Ultimo aggiornamento (UTC) | |
| Hostname | |
| Eseguito da | |
| Branch Git | |

## Host & Runtime

| Parametro | Valore |
| :--- | :--- |
| OS | |
| Kernel | |
| Docker Engine | |
| nftables | |

Comandi di riferimento: `cat /etc/os-release`, `uname -r`, `docker version --format '{{.Server.Version}}'`, `systemctl is-active nftables`, `nft list ruleset` (sola lettura).

## Reti Docker IPv6

| Nome rete | Subnet IPv6 | Gateway | Internal |
| :--- | :--- | :--- | :--- |

Comandi di riferimento: `docker network ls`, `docker network inspect <rete>`.

## Stack e Container Attivi

| Stack | Servizio | Indirizzo IPv6 | Porte esposte | Healthcheck |
| :--- | :--- | :--- | :--- | :--- |

Comandi di riferimento: `docker compose ls`, `docker compose ps`, `docker inspect --format '{{json .NetworkSettings.Networks}}' <container>`.
