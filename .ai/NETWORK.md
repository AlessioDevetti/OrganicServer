# Network & Connectivity Guidelines

## 1. Management Plane Protection (Anti-Lockout)
- Never restart, reload, or flush the primary network interface, firewall (`nftables`/`ufw`), or VPN tunnels (e.g., `wg-quick@*`) during an automated run.
- Always treat active SSH ports and management VPN interfaces as immutable infrastructure.

## 2. Dual-Stack Service Plane
- All application traffic, container-to-container communication, and published service ports support **both IPv4 and IPv6** as first-class transports.
- The reverse proxy and exposed services listen on both families; backend/database services stay on the isolated `internal` network and do not publish host ports.
- When auditing connectivity or firewall rules, verify **both** protocol families (`ip -4 a` / `ip -6 a`, `ip -4 r` / `ip -6 r`, `ss -4 -tulpn` / `ss -6 -tulpn`).
- Remember that ICMPv6 (Neighbor Discovery, Router Advertisements, Packet Too Big) is mandatory for IPv6 operation — never suggest dropping all ICMP. ICMPv4 (echo, unreachable, time-exceeded) is required for diagnostics and should be rate-limited, not dropped.

## 3. Port Binding & Reverse Proxy Hygiene
- Before deploying or modifying any service/container, verify port availability with `ss -tulpn` (both families) to prevent bind collisions (e.g., port 53 with `systemd-resolved`, or ports 80/443/25).
- Internal services bind to `[::1]`/`127.0.0.1` or an isolated Docker network, never to a public address.
- The reverse proxy binds `[::]` and `0.0.0.0` on the `edge` network, only for the ports explicitly authorised in `nftables` (section 8).

## 4. DNS & Outbound Health Verification
- During the 06:00 audit, test both IPv4 and IPv6 outbound reachability and DNS resolution (`resolvectl status` or `dig`/`getent hosts` / `getent ahostsv6`).
- IPv4 egress uses Docker NAT over RFC 1918 ranges; IPv6 is routed natively. A-only and AAAA-only names must both resolve.
- If outbound connectivity fails during a scheduled run, **abort package/image updates immediately**, log the diagnostic output in `.ai/REPORT.md`, and exit cleanly without modifying network configs.

## 5. Docker Dual-Stack Network Schema

Docker workloads use exactly two networks. Both are created once during host bootstrap and referenced by stacks as `external: true`; stacks never redefine them.

| Network | Role | IPv4 subnet | IPv6 subnet | Gateway | `internal` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `edge` | Routed, externally exposed: reverse proxy and published services | `<EDGE_V4>::/24` (RFC 1918) | `<EDGE_SUBNET>::/64` (provider-delegated) | `.1` / `::1` | `false` |
| `internal` | Backend and databases, no outbound routing | `<INTERNAL_V4>::/24` (RFC 1918) | `<ULA_SUBNET>::/64` | `.1` / `::1` | `true` |

- Values in `<...>` are placeholders: `<EDGE_V4>` / `<INTERNAL_V4>` are RFC 1918 `/24` networks (example `172.20.0.0/24` and `172.30.0.0/24`); `<EDGE_SUBNET>` is a `/64` slice of the provider-delegated prefix; `<ULA_SUBNET>` is a `/64` built from `fd00::/8` plus a 40-bit global ID (RFC 4193) and a 16-bit subnet ID. All must be recorded in `.ai/CONTEXT.md`; never invent a prefix.
- `edge` is the only network with a route to the outside; inbound traffic is filtered by `nftables` (section 8). IPv4 egress uses Docker masquerade; IPv6 is native (no NAT66).
- `internal` uses `internal: true`: Docker installs no default route (neither family) and containers have no outbound access. A service that needs egress uses a proxy on the edge network; never disable `internal` for convenience.
- Networks are defined once at bootstrap with IPv6 enabled, and stack compose files reference them as `external: true`; enabling IPv6 in the Docker daemon is a Tier 3 change reserved to the operator.

## 6. Deterministic Static Addressing

Container addresses are assigned statically and deterministically through `ipv4_address` and `ipv6_address`; DHCP and SLAAC are not used on Docker networks. The IPv4 host ID mirrors the IPv6 host ID (e.g. `.20` / `::20`).

