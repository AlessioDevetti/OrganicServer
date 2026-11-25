# OrganicServer

**OrganicServer** è un harness operativo basato su Git per la gestione **dichiarativa e agentica** di un server **Debian** orientato a container Docker e a connettività nativa IPv6.

Il repository viene clonato su `/opt/organic-server` e fornisce a un agente AI (OpenCode, Claude Code o agenti LLM locali) le regole, il contesto architetturale e i guardrail necessari per inizializzare, configurare e mantenere il sistema nel tempo. Ogni modifica è ispezionata, applicata in modo dichiarativo quando possibile e tracciata con commit atomici; le operazioni critiche restano in carico all'operatore umano.

Il server cresce *organicamente*: lo stato desiderato vive nel repository, lo stato reale viene misurato e registrato in `.ai/`.

## Principi

- **Context-first:** l'agente legge `AGENTS.md`, `.ai/CONTEXT.md`, `.ai/RUNBOOK.md` e `.ai/QUEUE.md` prima di qualsiasi comando che modifica lo stato.
- **Human-in-the-loop:** firewall, SSH, partizioni, interfacce di rete e privilegi sono Tier 3 e richiedono sempre l'intervento umano.
- **Reversibilità:** backup in `.backups/<timestamp>/` prima delle modifiche e rollback documentato via Git.
- **Commit atomico:** una sessione produce un cambiamento coerente, l'aggiornamento dello stato e un unico commit descrittivo.

## Alberatura della repository

```text
OrganicServer/
├── AGENTS.md            # Regole operative, tier di permesso e guardrail per l'agente
├── README.md            # Panoramica del progetto e flusso operativo
├── .gitignore           # Esclusione di segreti, chiavi, volumi e file temporanei
├── .env.example         # Segnaposto documentati per le variabili d'ambiente
├── .ai/
│   ├── CONTEXT.md       # Snapshot fattuale dello stato (host, reti IPv6, container)
│   ├── RUNBOOK.md       # Procedure operative standard
│   ├── QUEUE.md         # Coda dei task approvati dall'operatore
│   ├── REPORT.md        # Log cronologico delle esecuzioni
│   ├── NETWORK.md       # Linee guida di rete e connettività
│   └── prompts/         # Playbook operativi selezionati dall'intento (deploy, update, troubleshoot, audit)
├── stacks/              # Docker Compose stack dichiarativi (una directory per stack)
├── manifests/           # Asset dichiarativi già presenti (compose, unit systemd)
├── scripts/             # Script idempotenti di audit, raccolta stato e backup
└── logs/                # Note post-mortem e milestone di manutenzione
```

`stacks/` è la destinazione prevista per i nuovi stack Compose; gli asset già presenti restano in `manifests/` finché non vengono migrati con un task dedicato in `.ai/QUEUE.md`.

La connettività dei servizi esposti è nativa IPv6. Il piano di management va comunque verificato su entrambe le famiglie di protocollo, secondo la disciplina descritta in `.ai/NETWORK.md`.

## Flusso operativo standard

1. **Coda dei task** — ogni intervento nasce come voce in `.ai/QUEUE.md` con ID, stack coinvolto, descrizione e criteri di verifica. Solo i task in stato `APPROVED` possono essere eseguiti.
2. **Validazione** — pre-flight check secondo `.ai/RUNBOOK.md` (sezione 1), validazione della configurazione con `docker compose config` e verifica delle porte con `ss -tulnp` prima di toccare il servizio.
3. **Deploy** — backup dei file interessati in `.backups/<timestamp>/`, applicazione dichiarativa dello stack e verifica degli healthcheck (`.ai/RUNBOOK.md`, sezione 2).
4. **Aggiornamento dello stato** — riscrittura di `.ai/CONTEXT.md` con i dati raccolti e append della sessione in `.ai/REPORT.md` (esito, errori, follow-up).
5. **Commit atomico** — `git status` pulito e un singolo commit con formato `<type>(<scope>): <short summary>` sul branch `host/<hostname>`.

In caso di fallimento: massimo 2 tentativi, poi stop, log dell'errore esatto in `.ai/REPORT.md` e segnalazione per revisione umana.

## Utilizzo rapido con Agente AI

`AGENTS.md` contiene un *Router Operativo*: l'agente riconosce l'intento della richiesta, legge il playbook corrispondente in `.ai/prompts/` e lo esegue nel rispetto dei Tier 1-3. Non serve conoscere i comandi: basta descrivere l'obiettivo.

Esempi di richieste brevi:

- **Installare un nuovo servizio** — *"Installa Nginx Proxy Manager"* → `.ai/prompts/deploy-stack.md` (template, immagine pinnata, IPv6 statico, hardening, preflight, verifica).
- **Aggiornare o modificare uno stack** — *"Aggiorna lo stack vaultwarden"* oppure *"Cambia la porta interna di immich"* → `.ai/prompts/update-maintain.md` (pull, `up -d --remove-orphans`, healthcheck, rollback).
- **Diagnosticare un problema** — *"Il container immich è unhealthy"* o *"Non si raggiunge il servizio in IPv6"* → `.ai/prompts/troubleshoot.md` (diagnostica read-only, causa radice, report).
- **Verificare la sicurezza** — *"Fai un audit di sicurezza"* o *"Ci sono porte IPv4 esposte?"* → `.ai/prompts/security-audit.md` (hardening, segreti, coerenza di stato).

Se la richiesta è ambigua (rete `edge-v6` vs `internal-v6`, variabili d'ambiente o versione immagine mancanti), l'agente chiede conferma prima di procedere.

## Riferimenti

- `AGENTS.md` — regole operative, router dei playbook e tier di permesso.
- `.ai/prompts/` — playbook operativi per deploy, aggiornamento, troubleshooting e audit.
- `.ai/NETWORK.md` — disciplina di rete, binding delle porte e verifiche di connettività.
- `.ai/RUNBOOK.md` — procedure operative passo-passo.
