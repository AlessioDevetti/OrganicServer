# RUNBOOK.md — Procedure operative standard

> Procedure eseguibili dall'agente nei limiti di `AGENTS.md`. Le azioni Tier 3 non sono coperte da questo runbook: vanno proposte in `## Pending Human Approval` dentro `.ai/REPORT.md` e lasciate all'operatore.
> Ogni sezione termina con la voce da registrare in `.ai/REPORT.md`.

## 1. Pre-flight check

Da eseguire all'inizio di ogni sessione, prima di qualsiasi modifica.

1. Leggere `AGENTS.md`, `.ai/CONTEXT.md`, `.ai/QUEUE.md` e questo runbook.
2. Verificare lo stato del repository: `git status` deve essere pulito sul branch `host/<hostname>`.
3. Rilevare il contesto host (sola lettura):
   ```bash
   date -u
   uptime
   df -h
   free -m
   systemctl is-active docker
   ss -tulnp
   ip -4 a && ip -6 a
   ip -4 r && ip -6 r
   ```
4. Verificare la connettività in uscita e la risoluzione DNS su entrambe le famiglie.
5. Verificare che esista la directory di backup della sessione: `.backups/<timestamp>/`.

**Blocco:** se un comando di rete o DNS fallisce, non procedere con aggiornamenti di pacchetti o immagini; registrare il diagnostico ed uscire.

**Log:** esito del pre-flight e anomalie rilevate.

## 2. Validazione e Deploy di uno stack

Prerequisito: task in `.ai/QUEUE.md` con stato `APPROVED` e stack presente in `stacks/` (o `manifests/` per gli asset non ancora migrati).

1. Validare la configurazione senza applicarla:
   ```bash
   docker compose -f <file-compose> config -q
   ```
2. Verificare che le porte dichiarate non siano già in uso: `ss -tulnp`.
3. Verificare che i binding interni siano su `127.0.0.1` / `[::1]` o su rete interna, non su `0.0.0.0` / `[::]`, salvo esposizione esplicita via reverse proxy.
4. Copiare i file che verranno modificati in `.backups/<timestamp>/`.
5. Applicare in modo dichiarativo:
   ```bash
   docker compose -f <file-compose> pull
   docker compose -f <file-compose> up -d
   ```
6. Verificare lo stato e gli healthcheck:
   ```bash
   docker compose -f <file-compose> ps
   docker inspect --format '{{.State.Health.Status}}' <container>
   ```
7. Aggiornare `.ai/CONTEXT.md` con container, indirizzi IPv6 e porte osservate.

**Rollback:** in caso di esito negativo, applicare la sezione 4 e ripristinare i file da `.backups/<timestamp>/`.

**Retry:** massimo 2 tentativi; poi stato `BLOCKED` nel task e segnalazione in `.ai/REPORT.md`.

**Log:** comandi eseguiti, output di `ps`, stato healthcheck, hash del commit.

## 3. Diagnostica IPv6 e Container

Tutte le operazioni sono di sola lettura.

1. Interfacce e routing IPv6:
   ```bash
   ip -6 a
   ip -6 r
   ```
2. Socket in ascolto e relativi binding:
   ```bash
   ss -tulnp
   ```
3. Reti Docker e indirizzi assegnati:
   ```bash
   docker network ls
   docker network inspect <rete>
   docker inspect --format '{{json .NetworkSettings.Networks}}' <container>
   ```
4. Verifica che Docker abbia IPv6 attivo e nessun masquerading IPv6:
   ```bash
   docker network inspect edge-v6 --format '{{json .EnableIPv6}} {{json .Options}}'
   docker network inspect internal-v6 --format '{{json .Internal}} {{json .IPAM.Config}}'
   docker run --rm --network edge-v6 alpine:3 ping -6 -c 3 <IPV6_TARGET>
   ```
   Attesi: `EnableIPv6=true`, `com.docker.network.bridge.enable_ip_masquerade=false`, `Internal=false` su `edge-v6` e `Internal=true` su `internal-v6`, subnet coerenti con `.ai/CONTEXT.md` e risposta ICMPv6 dal target. Il template versionato del daemon è `config/docker/daemon.json.example`; la sua applicazione a `/etc/docker/daemon.json` è Tier 3 e spetta all'operatore.
5. Risoluzione e raggiungibilità dall'interno del container:
   ```bash
   docker exec <container> getent hosts <hostname>
   docker exec <container> ping -6 -c 3 <hostname>
   ```
6. Regole firewall in sola lettura: `nft list ruleset`. Non modificare, ricaricare o svuotare le regole. Il baseline di riferimento è `config/nftables/organic-docker.nft.example` (Tier 3, solo operatore).
7. Ricordare che ICMPv6 (Neighbor Discovery, Router Advertisement, Packet Too Big) è obbligatorio: non proporre il blocco totale di ICMP.

**Blocco:** qualsiasi intervento su `nftables`, interfacce o `systemd-networkd` è Tier 3 e richiede approvazione umana.

**Log:** comando, output rilevante e diagnosi; aprire un task in `.ai/QUEUE.md` se serve una modifica.

## 4. Procedura di Rollback via Git

Da usare quando un deploy o una modifica di configurazione tracciata produce un peggioramento verificabile.

1. Identificare il commit da annullare:
   ```bash
   git log --oneline -n 20
   git status
   ```
2. Annullare in modo non distruttivo, preferendo `git revert`:
   ```bash
   git revert --no-edit <sha>
   ```
   Per ripristinare un singolo file da un commit noto:
   ```bash
   git checkout <sha> -- <path>
   ```
3. Ripristinare eventuali file non tracciati da `.backups/<timestamp>/`.
4. Riapplicare lo stack interessato e verificarne lo stato:
   ```bash
   docker compose -f <file-compose> up -d
   docker compose -f <file-compose> ps
   ```
5. Confermare il ripristino con i controlli della sezione 3.
6. Registrare in `.ai/REPORT.md` il commit annullato, il motivo e l'esito; aggiornare `.ai/CONTEXT.md`.

**Divieto:** non usare `git reset --hard`, `git clean -fd` o `git push --force` durante un rollback automatico.

**Log:** SHA annullato, comandi eseguiti, stato finale dei servizi.
