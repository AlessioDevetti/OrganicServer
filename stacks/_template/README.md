# `stacks/_template` — blueprint hardened IPv6-only

Questa directory è il modello obbligatorio per ogni nuovo stack in `stacks/`.
Non va deployata così com'è: serve a copiare la struttura e l'hardening di
base, riducendo il rischio di dimenticare un vincolo di sicurezza.

Riferimenti: `AGENTS.md` (sezioni 5–7), `.ai/NETWORK.md`, `.ai/RUNBOOK.md`.

## 1. Creare un nuovo stack

```bash
cp -r stacks/_template "stacks/<servizio>"
```

Poi rinominare la directory e modificare `stacks/<servizio>/compose.yml`.

## 2. Campi da modificare (e come)

| Campo | Cosa fare |
| :--- | :--- |
| `name:` | Sostituire `organic-template` con il nome dello stack (minuscolo, trattini). Deve essere univoco sulla macchina. |
| `services.example-app:` | Rinominare il servizio con il nome reale; un servizio per container, nome stabile. |
| `image:` | Usare un tag di versione preciso o, meglio, un digest `image@sha256:...`. Mai `:latest` né tag mobili. |
| `command:` | Sostituire il comando placeholder con quello del servizio reale. |
| `user:` | Mantenere un UID/GID non-root esplicito. Se i volumi sono posseduti da un altro utente, usare quel `PUID:PGID` e documentarlo. |
| `env_file.path` | Puntare a `/etc/organic-server/secrets/<servizio>.env`. Il file reale resta fuori dal repository (permessi `0600`, directory `0700`). |
| `networks` + `ipv6_address` | Scegliere **una** rete pertinente e un host ID deterministico secondo `.ai/NETWORK.md`: backend/database su `internal-v6` da `::10`; reverse proxy/edge su `edge-v6` da `::20`. Registrare la tupla in `.ai/CONTEXT.md`. |
| `expose:` | Dichiarare solo le porte interne realmente usate dal servizio. |
| `healthcheck:` | Sostituire l'endpoint placeholder con un probe reale, eseguito su IPv6 (`[::1]` o l'indirizzo del servizio). Deve fallire quando il servizio non è pronto. |
| `restart:` | Lasciare `unless-stopped` salvo motivazione esplicita documentata. |
| `tmpfs` | Aggiungere altri path scrivibili solo se necessari, sempre con `noexec,nosuid` e una dimensione limitata. |

### Rete e pubblicazione porte

- I servizi backend restano solo su `internal-v6` e non pubblicano porte
  sull'host: si raggiungono tramite l'indirizzo IPv6 statico.
- Solo il reverse proxy può stare su `edge-v6` e pubblicare porte, con binding
  IPv6 esplicito, ad esempio `"[::]:443:443/tcp"`.
- Non aggiungere mai un binding IPv4, implicito o esplicito. Un `ports:` del
  tipo `"8080:8080"` crea un listener IPv4 e non è ammesso.
- Le reti `edge-v6` e `internal-v6` sono esterne e create da
  `stacks/_network/compose.yml`: non ridefinirle nello stack.

### Segreti

- Nessun valore reale in `compose.yml`, `.env.example`, README o Git.
- Il file `/etc/organic-server/secrets/<servizio>.env` va creato
  dall'operatore con permessi `0600`; la directory con `0700`.
- `required: false` serve solo a permettere la validazione sintattica in
  ambienti senza segreti montati. In produzione il file deve esistere: se
  manca, il servizio parte senza configurazione e va considerato un errore.

## 3. Vincoli da non rimuovere mai

Questi campi fanno parte del baseline di sicurezza. La loro rimozione rende
lo stack non conforme e richiede un task `APPROVED` in `.ai/QUEUE.md`:

- `user:` non-root esplicito (mai root, mai UID `0`).
- `security_opt: [no-new-privileges:true]`.
- `cap_drop: [ALL]`; eventuali `cap_add` devono essere singoli, motivati e
  documentati nel task.
- `read_only: true` con `tmpfs` limitati per `/tmp` e `/run`.
- Nessun mount di `/var/run/docker.sock` o di altri socket del runtime.
- Nessun `privileged: true`, nessun `pid: host`, `network_mode: host` o
  `ipc: host`.
- Nessun binding IPv4 e nessuna rete Docker IPv4: solo `edge-v6` /
  `internal-v6` con `ipv6_address` statico.
- Immagine pinnata e `healthcheck` esplicito.
- `restart: unless-stopped`.
- Segreti solo tramite `env_file` esterno al repository o meccanismo
  equivalente approvato.

## 4. Validazione e deploy

Dalla root del repository:

```bash
docker compose -f stacks/<servizio>/compose.yml config
grep -nE 'docker\.sock|0\.0\.0\.0' stacks/<servizio>/compose.yml   # nessun output
```

Il primo comando deve uscire con codice `0`; il secondo non deve trovare
nulla. Seguire poi `.ai/RUNBOOK.md` (pre-flight, deploy, verifica IPv6,
rollback). Ogni deploy richiede un task `APPROVED` in `.ai/QUEUE.md` e il
backup dei file in `.backups/<timestamp>/`.
