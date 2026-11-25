#!/usr/bin/env bash
set -euo pipefail
# ======================================================================
# OrganicServer — pre-flight check (read-only, Tier 1)
#
# Architettura dual-stack (IPv4 + IPv6 paritari): la pubblicazione di
# porte è ammessa su entrambe le famiglie. Questo script NON flagga più
# 0.0.0.0 / sintassi breve `ports:`; verifica invece che restino validi
# i vincoli di hardening e che la configurazione Compose sia coerente.
#
# Exit code: 0 = OK, 1 = almeno un'anomalia. Non modifica mai stato.
# ======================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
FAIL=0

err()  { printf 'PREFLIGHT-FAIL: %s\n' "$*" >&2; FAIL=1; }
ok()   { printf 'preflight-ok:  %s\n' "$*"; }
warn() { printf 'preflight-warn: %s\n' "$*" >&2; }
sec()  { printf '\n== %s ==\n' "$*"; }

sec "Repository"
if [ -n "$(git status --porcelain)" ]; then
  err "working tree non pulito: $(git status --porcelain | head -n 5 | tr '\n' ' ')"
else
  ok "working tree pulito (branch: $(git branch --show-current))"
fi

sec "Docker engine"
if ! command -v docker >/dev/null 2>&1; then
  err "docker CLI assente (ambiente di dry-run?)"
else
  ok "docker CLI: $(docker version --format '{{.Client.Version}}' 2>/dev/null || echo unknown)"
  if docker info >/dev/null 2>&1; then ok "docker daemon raggiungibile"; else err "docker daemon non raggiungibile"; fi
  if docker compose version >/dev/null 2>&1; then ok "docker compose: $(docker compose version --short)"; else err "docker compose v2 assente"; fi
fi

sec "Sintassi Compose"
shopt -s nullglob
compose_files=( stacks/*/compose.yml )
if [ "${#compose_files[@]}" -eq 0 ]; then
  err "nessun compose.yml sotto stacks/"
else
  for f in "${compose_files[@]}"; do
    if docker compose -f "$f" config -q >/dev/null 2>&1; then
      ok "config valido: $f"
    else
      err "config NON valido: $f"
    fi
  done
fi

sec "Hardening (vincoli non rimovibili)"
for f in "${compose_files[@]}"; do
  # Primitive runtime vietate
  if grep -nE 'docker\.sock|privileged:\s*true|network_mode:\s*host|pid:\s*host|ipc:\s*host' "$f" >/dev/null 2>&1; then
    err "primitive runtime vietate in $f:"
    grep -nE 'docker\.sock|privileged:\s*true|network_mode:\s*host|pid:\s*host|ipc:\s*host' "$f" >&2
  fi
  # Tag immagine flottanti
  if grep -nE 'image:\s*[^#[:space:]]+(:latest|:stable|:main|:edge)([[:space:]]|$)' "$f" >/dev/null 2>&1; then
    err "tag immagine flottante in $f:"
    grep -nE 'image:\s*[^#[:space:]]+(:latest|:stable|:main|:edge)([[:space:]]|$)' "$f" >&2
  fi
  # Utente root implicito o esplicito
  if grep -nE 'user:\s*(0|root)([:[:space:]]|$)' "$f" >/dev/null 2>&1; then
    err "utente root in $f:"
    grep -nE 'user:\s*(0|root)([:[:space:]]|$)' "$f" >&2
  fi
  # Vincoli di hardening obbligatori
  for key in security_opt cap_drop read_only; do
    if ! grep -qE "^[[:space:]]*${key}:" "$f"; then
      err "manca '${key}:' in $f"
    fi
  done
done

sec "Risorse host (best effort)"
for c in df free uptime; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c disponibile"; else warn "$c assente"; fi
done

sec "Socket in ascolto (informativo, dual-stack)"
if command -v ss >/dev/null 2>&1; then
  ss -tulpn >/dev/null 2>&1 && ok "ss disponibile (mostra IPv4 e IPv6)" || warn "ss non eseguibile"
else
  warn "ss assente"
fi

printf '\n'
if [ "$FAIL" -ne 0 ]; then
  printf 'PREFLIGHT RESULT: FAIL (%d anomalie)\n' "$FAIL" >&2
  exit 1
fi
printf 'PREFLIGHT RESULT: OK\n'
exit 0
