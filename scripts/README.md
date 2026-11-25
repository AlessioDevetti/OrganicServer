# scripts/

Script idempotenti usati dall'agente per audit, raccolta stato e backup.

Convenzioni:

- Sola lettura per default; nessuno script deve modificare rete, firewall, SSH o partizioni.
- Output leggibile e exit code `0` / `1`.
- Lo stato raccolto alimenta `.ai/CONTEXT.md`; le esecuzioni vanno registrate in `.ai/REPORT.md`.
