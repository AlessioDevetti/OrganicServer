# Playbook — Deploy di un nuovo stack

> **Trigger:** richieste di installazione, creazione o deploy di un nuovo
> servizio/stack (es. *"installa Nginx Proxy Manager"*, *"crea uno stack per
> Vaultwarden"*).
> **Tier di riferimento:** Tier 2 dopo validazione; ogni passo resta soggetto
> ai vincoli Tier 1–3 di `AGENTS.md`.

## 0. Contesto obbligatorio (prima di ogni comando)

1. Leggere `AGENTS.md`, `.ai/CONTEXT.md`, `.ai/QUEUE.md`, `.ai/NETWORK.md` e
   `.ai/RUNBOOK.md` (sezioni 1–3).
2. Verificare che esista un task `APPROVED` in `.ai/QUEUE.md` per lo stack.
   In assenza del task, fermarsi e chiedere approvazione all'operatore.
3. Chiarire i requisiti mancanti prima di scrivere file (vedi
   *Chiarimento preventivo* in `AGENTS.md`):
   - nome del servizio e nome dello stack;
   - se il servizio deve essere esposto su `edge` o isolato su
     `internal`;
   - variabili d'ambiente e segreti obbligatori;
   - porta interna, volume persistente e UID/GID dei dati.
4. Eseguire il pre-flight: `./scripts/preflight.sh`. Se lo script non è
   ancora presente nella repository, eseguire manualmente i controlli della
   sezione 1 di `.ai/RUNBOOK.md` (stato Git, spazio/inode, Docker, sintassi
   Compose, rete/DNS IPv6) e non proseguire in caso di blocco.

## 1. Creare lo stack dal template

```bash
STACK="<nome-stack>"
test ! -e "stacks/${STACK}" || { echo "stack già esistente"; exit 1; }
cp -r stacks/_template "stacks/${STACK}"
```

Seguire `stacks/_template/README.md` per i campi da modificare.

## 2. Immagine pinnata

- Usare un tag di versione preciso o, meglio, un digest immutabile
  (`image@sha256:...`).
- **Mai** `:latest` né tag mobili (`:stable`, `:main`, `:edge`).
- Se non esiste un tag stabile, fermarsi e chiedere indicazione all'operatore.

## 3. Indirizzi statici (IPv4 + IPv6)

- Scegliere la rete in base al ruolo, secondo `.ai/NETWORK.md`:
  - backend, database e servizi interni → `internal`, host ID da `.10`/`::10`
    in su;
  - solo reverse proxy e servizi esposti → `edge`, host ID da `.20`/`::20`
    in su.
- Mai collegare un backend a `edge`.
- Gli indirizzi devono essere liberi: verificare `.ai/CONTEXT.md` e le reti
  esistenti prima di assegnarli. Non inventare prefissi: usare quelli
  registrati in `.ai/CONTEXT.md`.
- Dichiarare la rete come esterna (`external: true`); non ridefinire
  `edge` / `internal` nello stack.

```yaml
networks:
  internal:
    ipv4_address: "<INTERNAL_V4>::10"
    ipv6_address: "<ULA_SUBNET>::10"
```

## 4. Hardening obbligatorio (non rimovibile)

Mantenere in `stacks/${STACK}/compose.yml`:

- `user:` non-root esplicito (mai `root`, mai UID `0`);
- `security_opt: ["no-new-privileges:true"]`;
- `cap_drop: ["ALL"]` (eventuali `cap_add` singoli, motivati e approvati);
- `read_only: true` con `tmpfs` limitati per i path scrivibili;
- `restart: unless-stopped`;
- `healthcheck` reale (`[::1]`/`127.0.0.1` o indirizzo del servizio);
- nessun mount di `docker.sock` o altri socket del runtime;
- nessun `privileged`, `pid: host`, `network_mode: host`, `ipc: host`;
- pubblicazione porte solo tramite il reverse proxy su `edge`, dual-stack
  (`"<porta>:<porta>"` espone su entrambe le famiglie); per i servizi
  interni usare solo `expose:`.

## 5. Segreti

- Nessun valore reale in `compose.yml`, `.env.example`, README o Git.
- Configurare i segreti tramite `env_file` esterno:

```yaml
env_file:
  - path: /etc/organic-server/secrets/<nome-stack>.env
    required: false
```

- Il file reale è creato dall'operatore, permessi `0600` (directory `0700`).
  Verificare l'esistenza senza stamparne il contenuto:

```bash
test -f "/etc/organic-server/secrets/${STACK}.env"
stat -c '%a %U:%G %n' "/etc/organic-server/secrets/${STACK}.env"
```

Se il file manca, il deploy può solo essere validato sintatticamente: non
avviare il servizio.

## 6. Validare

```bash
COMPOSE="stacks/${STACK}/compose.yml"

docker compose -f "$COMPOSE" config          # exit code 0
grep -nE 'docker\.sock|privileged:\s*true|network_mode:\s*host' "$COMPOSE"   # atteso: nessun output
docker compose -f "$COMPOSE" config -q
```

Eseguire `./scripts/preflight.sh` (o i controlli equivalenti di
`.ai/RUNBOOK.md` sez. 1) prima di applicare.

## 7. Backup e commit della configurazione

Prima di applicare (Tier 2):

```bash
TS="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p ".backups/${TS}/${STACK}"
cp -a "stacks/${STACK}" ".backups/${TS}/"

git add "stacks/${STACK}"
git commit -m "chore(stacks): deploy ${STACK} configuration"
```

## 8. Deploy

```bash
docker compose -f "$COMPOSE" pull
docker compose -f "$COMPOSE" up -d --remove-orphans
docker compose -f "$COMPOSE" ps
```

Non usare `down` e non toccare i volumi persistenti.

## 9. Verifica

```bash
# Healthcheck
for c in $(docker compose -f "$COMPOSE" ps -q); do
  docker inspect --format \
    '{{.Name}} state={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' \
    "$c"
done

# Esposizione porte
ss -4 -tulnp
ss -6 -tulpn
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Attesi: `state=running` e `health=healthy`; porte pubblicate su entrambe le
famiglie (`0.0.0.0` e `[::]`), coerenti con `.ai/CONTEXT.md`.

**Circuit Breaker:** massimo 2 tentativi consecutivi per comando o servizio.
Al secondo fallimento fermarsi, ripristinare la configurazione precedente
(`git checkout -- <path>` oppure il commit sano), scrivere l'errore esatto in
`.ai/REPORT.md`, marcare il task `BLOCKED` in `.ai/QUEUE.md` e terminare la
sessione.

## 10. Aggiornare lo stato e committare

1. Aggiornare `.ai/CONTEXT.md` — preferibilmente con
   `./scripts/update-context.sh`; se lo script non è ancora disponibile,
   aggiornare a mano container, `ipv4_address`, `ipv6_address`, porte e stato
   healthcheck. Registrare la tupla `(container, ipv4_address, ipv6_address, porte)`.
2. Appendere la sessione in `.ai/REPORT.md`: comandi, esito, anomalie,
   follow-up.
3. Aggiornare lo stato del task in `.ai/QUEUE.md` (`DONE` o `BLOCKED`).
4. `git status` e commit atomico:

```bash
git add stacks/${STACK} .ai/CONTEXT.md .ai/REPORT.md .ai/QUEUE.md
git commit -m "feat(stacks): add hardened dual-stack ${STACK} stack"
```

## Divieti specifici

- Pubblicare porte non autorizzate in `nftables`/`.ai/CONTEXT.md`, o creare
  reti/subnet ad-hoc.
- Rimuovere i campi di hardening del template.
- Modificare `nftables`, `/etc/docker/daemon.json`, interfacce o
  `systemd-networkd` (Tier 3).
- `docker volume rm`, `docker volume prune`, `docker compose down -v`.
- Istruzioni `unhealthy` nascoste: ogni anomalia va in `.ai/REPORT.md`.
