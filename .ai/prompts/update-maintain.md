# Playbook — Aggiornamento e manutenzione di uno stack

> **Trigger:** richieste di aggiornamento versione immagine, modifica di
> configurazione o riavvio di uno stack esistente (es. *"aggiorna Immich
> all'ultima versione"*, *"cambia la porta interna di Vaultwarden"*).
> **Tier di riferimento:** Tier 2 dopo validazione; nessuna modifica Tier 3.

## 0. Contesto e pre-flight

1. Leggere `AGENTS.md`, `.ai/CONTEXT.md`, `.ai/NETWORK.md`,
   `.ai/RUNBOOK.md` (sezioni 1–4) e il task `APPROVED` in `.ai/QUEUE.md`.
2. Individuare lo stack: `stacks/<nome-servizio>/compose.yml`.
3. Eseguire `./scripts/preflight.sh` (o i controlli manuali della sezione 1
   di `.ai/RUNBOOK.md` se lo script non è ancora presente). Non procedere se
   il filesystem è oltre il 90%, se il daemon Docker è inattivo o se la rete
   IPv6/DNS64 non risponde.
4. Fotografare lo stato corrente:

```bash
STACK="<nome-servizio>"
COMPOSE="stacks/${STACK}/compose.yml"

git status --short
docker compose -f "$COMPOSE" ps
docker compose -f "$COMPOSE" config -q
```

## 1. Verificare lo stack esistente

```bash
test -f "$COMPOSE"
docker compose -f "$COMPOSE" ps
docker compose -f "$COMPOSE" images
git log --oneline -n 5 -- "$COMPOSE"
```

Annotare immagine attuale, tag, `ipv6_address`, porte e stato healthcheck.
Confrontare con `.ai/CONTEXT.md`: una divergenza è un'anomalia da registrare
in `.ai/REPORT.md`.

## 2. Aggiornare il tag immagine

- Scegliere un tag di versione preciso o un digest immutabile.
- **Mai** `:latest` né tag mobili.
- Verificare le note di rilascio upstream per breaking change e migrazioni
  di schema prima di applicare.
- Se è richiesta una migrazione dati o una variabile d'ambiente nuova,
  fermarsi e chiedere conferma all'operatore prima del deploy.

```bash
grep -nE '^\s*image:' "$COMPOSE"
```

## 3. Modifiche di configurazione

- Ogni modifica deve preservare i vincoli di `AGENTS.md` sezioni 5–7:
  `cap_drop: ["ALL"]`, `no-new-privileges:true`, `read_only: true`,
  `user` non-root, `ipv4_address` + `ipv6_address` statici, nessun mount
  di `docker.sock`.
- Nuove porte interne: verificare che non siano già in uso
  (`ss -6 -tulpn`, `ss -4 -tulpn`) e registrarle in `.ai/CONTEXT.md`.
- Nuovi segreti: solo tramite `env_file` in `/etc/organic-server/secrets/`
  (permessi `0600`, directory `0700`). Nessun valore in Git.

## 4. Validare e committare la configurazione

```bash
docker compose -f "$COMPOSE" config        # exit code 0
grep -nE 'docker\.sock|privileged:\s*true|network_mode:\s*host' "$COMPOSE"   # atteso: nessun output
```

Eseguire `./scripts/preflight.sh` (o i controlli equivalenti del RUNBOOK).

Backup e commit Tier 2 prima di applicare:

```bash
TS="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p ".backups/${TS}/${STACK}"
cp -a "stacks/${STACK}" ".backups/${TS}/"

git add "stacks/${STACK}"
git commit -m "chore(stacks): update ${STACK} configuration"
```

## 5. Applicare

```bash
docker compose -f "$COMPOSE" pull
docker compose -f "$COMPOSE" up -d --remove-orphans
docker compose -f "$COMPOSE" ps
```

Non usare `down`: interromperebbe il servizio senza necessità. Non toccare
i volumi persistenti.

## 6. Verificare healthcheck ed esposizione

```bash
for c in $(docker compose -f "$COMPOSE" ps -q); do
  docker inspect --format \
    '{{.Name}} state={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' \
    "$c"
done

ss -4 -tulpn
ss -6 -tulpn
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Attesi: `state=running`, `health=healthy`, nessuna nuova porta non autorizzata.
Se lo stato è `starting`, attendere una sola volta 15–20 secondi e ripetere
(massimo 2 letture totali).

In caso di regressione funzionale, applicare anche una verifica del
servizio reale (endpoint health, log applicativi) senza mai stampare
segreti.

## 7. Circuit Breaker e rollback

- Massimo **2 tentativi consecutivi** per comando o servizio.
- Al secondo fallimento: stop immediato, nessuna terza prova e nessun
  workaround improvvisato.
- Rollback secondo `.ai/RUNBOOK.md` sezione 4:

```bash
git log --oneline -n 20 -- "$COMPOSE"
git checkout <commit-sano> -- "$COMPOSE"
docker compose -f "$COMPOSE" config -q
docker compose -f "$COMPOSE" up -d --remove-orphans
docker compose -f "$COMPOSE" ps
```

- Vietati: `docker compose down -v`, `docker volume rm/prune`,
  `git reset --hard`, `git clean -fd`, `git push --force`.
- Scrivere l'errore esatto in `.ai/REPORT.md`, marcare il task `BLOCKED` in
  `.ai/QUEUE.md` e terminare la sessione.

## 8. Aggiornare lo stato e committare

1. Aggiornare `.ai/CONTEXT.md` (versione immagine, eventuali indirizzi/porte
   cambiati) con `./scripts/update-context.sh` o manualmente se lo script
   non è disponibile.
2. Appendere la sessione in `.ai/REPORT.md`: versione precedente/nuova,
   comandi, esito healthcheck, anomalie.
3. Aggiornare `.ai/QUEUE.md` (`DONE` / `BLOCKED`).
4. Commit atomico:

```bash
git add stacks/${STACK} .ai/CONTEXT.md .ai/REPORT.md .ai/QUEUE.md
git commit -m "chore(stacks): update ${STACK} to <version>"
```

## Divieti specifici

- Aggiornamenti a tag mobili o `latest`.
- Modifiche a `nftables`, `/etc/docker/daemon.json`, interfacce o
  `systemd-networkd` (Tier 3).
- Riavvio del daemon Docker o della rete di management.
- Qualunque operazione che cancelli volumi o dati persistenti.
