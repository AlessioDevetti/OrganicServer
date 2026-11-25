# stacks/

Una sottodirectory per ogni stack Docker Compose gestito da OrganicServer.

Convenzioni:

- Nome directory = nome dello stack, in minuscolo con trattini.
- File principale `compose.yaml`; variabili non sensibili documentate in `.env.example`, valori reali in `.env` (ignorato da Git).
- Binding interni su `127.0.0.1` / `[::1]` o su rete Docker interna; esposizione pubblica solo tramite reverse proxy.
- Ogni nuovo stack richiede un task `APPROVED` in `.ai/QUEUE.md`.
