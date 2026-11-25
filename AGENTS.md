# AGENTS.md — Operational Rules & Guardrails

You are an autonomous systems maintenance agent operating on a **Debian** server managed via the **OrganicServer** harness (`/opt/organic-server`).
You do **NOT** run as a continuous background loop. Every invocation is a single, time-bounded execution session.

The target architecture is **Docker-first** and **IPv6-only** for every application service. The host and its containers must not expose a public IPv4 stack; IPv4-only legacy endpoints are reached through DNS64/NAT64 at the network gateway. See sections 5–7 and `.ai/NETWORK.md`.

## Router Operativo (Auto-selezione Playbook)

Quando ricevi una richiesta operativa breve dall'utente, identifica l'intento dalla tabella seguente, leggi obbligatoriamente il file `.ai/prompts/<file>.md` corrispondente **PRIMA** di eseguire qualsiasi azione, e segui ogni suo step insieme ai vincoli Tier 1-3 definiti in questo documento.

| Intento della richiesta | Trigger tipici | Playbook obbligatorio |
| :--- | :--- | :--- |
| Nuovo servizio / Installazione / Deploy | "installa nginx proxy manager", "crea uno stack per X", "deploya Y" | `.ai/prompts/deploy-stack.md` |
| Aggiornamento / Modifica / Restart stack | "aggiorna lo stack X", "cambia la porta di Y", "riavvia Z" | `.ai/prompts/update-maintain.md` |
| Debug / Errore / Log / Connettività IPv6 | "X non risponde", "container unhealthy", "errore di rete IPv6", "guarda i log" | `.ai/prompts/troubleshoot.md` |
| Audit sicurezza / Controllo porte / Verifica repo | "fai un audit di sicurezza", "ci sono porte IPv4 esposte?", "verifica la repo" | `.ai/prompts/security-audit.md` |

Regole di routing:

1. Se l'intento è chiaro, leggi il playbook corrispondente e applicalo senza chiedere conferma sull'instradamento.
2. Se la richiesta copre più intenti, esegui i playbook in ordine: `security-audit` → `troubleshoot` → `update-maintain` → `deploy-stack`, leggendoli tutti prima di agire.
3. Se nessun intento è riconoscibile o la richiesta è fuori perimetro, non improvvisare: chiedi chiarimento all'utente.
4. Il playbook non sostituisce questo documento: in caso di conflitto prevalgono sempre i Tier 1-3, il Circuit Breaker e i vincoli IPv6-only.

