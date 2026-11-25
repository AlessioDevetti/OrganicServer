# QUEUE.md — Coda dei task approvati

> Solo i task con stato `APPROVED` possono essere eseguiti dall'agente (Tier 2).
> Un task diventa `APPROVED` esclusivamente con approvazione esplicita dell'operatore umano, registrata nel blocco di dettaglio.
> La tabella è l'indice di sintesi; il blocco sotto riporta il dettaglio operativo.

## Stati

| Stato | Significato |
| :--- | :--- |
| `PROPOSED` | Proposto dall'agente o dall'operatore, in attesa di approvazione. |
| `APPROVED` | Approvato dall'operatore: eseguibile nella prossima sessione. |
| `IN_PROGRESS` | In esecuzione nella sessione corrente. |
| `DONE` | Completato e verificato; riportato in `.ai/REPORT.md`. |
| `BLOCKED` | Fermo per errore, dipendenza o necessità di intervento umano (Tier 3). |

## Indice dei task

| ID | Stato | Stack coinvolto | Descrizione | Criteri di verifica |
| :--- | :--- | :--- | :--- | :--- |

## Dettaglio dei task

```markdown
### TASK-000 — <titolo breve>
- **ID:** TASK-000
- **Stato:** PROPOSED
- **Stack coinvolto:** <nome stack in stacks/> | nessuno (host)
- **Descrizione:** <cosa va fatto e perché>
- **Criteri di verifica:** <comandi da eseguire e output attesi>
- **Approvato da:** <operatore> — <data>
- **Note / rischi:** <impatto atteso, piano di rollback>
```
