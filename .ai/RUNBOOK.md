# RUNBOOK.md — Procedure operative standard

> Procedure eseguibili dall'agente nei limiti di `AGENTS.md`. Le azioni Tier 3 non sono coperte da questo runbook: vanno proposte in `## Pending Human Approval` dentro `.ai/REPORT.md` e lasciate all'operatore.
> Ogni sezione termina con la voce da registrare in `.ai/REPORT.md`.
> Tutti i comandi si eseguono dalla root del repository, `/opt/organic-server`, sul branch `host/<hostname>`.

## 1. Pre-flight check

Da eseguire all'inizio di ogni sessione, prima di qualsiasi modifica.

### 1.1 Contesto e repository

1. Leggere `AGENTS.md`, `.ai/CONTEXT.md`, `.ai/QUEUE.md`, `.ai/NETWORK.md` e questo runbook.
2. Verificare lo stato del repository:
   ```bash
   git status --short
   git branch --show-current
   git log --oneline -n 5
   ```
   Il working tree deve essere pulito sul branch `host/<hostname>`. Se ci sono modifiche non attribuibili alla sessione corrente, fermarsi e registrare l'anomalia.

### 1.2 Risorse host

```bash
date -u
uptime
df -h
df -i
free -m
```

**Blocco:** se il filesystem che ospita `/` o `/var/lib/docker` è oltre il
90% di spazio o di inode, non avviare pull, build o deploy. Registrare
l'output esatto e uscire con lo stato `BLOCKED`.

### 1.3 Docker daemon e Compose

```bash
systemctl is-active docker
docker version --format '{{.Server.Version}}'
docker compose version
```

Attesi: `active`, una versione del server Docker e Docker Compose v2. Se il
daemon non è attivo, non avviarlo e non riavviarlo: registrare l'errore e
uscire. Il riavvio del daemon Docker è un intervento infrastrutturale, non
un'operazione di routine dell'agente.

### 1.4 Sintassi Compose di tutti gli stack

```bash
for f in stacks/*/compose.yml; do
  docker compose -f "$f" config -q || {
    echo "INVALID: $f"
    exit 1
  }
done
```

Il comando è idempotente, non contatta il daemon e non applica nulla.
Include `stacks/_template/compose.yml`, che deve restare sempre valido.
Qualsiasi file non valido blocca la sessione: correggere solo se esiste un
task `APPROVED`, altrimenti registrare e uscire.

### 1.5 Rete, DNS e backup

```bash
ip -4 a
ip -6 a
ip -4 r
ip -6 r
ss -4 -tulnp
ss -6 -tulnp
getent ahostsv6 <fqdn>
```

Verificare la connettività in uscita IPv4 e IPv6 e la risoluzione DNS. Un
fallimento non autorizza a modificare rete o firewall.

Creare la directory di backup della sessione:

```bash
TS="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p ".backups/${TS}"
```

**Blocco:** se un comando di rete o DNS fallisce, non procedere con
aggiornamenti di pacchetti o immagini; registrare il diagnostico ed uscire.

**Log:** esito del pre-flight, versioni Docker/Compose, spazio libero e
anomalie rilevate.

## 2. Deploy di un singolo stack

Prerequisito: task in `.ai/QUEUE.md` con stato `APPROVED` e stack presente
in `stacks/`.

### 2.1 Nuovo stack: copia dal template

Ogni nuovo servizio parte da `stacks/_template`:

```bash
STACK="<nome-stack>"
test ! -e "stacks/${STACK}" || { echo "stack già esistente"; exit 1; }
cp -r stacks/_template "stacks/${STACK}"
```

Modificare poi `stacks/${STACK}/compose.yml` seguendo
`stacks/_template/README.md`. I vincoli di hardening (utente non-root,
`no-new-privileges`, `cap_drop: ALL`, `read_only`, `tmpfs`, rete dual-stack,
immagine pinnata, healthcheck) non vanno rimossi.

### 2.2 Controlli preliminari

```bash
STACK="<nome-stack>"
COMPOSE="stacks/${STACK}/compose.yml"

test -f "$COMPOSE"
docker compose -f "$COMPOSE" config -q
grep -nE 'docker\.sock|0\.0\.0\.0' "$COMPOSE"   # atteso: nessun output
```

Verificare che le porte interne non siano già in uso:

```bash
ss -6 -tulnp
ss -4 -tulnp
```

Verificare che il file dei segreti esista e abbia i permessi corretti, senza
stamparne il contenuto:

```bash
test -f "/etc/organic-server/secrets/${STACK}.env"
stat -c '%a %U:%G %n' "/etc/organic-server/secrets/${STACK}.env"
```

Attesi `600` e proprietario dell'operatore. In assenza del file, il deploy
può solo essere validato sintatticamente: non avviare il servizio.

### 2.3 Backup e commit della configurazione

