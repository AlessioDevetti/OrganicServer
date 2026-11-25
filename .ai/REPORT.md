# REPORT.md — Log cronologico delle esecuzioni

> Registro append-only: una voce per sessione, in ordine cronologico, dalla più vecchia alla più recente.
> Ogni voce riporta azioni, esito, errori esatti e follow-up. Le richieste che richiedono intervento umano vanno in `## Pending Human Approval`.

| Campo | Valore |
| :--- | :--- |
| Formato data | `YYYY-MM-DD HH:MM` (fuso del server, variabile `TZ`) |
| Retry massimo | 2 tentativi per comando o servizio |
| Responsabile Tier 3 | operatore umano |

## Pending Human Approval

> Modifiche Tier 3 richieste dall'agente: l'agente si ferma e attende l'operatore.
> Per ogni richiesta indicare comandi proposti, motivazione e rischio.

_Nessuna richiesta pendente._

## Esecuzioni

### YYYY-MM-DD HH:MM — <tipo sessione>
- **Agente:** <modello / harness>
- **Scope:** <task ID oppure "audit read-only">
- **Azioni:** <elenco dei comandi e delle modifiche>
- **Esito:** `OK` | `FAILED` | `PARTIAL`
- **Errori:** <output esatto oppure "nessuno">
- **Follow-up:** <task proposto in QUEUE.md oppure "nessuno">
- **Commit:** <hash oppure "nessuno">

---
