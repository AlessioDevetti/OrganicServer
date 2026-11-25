# Network & Connectivity Guidelines

## 1. Management Plane Protection (Anti-Lockout)
- Never restart, reload, or flush the primary network interface, firewall (`nftables`/`ufw`), or VPN tunnels (e.g., `wg-quick@*`) during an automated run.
- Always treat active SSH ports and management VPN interfaces as immutable infrastructure.

## 2. IPv6-Only Service Plane (Dual-Stack Management)
- All application traffic, container-to-container communication, and published service ports use **IPv6 exclusively**. IPv4 is not a supported transport for application services.
- The management plane may keep a private IPv4 address for legacy administration; this never authorises publishing a service over IPv4.
- When auditing connectivity or firewall rules, verify **both** protocol families (`ip -4 a` / `ip -6 a`, `ip -4 r` / `ip -6 r`, `ss -tulnp`, `ss -6 -tulnp`). Any public IPv4 listener is a finding to record in `.ai/REPORT.md`, not a supported configuration.
- Remember that ICMPv6 (Neighbor Discovery, Router Advertisements, Packet Too Big) is mandatory for IPv6 operation — never suggest dropping all ICMP traffic.

## 3. Port Binding & Reverse Proxy Hygiene
- Before deploying or modifying any service/container, verify port availability with `ss -6 -tulnp` to prevent bind collisions (e.g., port 53 with `systemd-resolved`, or ports 80/443/25).
- Internal services must bind to `[::1]` or an isolated Docker/VPN interface, never to `0.0.0.0` or a public IPv4 address.
- Only the reverse proxy may bind `[::]` on the `edge-v6` network, and only for the ports explicitly authorised in `nftables` (section 8).

## 4. DNS & Outbound Health Verification
- During the 06:00 audit, test both IPv4 and IPv6 outbound reachability and DNS resolution (`resolvectl status` or `dig`/`getent hosts`).
- Outbound IPv6 is the operative path; IPv4-only destinations are resolved through DNS64/NAT64 at the gateway (section 7), never by adding IPv4 to the host.
- If outbound connectivity fails during a scheduled run, **abort package/image updates immediately**, log the diagnostic output in `.ai/REPORT.md`, and exit cleanly without modifying network configs.

## 5. Docker IPv6 Network Schema

Docker workloads use exactly two IPv6 networks. Both are created once during host bootstrap and referenced by stacks as `external: true`; stacks never redefine them.

| Network | Role | IPv6 subnet | Gateway | `internal` |
| :--- | :--- | :--- | :--- | :--- |
| `edge-v6` | Routed, externally exposed: reverse proxy and published services | `<EDGE_SUBNET>::/80` | `<EDGE_SUBNET>::1` | `false` |
| `internal-v6` | Backend and databases, no outbound routing | `<ULA_SUBNET>::/64` | `<ULA_SUBNET>::1` | `true` |

- Values in `<...>` are placeholders: `<EDGE_SUBNET>` is one `/80` slice of the provider-delegated prefix; `<ULA_SUBNET>` is a `/64` built from `fd00::/8` plus a 40-bit global ID (RFC 4193) and a 16-bit subnet ID. Both must be recorded in `.ai/CONTEXT.md`; never invent a prefix.
- `edge-v6` is the only network with a route to the outside; inbound traffic is filtered by `nftables` (section 8).
- `internal-v6` uses `internal: true`: Docker installs no default route and containers have no outbound access. A service that needs egress uses a proxy on the edge network; never disable `internal` for convenience.
- No IPv4 subnet is declared. Networks are defined once at bootstrap with IPv6 enabled, and stack compose files reference them as `external: true`; enabling IPv6 in the Docker daemon is a Tier 3 change reserved to the operator.

## 6. Deterministic Static Addressing

Container addresses are assigned statically and deterministically through `ipv6_address`; DHCPv6 and SLAAC are not used on Docker networks.