Prima di applicare, copiare i file che verranno modificati e committare la
configurazione validata (Tier 2):

```bash
TS="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p ".backups/${TS}/${STACK}"
cp -a "$COMPOSE" ".backups/${TS}/${STACK}/"

git add "$COMPOSE"
git commit -m "chore(stacks): deploy ${STACK} configuration"
```

Se non ci sono modifiche da committare, `git commit` restituisce "nothing to
commit": è un esito accettabile, non un errore.

### 2.4 Applicazione dichiarativa

```bash
docker compose -f "$COMPOSE" pull
docker compose -f "$COMPOSE" up -d --remove-orphans
docker compose -f "$COMPOSE" ps
```

`up -d --remove-orphans` è idempotente: ricrea solo i container la cui
configurazione o immagine è cambiata e rimuove i servizi eliminati dal file.
Non usare `down` in questa fase: interromperebbe il servizio senza necessità.

### 2.5 Verifica healthcheck

```bash
for c in $(docker compose -f "$COMPOSE" ps -q); do
  docker inspect --format \
    '{{.Name}} state={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' \
    "$c"
done
```

Attesi `state=running` e `health=healthy`. Se lo stato è `starting`,
attendere una sola volta 15–20 secondi e ripetere la lettura (massimo 2
letture totali). Se lo stato è `unhealthy`, `exited` o `missing`, applicare
la sezione 4 e registrare l'errore.

Aggiornare `.ai/CONTEXT.md` con container, indirizzo IPv6, porte osservate e
stato dell'healthcheck.

**Retry:** massimo 2 tentativi per comando o servizio; poi stato `BLOCKED`
nel task e segnalazione in `.ai/REPORT.md`.

**Log:** comandi eseguiti, output di `ps`, stato degli healthcheck, hash del
commit.

## 3. Verifica esposizione dual-stack

Tutte le operazioni sono di sola lettura. Eseguire dopo ogni deploy e
durante ogni audit.

### 3.1 Socket IPv4 e IPv6

```bash
ss -4 -tulpn
ss -6 -tulpn
```

Atteso: le porte applicative pubblicate ascoltano su entrambe le famiglie
(`0.0.0.0` e `[::]`, oppure su indirizzi specifici autorizzati). Un listener
applicativo su una famiglia o una porta non prevista è un'anomalia da
annotare. Un listener di management (ad esempio `sshd`) è tollerato solo se
previsto e va annotato, non rimosso dall'agente.

### 3.2 Mapping porte Docker

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Le pubblicazioni dual-stack compaiono come `0.0.0.0:<porta>->...` e
`[::]:<porta>->...` (o `:::<porta>->...` nelle versioni precedenti).

### 3.3 Ispezione dei container e delle reti

```bash
COMPOSE="stacks/<nome-stack>/compose.yml"

for c in $(docker compose -f "$COMPOSE" ps -q); do
  docker inspect --format \
    '{{.Name}} ports={{json .NetworkSettings.Ports}} networks={{json .NetworkSettings.Networks}}' \
    "$c"
done
```

Verificare che:

- ogni `HostIp` in `NetworkSettings.Ports` sia `0.0.0.0`/`::` (o un indirizzo
  specifico autorizzato);
- ogni container abbia `GlobalIPv6Address` e `IPAddress` coerenti con
  `.ai/CONTEXT.md`.

```bash
docker network inspect edge \
  --format 'EnableIPv6={{.EnableIPv6}} internal={{.Internal}} ipam={{json .IPAM.Config}}'
docker network inspect internal \
  --format 'EnableIPv6={{.EnableIPv6}} internal={{.Internal}} ipam={{json .IPAM.Config}}'
```

Attesi: `EnableIPv6=true`; `Internal=false` su `edge`, `Internal=true` su
`internal`; configurazioni IPAM con una subnet IPv4 (RFC 1918) e una subnet
IPv6.

### 3.4 Probe dall'interno del container

```bash
docker exec <container> getent hosts <hostname>
docker exec <container> wget -q -O /dev/null 'http://[::1]:<porta>/'
docker exec <container> wget -q -O /dev/null 'http://127.0.0.1:<porta>/'
```

Adattare il probe all'immagine: verificare entrambe le famiglie.

**Blocco:** non modificare `nftables`, `/etc/docker/daemon.json`, interfacce
o `systemd-networkd` per "aggiustare" un'esposizione. Sono modifiche Tier 3.
Fermarsi, applicare la sezione 4 se il deploy è recente, e aprire un task.

**Log:** output dei due `ss`, mapping porte Docker, indirizzi IPv6 osservati
e ogni anomalia.

## 4. Rollback sicuro di uno stack

Da usare quando un deploy o una modifica tracciata produce un peggioramento
verificabile. Il rollback ripristina la configurazione e ricrea i container,
ma **non tocca i volumi persistenti**.

