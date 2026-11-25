# Playbook — Security audit

> **Trigger:** richieste di verifica sicurezza, controllo esposizione IPv4 o
> audit della repository (es. *"fai un audit di sicurezza"*, *"controlla che
> non ci siano porte IPv4 esposte"*).
> **Tier di riferimento:** interamente **read-only Tier 1**. Nessuna
> correzione viene applicata durante l'audit: le anomalie diventano task in
> `.ai/QUEUE.md` e voci in `.ai/REPORT.md`.

## 0. Contesto

1. Leggere `AGENTS.md`, `.ai/CONTEXT.md`, `.ai/NETWORK.md`,
   `.ai/RUNBOOK.md` (sezioni 1, 3 e 5).
2. Verificare lo stato del repository (`git status --short`,
   `git branch --show-current`, `git log --oneline -n 5`).
3. Non modificare file di sistema, rete, firewall o container durante la
   fase di raccolta.

## 1. Esposizione IPv4

```bash
ss -4 -tulpn
ss -4 -tulpn | grep -F 'docker-proxy'
docker ps --format 'table {{.Names}}\t{{.Ports}}'
docker ps --format '{{.Names}}\t{{.Ports}}' | grep -E '(^|[[:space:]])0\.0\.0\.0:'
```

Atteso: nessun listener `docker-proxy`/`containerd`/processo applicativo
Docker su IPv4; nessuna pubblicazione `0.0.0.0:<porta>`. Un listener IPv4 di
management (es. `sshd`) è tollerato solo se previsto e va annotato, non
rimosso.

## 2. Esposizione IPv6 e binding

```bash
ss -6 -tulpn
docker ps --format '{{.Ports}}' | grep -E '\[::\]|:::'
```

Verificare che i servizi esposti ascoltino su `[::]` o su un indirizzo IPv6
specifico e che le porte corrispondano ai pair autorizzati in `.ai/NETWORK.md`
sezione 8 e in `.ai/CONTEXT.md`.

## 3. Hardening di tutti gli stack

Per ogni `stacks/*/compose.yml` verificare la presenza dei vincoli:

```bash
for f in stacks/*/compose.yml; do
  echo "== $f"
  grep -nE '^\s*(user|security_opt|cap_drop|read_only|tmpfs|healthcheck|restart|image|ipv6_address|ports|privileged|pid|network_mode|ipc):' "$f"
done
```

Checklist per stack:

- [ ] `user:` esplicito e non-root (mai `0`, mai `root`).
- [ ] `security_opt: ["no-new-privileges:true"]`.
- [ ] `cap_drop: ["ALL"]`; eventuali `cap_add` singoli e documentati.
- [ ] `read_only: true` con `tmpfs` limitati.
- [ ] `healthcheck` presente e basato su IPv6 (`[::1]`, mai `127.0.0.1`).
- [ ] `image:` pinnata (tag preciso o digest), mai `:latest`.
- [ ] `ipv6_address` statico e coerente con `.ai/CONTEXT.md`.
- [ ] Nessun `0.0.0.0`, nessun `ports:` implicito IPv4.
- [ ] Nessun mount di `/var/run/docker.sock`.
- [ ] Nessun `privileged: true`, `pid: host`, `network_mode: host`,
      `ipc: host`.

Controllo aggregato delle violazioni:

```bash
grep -nE 'docker\.sock|0\.0\.0\.0|:latest|privileged:\s*true|network_mode:\s*host|pid:\s*host|ipc:\s*host' stacks/*/compose.yml
```

Atteso: nessun output. Ogni corrispondenza è una violazione da riportare.

Validazione sintattica (non applica nulla):

```bash
for f in stacks/*/compose.yml; do
  docker compose -f "$f" config -q || echo "INVALID: $f"
done
```

## 4. Segreti tracciati in Git

```bash
git ls-files | grep -Ei '(^|/)\.env($|\.)|secret|private|\.pem$|\.key$|id_rsa'
git grep -nE '(BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|password\s*=\s*[^[:space:]]+|api[_-]?key\s*=\s*[^[:space:]]+)' -- ':!*.example' ':!.ai/*'
```

Atteso: nessun file reale di segreti e nessun valore credenziale nei file
tracciati. Gli unici file ammessi sono `.env.example` e i template con
segnaposto. Se viene trovato un segreto: **non riprodurne il valore**,
rimuoverlo dal working tree, riportare l'incidente in `.ai/REPORT.md` e
segnalare la rotazione all'operatore.

Verificare anche `.gitignore`:

```bash
git check-ignore -v .env .backups/ logs/ 2>/dev/null
```

## 5. Coerenza di `.ai/CONTEXT.md` e `.ai/NETWORK.md`

- Ogni container/stack registrato in `.ai/CONTEXT.md` deve corrispondere a
  uno stack reale in `stacks/` e a un container in esecuzione (o documentato
  come fermo).
- Ogni tupla `(container, ipv6_address, porte)` deve combaciare con il
  compose e con `docker inspect`.
- Le subnet e gli host ID devono rispettare lo schema di `.ai/NETWORK.md`
  (`edge-v6` da `::20`, `internal-v6` da `::10`, nessuna subnet IPv4).
- Le porte autorizzate in `.ai/CONTEXT.md` devono coincidere con i pair
  IPv6 di `.ai/NETWORK.md` sezione 8.

```bash
docker network inspect edge-v6 \
  --format 'EnableIPv6={{.EnableIPv6}} internal={{.Internal}} ipam={{json .IPAM.Config}}'
docker network inspect internal-v6 \
  --format 'EnableIPv6={{.EnableIPv6}} internal={{.Internal}} ipam={{json .IPAM.Config}}'
```

Attesi: `EnableIPv6=true`; `Internal=false` su `edge-v6`,
`Internal=true` su `internal-v6`; nessuna subnet IPv4.

## 6. Controlli host (read-only)

```bash
systemctl is-active docker
systemctl is-active ssh
journalctl -u ssh --since '24 hours ago' --no-pager | tail -n 50
df -h
df -i
free -m
apt-get -s upgrade | grep -i security
nft list ruleset
```

Annotare: patch di sicurezza pendenti, tentativi SSH falliti, uso disco e
inode, regole firewall mancanti (es. ICMPv6). Nessun comando correttivo.

## 7. Scrivere l'esito

Appendere in `.ai/REPORT.md` una sezione `## Security audit — <data UTC>`
con:

- data/ora e commit HEAD analizzato;
- esito per ciascun blocco (IPv4, IPv6, hardening, segreti, coerenza stato);
- elenco anomalie con file/riga o container;
- classificazione Tier dell'eventuale correzione proposta;
- per ogni anomalia Tier 3: comandi proposti sotto
  `## Pending Human Approval`, senza eseguirli.

Aggiornare `.ai/QUEUE.md` aprendo un task per ogni violazione che richiede
una modifica. Se l'audit non produce modifiche ai file tracciati oltre al
report:

```bash
git add .ai/REPORT.md .ai/QUEUE.md
git commit -m "chore(audit): security and IPv4 exposure audit"
```

## Divieti specifici

- Applicare fix durante l'audit (l'audit è read-only).
- Modificare `nftables`, `/etc/docker/daemon.json`, SSH, interfacce,
  kernel o permessi.
- Stampare valori di segreti nei report o nei log.
- Rimuovere listener IPv4 di management senza approvazione umana.
