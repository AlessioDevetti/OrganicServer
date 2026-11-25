# Playbook — Troubleshooting

> **Trigger:** segnalazioni di malfunzionamenti, errori di rete IPv6 o
> container `unhealthy` (es. *"Immich non risponde"*, *"il container è
> unhealthy"*, *"non si raggiunge il servizio in IPv6"*).
> **Tier di riferimento:** solo diagnostica read-only Tier 1; fix solo se
> rientrano in Tier 1/2 e sono già approvati.

## 0. Contesto

1. Leggere `AGENTS.md`, `.ai/CONTEXT.md`, `.ai/NETWORK.md`,
   `.ai/RUNBOOK.md` (sezioni 3 e 5) e lo stato del task in `.ai/QUEUE.md`.
2. Identificare stack e container coinvolti; non modificare nulla prima di
   aver completato la raccolta diagnostica.
3. Applicare il **Circuit Breaker**: massimo 2 tentativi consecutivi, poi
   stop, report e task `BLOCKED`.

## 1. Diagnostica read-only (Tier 1)

Stato dei container:

```bash
docker ps -a
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker compose -f stacks/<nome-stack>/compose.yml ps
docker inspect --format \
  '{{.Name}} state={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' \
  <container>
```

Log (senza stampare segreti):

```bash
docker logs --tail 200 <container>
docker logs --since 30m <container>
```

Configurazione e rete del container:

```bash
docker inspect <container>
docker inspect --format '{{json .NetworkSettings.Networks}}' <container>
docker inspect --format '{{json .NetworkSettings.Ports}}' <container>
docker inspect --format '{{json .HostConfig.CapDrop}} {{json .HostConfig.SecurityOpt}}' <container>
```

Rete e socket dell'host:

```bash
ip -6 a
ip -6 r
ip -4 a
ip -4 r
ss -6 -tulpn
ss -4 -tulpn
```

Reti Docker:

```bash
docker network ls
docker network inspect edge
docker network inspect internal
docker network inspect edge --format '{{json .EnableIPv6}} {{json .Options}}'
```

Risoluzione e raggiungibilità:

```bash
getent ahostsv6 <fqdn>
docker exec <container> getent hosts <hostname>
docker exec <container> ping -6 -c 3 <target>
```

Firewall in sola lettura: `nft list ruleset` (non modificare, ricaricare o
svuotare).

## 2. Confrontare con lo stato dichiarato

Confrontare i dati raccolti con `.ai/NETWORK.md` e `.ai/CONTEXT.md`:

| Controllo | Atteso |
| :--- | :--- |
| Rete `edge` | `EnableIPv6=true`, `Internal=false`, subnet IPv4 (RFC 1918) + IPv6 |
| Rete `internal` | `EnableIPv6=true`, `Internal=true`, subnet IPv4 (RFC 1918) + IPv6 |
| Indirizzo container | `IPAddress` (IPv4) e `GlobalIPv6Address` uguali a quelli in `.ai/CONTEXT.md` |
| Porte pubblicate | su entrambe le famiglie, coerenti con `.ai/CONTEXT.md` |
| `Healthcheck` | `healthy`, oppure `starting` entro lo start period |
| Routing | default route presente (solo su `edge`); ICMPv6/ICMPv4 non filtrati |
| DNS | risoluzione A e AAAA funzionante |

Una divergenza è un'anomalia: registrarla, non "correggerla" modificando
rete o firewall.

## 3. Classificare la causa

Cause tipiche e verifica:

1. **Container unhealthy** — probe errato, dipendenza non pronta, permessi
   sui volumi, crash applicativo. Leggere i log e il comando di healthcheck.
2. **Indirizzi IPv4/IPv6 errati o duplicati** — confrontare compose,
   `.ai/CONTEXT.md` e `docker network inspect`.
3. **Binding o porta occupata** — `ss -4/-6 -tulpn`; collisioni con
   `systemd-resolved`, reverse proxy o altri stack.
4. **Risoluzione DNS (A/AAAA) non funzionante** — `getent hosts`,
   `getent ahostsv6`, `resolvectl status`; non modificare rete/firewall come
   workaround.
5. **Firewall/ICMP** — regole `nft` mancanti o ICMPv6/ICMPv4 filtrato; la
   modifica è Tier 3, solo proposta.
6. **Volume o permessi** — UID/GID non coerente con `user:`; nessuna
   cancellazione di volumi.

## 4. Fix ammessi

Solo se rientrano in Tier 1/2 e il task è `APPROVED`:

- riavvio di un container non critico senza modifica di file
  (`docker compose -f <file> restart <servizio>`);
- `docker compose -f <file> up -d --remove-orphans` dopo una modifica di
  configurazione validata e committata, con backup in
  `.backups/<timestamp>/`;
- rollback della sola configurazione secondo `.ai/RUNBOOK.md` sezione 4.

Prerequisiti per un fix Tier 2: `docker compose config` exit `0`, commit
della configurazione, backup dei file, verifica post-modifica.

**Non ammessi senza approvazione umana:** modifiche a `nftables`,
`/etc/docker/daemon.json`, interfacce, `systemd-networkd`, SSH, kernel,
volumi persistenti. In questi casi scrivere i comandi proposti sotto
`## Pending Human Approval` in `.ai/REPORT.md` e fermarsi.

## 5. Documentare e chiudere

1. Scrivere in `.ai/REPORT.md`: sintomo, comandi eseguiti, output rilevante,
   causa radice, fix applicato (o proposta Tier 3), esito.
2. Aggiornare `.ai/CONTEXT.md` se lo stato osservato è cambiato
   (`./scripts/update-context.sh` o manualmente se lo script non è
   disponibile).
3. Aggiornare `.ai/QUEUE.md`: `DONE` se risolto, `BLOCKED` se servono
   interventi Tier 3 o il Circuit Breaker è scattato.
4. Se non ci sono modifiche a file tracciati, non creare commit vuoti; se ci
   sono aggiornamenti di stato, commit atomico:

```bash
git add .ai/CONTEXT.md .ai/REPORT.md .ai/QUEUE.md
git commit -m "docs(ai): document <sintomo> troubleshooting session"
```

## Divieti specifici

- Diagnostica che stampa segreti o contenuto di `.env`.
- Modifiche a rete, firewall, daemon Docker o SSH (Tier 3).
- `docker compose down -v`, `docker volume rm/prune`, cancellazione dati.
- Loop di retry oltre i 2 tentativi.
