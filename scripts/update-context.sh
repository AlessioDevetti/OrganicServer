#!/usr/bin/env bash
set -euo pipefail
# ======================================================================
# OrganicServer — raccolta stato read-only (Tier 1)
#
# Rigenera .ai/CONTEXT.md da dati reali raccolti in sola lettura.
# Architettura dual-stack (IPv4 + IPv6).
#
# Vincolo di sicurezza: NON legge né scrive MAI le variabili d'ambiente
# dei container (Config.Env), che possono contenere segreti.
# ======================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
OUT=".ai/CONTEXT.md"
TS="$(date -u +'%Y-%m-%d %H:%M')"

host="$(hostname 2>/dev/null || echo 'unavailable')"
os="$( (grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null || echo 'PRETTY_NAME=unavailable') | cut -d= -f2- | tr -d '"' )"
kernel="$(uname -r 2>/dev/null || echo 'unavailable')"

docker_ver="unavailable"
if command -v docker >/dev/null 2>&1; then
  docker_ver="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'daemon unreachable')"
fi

# Reti: nome, subnet IPv4+IPv6 con gateway, internal. Mai Config.Env.
net_rows=""
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  for n in edge internal; do
    row="$(docker network inspect "$n" \
      --format '{{.Name}} | {{range .IPAM.Config}}{{.Subnet}} (gw {{.Gateway}}) {{end}} | internal={{.Internal}}' \
      2>/dev/null || echo "$n | unavailable | unavailable")"
    net_rows="${net_rows}| ${row} |\n"
  done
fi

# Container: nome, immagine, IPv4, IPv6, porte. Mai Config.Env.
ctr_rows=""
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  mapfile -t cids < <(docker ps -q 2>/dev/null || true)
  for cid in "${cids[@]:-}"; do
    [ -z "${cid:-}" ] && continue
    name="$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')"
    img="$(docker inspect --format '{{.Config.Image}}' "$cid" 2>/dev/null)"
    ip4="$(docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{$v.IPAddress}} {{end}}' "$cid" 2>/dev/null)"
    ip6="$(docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{$v.GlobalIPv6Address}} {{end}}' "$cid" 2>/dev/null)"
    ports="$(docker inspect --format '{{json .NetworkSettings.Ports}}' "$cid" 2>/dev/null)"
    ctr_rows="${ctr_rows}| ${name} | ${img} | ${ip4} | ${ip6} | ${ports} |\n"
  done
fi

{
  cat <<EOF
# CONTEXT.md — Stato corrente del sistema

> Snapshot **fattuale** generato da \`scripts/update-context.sh\` il ${TS} UTC.
> Nessuna variabile d'ambiente di container (\`Config.Env\`) viene letta o scritta.

| Campo | Valore |
| :--- | :--- |
| Ultimo aggiornamento (UTC) | ${TS} |
| Hostname | ${host} |
| OS | ${os} |
| Kernel | ${kernel} |
| Docker Engine | ${docker_ver} |

## Reti Docker (dual-stack)

| Nome rete | Subnet (IPv4 + IPv6) | Internal |
| :--- | :--- | :--- |
EOF
  if [ -n "$net_rows" ]; then printf '%b' "$net_rows"; else printf '| (nessuna rete raccolta) | — | — |\n'; fi

  cat <<EOF

## Stack e Container Attivi

| Stack | Servizio | Immagine | IPv4 | IPv6 | Porte |
| :--- | :--- | :--- | :--- | :--- | :--- |
EOF
  if [ -n "$ctr_rows" ]; then printf '%b' "$ctr_rows"; else printf '| — | — | — | nessun container attivo | — | — |\n'; fi
} > "$OUT"

printf 'update-context: scritto %s\n' "$OUT"