### 4.1 Fotografare lo stato corrente

```bash
STACK="<nome-stack>"
COMPOSE="stacks/${STACK}/compose.yml"
TS="$(date -u +%Y%m%dT%H%M%SZ)"

git status --short
docker compose -f "$COMPOSE" ps

mkdir -p ".backups/${TS}/${STACK}"
cp -a "$COMPOSE" ".backups/${TS}/${STACK}/"
```

### 4.2 Identificare il commit sano

```bash
git log --oneline -n 20 -- "$COMPOSE"
git show <commit-sano>:"$COMPOSE" | head -n 20
```

Usare l'ultimo commit nel quale lo stack funzionava, tipicamente
`<commit-guasto>^`. Non serve riscrivere la storia.

### 4.3 Ripristinare il solo file dello stack

```bash
git checkout <commit-sano> -- "$COMPOSE"
git diff -- "$COMPOSE"
```

`git checkout <commit> -- <path>` modifica solo quel file e lo mette in
staging; non sposta il branch e non tocca altri stack.

### 4.4 Validare e riapplicare

```bash
docker compose -f "$COMPOSE" config -q
docker compose -f "$COMPOSE" up -d --remove-orphans
docker compose -f "$COMPOSE" ps
```

`up -d --remove-orphans` ricrea i container con l'immagine e la
configurazione ripristinate. I volumi con nome restano montati e intatti;
i dati non vengono cancellati.

### 4.5 Verificare e committare il ripristino

Ripetere i controlli delle sezioni 2.5 e 3, poi:

```bash
git add "$COMPOSE"
git commit -m "revert(stacks): rollback ${STACK} to <commit-sano>"
```

Registrare in `.ai/REPORT.md` commit annullato, motivo ed esito; aggiornare
`.ai/CONTEXT.md`.

### 4.6 Divieti

Mai eseguire durante un rollback automatico:

- `docker compose down -v` o qualunque opzione `--volumes`;
- `docker volume rm`, `docker volume prune`, `docker system prune --volumes`;
- `git reset --hard`, `git clean -fd`, `git push --force`;
- cancellazione o spostamento di directory dati.

Se il ripristino del file non è sufficiente (ad esempio un'immagine è stata
eliminata dal registry), fermarsi, riportare lo stato `BLOCKED` e chiedere
intervento all'operatore.

**Log:** SHA ripristinato, comandi eseguiti, stato finale dei servizi e dei
volumi (solo lettura: `docker volume ls`).

## 5. Diagnostica IPv6 e container

Tutte le operazioni sono di sola lettura.

1. Interfacce e routing IPv6:
   ```bash
   ip -6 a
   ip -6 r
   ```
2. Socket in ascolto e relativi binding:
   ```bash
   ss -tulnp
   ss -6 -tulnp
   ```
3. Reti Docker e indirizzi assegnati:
   ```bash
   docker network ls
   docker network inspect <rete>
   docker inspect --format '{{json .NetworkSettings.Networks}}' <container>
   ```
4. Verifica che Docker abbia IPv6 attivo e subnet dual-stack:
   ```bash
   docker network inspect edge --format '{{json .EnableIPv6}} {{json .Options}}'
   docker network inspect internal --format '{{json .Internal}} {{json .IPAM.Config}}'
   docker run --rm --network edge alpine:3.20.3 ping -6 -c 3 <IPV6_TARGET>
   docker run --rm --network edge alpine:3.20.3 ping -4 -c 3 <IPV4_TARGET>
   ```
   Attesi: `EnableIPv6=true`, `com.docker.network.bridge.enable_ip_masquerade=true` (NAT IPv4) su `edge`, `Internal=false` su `edge` e `Internal=true` su `internal`, subnet IPv4+IPv6 coerenti con `.ai/CONTEXT.md` e risposta ICMPv6/ICMPv4 dal target. Il template versionato del daemon è `config/docker/daemon.json.example`; la sua applicazione a `/etc/docker/daemon.json` è Tier 3 e spetta all'operatore.
5. Risoluzione e raggiungibilità dall'interno del container:
   ```bash
   docker exec <container> getent hosts <hostname>
   docker exec <container> ping -6 -c 3 <hostname>
   ```
6. Regole firewall in sola lettura: `nft list ruleset`. Non modificare, ricaricare o svuotare le regole. Il baseline di riferimento è `config/nftables/organic-docker.nft.example` (Tier 3, solo operatore).
7. Ricordare che ICMPv6 (Neighbor Discovery, Router Advertisement, Packet Too Big) è obbligatorio: non proporre il blocco totale di ICMP.

**Blocco:** qualsiasi intervento su `nftables`, interfacce o `systemd-networkd` è Tier 3 e richiede approvazione umana.

**Log:** comando, output rilevante e diagnosi; aprire un task in `.ai/QUEUE.md` se serve una modifica.