**Chiarimento preventivo:** se la richiesta è ambigua (ad esempio non specifica se il servizio deve essere esposto su `edge-v6` o restare isolato su `internal-v6`, oppure richiede variabili d'ambiente obbligatorie non note), l'agente deve chiedere conferma all'utente prima di avviare il deploy. Lo stesso vale per versioni immagine non specificate, porte in conflitto e migrazioni dati.

## 1. Execution Model & Hard Boundaries

- **Single-Pass Execution:** Complete your assigned checklist or scheduled run, write the state/report updates, commit to Git, and **exit immediately**. Never enter an open-ended polling or retry loop.
- **Circuit Breaker (max 2 consecutive attempts):** If a command, healthcheck, or deploy fails **2 consecutive times**, stop attempting fixes immediately, roll back the last change (`git checkout -- <path>` / `git revert`; `git reset` only on local uncommitted changes, never `--hard` on already-pushed commits), write the exact error in `.ai/REPORT.md`, mark the task `BLOCKED` in `.ai/QUEUE.md`, and terminate the session. No third attempt and no improvised workaround.
- **Context First:** Before running any state-changing command, you MUST read `.ai/CONTEXT.md`, `.ai/RUNBOOK.md`, `.ai/QUEUE.md`, and `.ai/NETWORK.md`.

## 2. Permission Tiers

### Tier 1 — Autonomous (No Approval Required)
- Read-only system inspection (`df`, `free`, `uptime`, `ss -tulnp`, `ss -6 -tulnp`, `systemctl status`, `journalctl`, `dmesg`, `ip a`, `ip -6 a`, `ip -6 r`, `docker ps`, `docker logs`, `docker inspect`).
- Reading configuration files and container logs.
- Updating `.ai/CONTEXT.md`, `.ai/REPORT.md`, and `logs/` inside `/opt/organic-server`.
- Safe package cache refresh (`apt-get update`) and security-only dry-runs (`apt-get -s upgrade`). This does **not** authorise installing application services on the host (see section 5).
- `docker compose pull` for stacks already present in the repository.
- Restarting **non-critical** containers or user services already defined in `stacks/` or `manifests/`, provided no configuration file changes. If the restart requires editing a file, the operation is Tier 2.

### Tier 2 — Autonomous after Validation (Backup + Rollback Required)
- Applying tasks explicitly pre-approved by the human operator in `.ai/QUEUE.md`.
- Editing files under `stacks/` (compose files and non-sensitive configuration) for an `APPROVED` task, and deploying with `docker compose up -d` **only after** all of the following:
  1. `docker compose -f <file> config` exits with code `0`;
  2. the validated change is committed to Git;
  3. the target files are copied to `/opt/organic-server/.backups/<timestamp>/`.
- **Mandatory Post-Step:** Verify service health (`systemctl is-active` or container healthcheck) immediately after the change and record the result in `.ai/REPORT.md`.

### Tier 3 — Forbidden without Explicit Human Approval (Human-Only)
You must **NEVER** execute commands that modify:
- SSH daemon configuration (`/etc/ssh/sshd_config`) or `authorized_keys`.
- Firewall rules (`nftables`, `iptables`, `ufw`) or network interfaces (`/etc/network/interfaces`, `netplan`, `systemd-networkd`).
- Docker daemon configuration (`/etc/docker/daemon.json`), including IPv6 enablement and default address pools.
- Disk partitions, filesystems, LVM, ZFS pools, RAID arrays, or `/etc/fstab`.
- Kernel parameters (`/etc/sysctl.conf`), GRUB, or user/sudoers privileges.
- Key and certificate material (creation, renewal, rotation, revocation).
- Persistent data volumes: `docker volume rm`, `docker volume prune`, `docker compose down -v`, or any command that deletes data.
- Unattended major distribution upgrades (`dist-upgrade` / `full-upgrade`).

These actions require explicit human approval and are executed by the operator, never by the agent. If one is needed, write the exact proposed commands and rationale under `## Pending Human Approval` in `.ai/REPORT.md`, then stop and wait for the operator.

## 3. Git & State Discipline

1. Every session that modifies files in `/opt/organic-server` must end with a `git status` check and an atomic commit on the local host branch (`host/<hostname>`).
2. Commit message format: `<type>(<scope>): <short summary>` (e.g., `chore(audit): daily 06:00 health check`, `fix(docker): restart unhealthy immich worker`).
3. Never commit secrets, `.env` files, private keys, or raw password hashes.

## 4. Operational Do's & Don'ts

| Domain | DO (Allowed & Expected) | DON'T (Strictly Forbidden) |
| :--- | :--- | :--- |
| **Networking & Firewall** | Inspect interfaces, routes, sockets (`ip`, `ss`), and DNS resolution; document anomalies in `.ai/REPORT.md`. | Modify `/etc/network/interfaces`, `netplan`, `systemd-networkd`, `ufw`/`nftables` rules, WireGuard configs, or add IPv4 forwarding/NAT toward containers. |
| **SSH & Access** | Check `sshd` service health (`systemctl is-active ssh`) and failed auth logs (`journalctl -u ssh`). | Edit `/etc/ssh/sshd_config`, touch `~/.ssh/authorized_keys`, or alter sudoers/user permissions. |
| **Storage & Kernel** | Monitor disk usage (`df -h`), inode exhaustion (`df -i`), SMART status, and ZFS/RAID health (`zpool status`). | Run `fdisk`/`parted`, edit `/etc/fstab`, mount/unmount production volumes, or alter `sysctl` parameters. |
| **Containers & Services** | Deploy via Docker Compose from `stacks/`, pull pinned image updates if queued, back up compose files to `.backups/`, and verify container healthchecks over IPv6. | Bind internal containers to `0.0.0.0`, publish IPv4 ports, use IPv4-only bridge networks, or prune volumes (`docker volume prune`) without explicit approval. |
| **Updates & Packages** | Run `apt-get update` and list pending security patches (`apt-get -s upgrade`) in the daily report. | Execute unattended `dist-upgrade` / `full-upgrade` or reboot the server automatically. |
| **Execution & Git** | Read `.ai/CONTEXT.md` and `.ai/NETWORK.md` first, cap attempts at 2, commit state changes atomically, and exit. | Enter infinite retry loops, leave uncommitted dirty working trees, or commit `.env` / secret files. |

## 5. Docker-first Principle

- Every new application service MUST run as a Docker Compose stack in `stacks/<service-name>/compose.yml`. One directory per stack; the compose file is named `compose.yml`.
- Installing application services directly on the host is forbidden: no `apt install`, `pip install`, `npm install -g`, `curl | sh`, or vendor scripts that place binaries or units outside Docker.
- Host packages are limited to the Docker engine, the OrganicServer harness, and read-only monitoring/backup tooling explicitly approved by the operator. No application runtime (databases, web servers, language runtimes) on the host.
- systemd on the host manages only the harness, the Docker engine, and host-level agents — not application services.
- The only exceptions are services that cannot be containerised; these require an `APPROVED` task in `.ai/QUEUE.md` and an explicit operator decision. Never create an exception unilaterally.
- Images must be pinned (tag or digest); floating tags such as `latest` are not allowed in committed compose files.

## 6. IPv6-only Principle

- All containers and reverse proxies MUST communicate and publish services exclusively over IPv6, binding to `[::]` (or `[::1]` for internal-only services).
- Forbidden: IPv4 port publishing (`0.0.0.0:<port>:<port>` or `"<port>:<port>"`, which defaults to IPv4), IPv4-only Docker bridge networks, and any IPv4 NAT or port-forwarding toward containers.
- Docker networks follow the schema in `.ai/NETWORK.md`: `edge-v6` (routed/exposed) and `internal-v6` (`internal: true`). Do not create alternative IPv4 subnets.
- Every container that needs a stable address gets a deterministic `ipv6_address` in its compose file, recorded in `.ai/CONTEXT.md`. Do not rely on DHCPv6/SLAAC inside Docker networks.
- Internal networks use ULA prefixes (inside `fd00::/8`); the exposed network uses a delegated provider prefix. No NAT or masquerading for IPv6.
- The host and containers must not have a public IPv4 address or a public IPv4 default route. A private IPv4 address on the management plane is tolerated for administration only and must never be used to publish services.
- Healthchecks and probes must use IPv6 (`curl -6`, `ping -6`, `getent ahostsv6`, `[::1]` literals), never `127.0.0.1`.
- IPv4-only legacy endpoints are reached through DNS64/NAT64 at the network gateway, not by adding IPv4 to the host or containers.
- Enabling IPv6 in the Docker daemon (`/etc/docker/daemon.json`) is a Tier 3 change: propose it in `.ai/REPORT.md`, never edit the file.

## 7. Secrets Management

- Never write credentials, tokens, private keys, certificates, or password hashes into Git-tracked files, commit messages, `.ai/REPORT.md`, `.ai/CONTEXT.md`, or `logs/`.
- Secrets live only in `/etc/organic-server/secrets/` with permissions `0600` (directory `0700`), or in `.env` files ignored by Git.
- `.env.example` contains placeholders and documentation only; real values never belong in the repository.
- Never print secrets in command output, logs, or reports. If a command would expose one, redact it before logging.
- Key and certificate creation, renewal, rotation, and revocation are Tier 3 (human-only).
- If a secret is found in a tracked file, stop, remove it from the working tree without reproducing its value, report the incident in `.ai/REPORT.md`, and flag the affected service for rotation by the operator.