| Network | Reserved host IDs | Assignment convention |
| :--- | :--- | :--- |
| `edge-v6` | `::1` gateway; `::2`–`::f` network infrastructure; `::10`–`::1f` reverse proxy and edge services | `::20` upward, in registration order in `.ai/CONTEXT.md` |
| `internal-v6` | `::1` gateway; `::2`–`::f` network infrastructure | `::10` upward, assigned per service and stable across redeploys |

- A service keeps the same host ID for its whole life; a released host ID is not reassigned without updating `.ai/CONTEXT.md`.
- The ULA uses a random 40-bit global ID per RFC 4193 inside `fd00::/8`, generated once and documented; never reuse a provider prefix for internal networks.
- `/80` subnets are allowed only for statically addressed Docker segments; never split a `/64` intended for hosts that rely on autoconfiguration.
- Every `(container, ipv6_address, ports)` tuple must be recorded in `.ai/CONTEXT.md` and in the stack compose file.

```yaml
# Reference fragment — values remain placeholders
networks:
  edge-v6:
    external: true
  internal-v6:
    external: true

services:
  <service>:
    networks:
      internal-v6:
        ipv6_address: "<ULA_SUBNET>::10"
```

## 7. NAT64/DNS64 and No Masquerading

- IPv6 traffic is routed natively: no NAT66, no masquerading, no port-forwarding toward containers.
- The host and containers have no public IPv4 address and no IPv4 default route. A private management IPv4 address, where present, is not a service transport.
- IPv4-only legacy endpoints are reached exclusively through DNS64/NAT64 at the network gateway, using the well-known prefix `64:ff9b::/96` (RFC 6052) or the provider-assigned prefix.
- Container DNS must point to the DNS64 resolver so that A-only names receive a synthesized AAAA record; verify with `getent ahostsv6 <fqdn>`.
- If a tool cannot operate over IPv6 or through NAT64, record the limitation in `.ai/REPORT.md` and open a task; never add IPv4 to the host or containers as a workaround.
- DNS64/NAT64 configuration on the gateway is a Tier 3 change owned by the human operator.

## 8. nftables Requirements

- Use an `inet` table. Default policy is `drop` on both the `input` and `forward` chains.
- Allow only loopback, `established,related` traffic, essential ICMPv6, and the explicitly authorised `(IPv6_container, porta)` pairs. No catch-all port ranges.
- The authorised pairs are the single source of truth for exposure and must be mirrored in `.ai/CONTEXT.md`; a new published port requires a queued task, not a runtime rule.
- ICMPv6 must always pass: Neighbor Solicitation/Advertisement (types 135/136), Router Solicitation/Advertisement (133/134), and Packet Too Big (type 2) for PMTUD. Destination Unreachable, Time Exceeded, and Parameter Problem should also be permitted. Rate-limiting is acceptable; dropping all ICMPv6 is not.
- No IPv4 `accept` rule for application services. IPv4 management access, if strictly required, stays under the same default-drop policy.
- Docker installs its own NAT/publishing rules: never publish ports in IPv4 and verify that Docker did not create IPv4 exposure (`ss -4 -tulnp`, `nft list ruleset`).
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
        ip6 saddr <IPV6_REVERSE_PROXY> tcp dport { 80, 443 } accept
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
        ip6 nexthdr ipv6-icmp accept
        ip6 saddr <IPV6_REVERSE_PROXY> ip6 daddr <IPV6_CONTAINER> tcp dport <PORTA> accept
    }
}
```

## 9. Read-Only Verification

```bash
ip -6 a
ip -6 r
ss -6 -tulnp
ss -4 -tulnp
docker network inspect edge-v6
docker network inspect internal-v6
docker inspect --format '{{json .NetworkSettings.Networks}}' <container>
nft list ruleset
getent ahostsv6 <fqdn>
```

Any public IPv4 listener, IPv4 subnet on a Docker network, or missing essential ICMPv6 rule must be recorded as an anomaly in `.ai/REPORT.md` and proposed as a task in `.ai/QUEUE.md`.