| Network | Reserved host IDs | Assignment convention |
| :--- | :--- | :--- |
| `edge` | `.1`/`::1` gateway; `.2`–`.9`/`::2`–`::f` network infrastructure; `.10`–`.31`/`::10`–`::1f` reverse proxy and edge services | `.32`/`::20` upward, in registration order in `.ai/CONTEXT.md` |
| `internal` | `.1`/`::1` gateway; `.2`–`.9`/`::2`–`::f` network infrastructure | `.10`/`::10` upward, assigned per service and stable across redeploys |

- A service keeps the same host ID for its whole life; a released host ID is not reassigned without updating `.ai/CONTEXT.md`.
- The ULA uses a random 40-bit global ID per RFC 4193 inside `fd00::/8`, generated once and documented; never reuse a provider prefix for internal networks.
- Every `(container, ipv4_address, ipv6_address, ports)` tuple must be recorded in `.ai/CONTEXT.md` and in the stack compose file.

```yaml
# Reference fragment — values remain placeholders
networks:
  edge:
    external: true
  internal:
    external: true

services:
  <service>:
    networks:
      internal:
        ipv4_address: "<INTERNAL_V4>::10"
        ipv6_address: "<ULA_SUBNET>::10"
```

## 7. IPv4 NAT, native IPv6 routing, NAT64/DNS64

- IPv6 traffic is routed natively: no NAT66, no masquerading, no port-forwarding toward containers.
- IPv4 uses RFC 1918 private ranges on Docker bridges with Docker masquerade (NAT) for egress. No container gets a public IPv4 address unless a public range is explicitly delegated and routed by the operator (Tier 3).
- NAT64/DNS64 at the gateway remains available as a fallback for IPv6-only hosts reaching IPv4-only destinations, but it is no longer the primary path for service traffic.
- Container DNS must resolve both A and AAAA records; verify with `getent hosts <fqdn>` and `getent ahostsv6 <fqdn>`.
- Gateway-level NAT64/DNS64 or public IPv4 delegation is a Tier 3 change owned by the human operator.

## 8. nftables Requirements

- Use an `inet` table. Default policy is `drop` on both the `input` and `forward` chains.
- Allow only loopback, `established,related` traffic, essential ICMPv6 (ND/RA/PTB), rate-limited ICMPv4, and the explicitly authorised `(address, porta)` pairs for both families. No catch-all port ranges.
- The authorised pairs are the single source of truth for exposure and must be mirrored in `.ai/CONTEXT.md`; a new published port requires a queued task, not a runtime rule.
- ICMPv6 must always pass: Neighbor Solicitation/Advertisement (types 135/136), Router Solicitation/Advertisement (133/134), and Packet Too Big (type 2) for PMTUD. Destination Unreachable, Time Exceeded, and Parameter Problem should also be permitted. Rate-limiting is acceptable; dropping all ICMPv6 is not.
- ICMPv4 (echo, destination-unreachable, time-exceeded, parameter-problem) should be permitted with rate-limiting.
- Docker installs its own NAT/publishing rules for both families: verify Docker did not create unintended exposure (`ss -4 -tulpn`, `ss -6 -tulpn`, `nft list ruleset`).
- A `drop` policy on `forward` can interfere with Docker's own forwarding chains: integration must be validated by the operator before rollout, never by the agent.
- Every change to these rules is Tier 3 (human-only); the agent may only read the ruleset and report.

```nftables
# Conceptual model — the agent NEVER applies these rules (Tier 3)
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        ct state established,related accept
        iifname "lo" accept
        ip6 nexthdr ipv6-icmp accept          # ND, RA, PTB — consider rate-limiting
        ip saddr <IPV4_REVERSE_PROXY> tcp dport { 80, 443 } accept
        ip6 saddr <IPV6_REVERSE_PROXY> tcp dport { 80, 443 } accept
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
        ip6 nexthdr ipv6-icmp accept
        ip daddr <IPV4_CONTAINER> tcp dport <PORTA> accept
        ip6 daddr <IPV6_CONTAINER> tcp dport <PORTA> accept
    }
}
```

## 9. Read-Only Verification

```bash
ip -4 a
ip -6 a
ip -4 r
ip -6 r
ss -4 -tulpn
ss -6 -tulpn
docker network inspect edge
docker network inspect internal
docker inspect --format '{{json .NetworkSettings.Networks}}' <container>
nft list ruleset
getent hosts <fqdn>
getent ahostsv6 <fqdn>
```

Any unexpected listener on either family, an ad-hoc subnet on a Docker network, or a missing essential ICMP rule must be recorded as an anomaly in `.ai/REPORT.md` and proposed as a task in `.ai/QUEUE.md`.
