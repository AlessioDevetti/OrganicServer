## Network & Connectivity Guidelines

1. **Management Plane Protection (Anti-Lockout):**
   - Never restart, reload, or flush the primary network interface, firewall (`nftables`/`ufw`), or VPN tunnels (e.g., `wg-quick@*`) during an automated run.
   - Always treat active SSH ports and management VPN interfaces as immutable infrastructure.

2. **Dual-Stack Discipline (IPv4 & IPv6):**
   - Assume the host operates in a dual-stack environment unless `.ai/CONTEXT.md` explicitly states IPv4-only.
   - When auditing connectivity or firewall rules, verify **both** protocol families (`ip -4 a` / `ip -6 a`, `ip -4 r` / `ip -6 r`, `ss -tulnp`).
   - Remember that ICMPv6 (Neighbor Discovery, Router Advertisements, Packet Too Big) is mandatory for IPv6 operation — never suggest dropping all ICMP traffic.

3. **Port Binding & Reverse Proxy Hygiene:**
   - Before deploying or modifying any service/container, verify port availability with `ss -tulnp` to prevent bind collisions (e.g., port 53 with `systemd-resolved`, or ports 80/443/25).
   - Internal services must bind to `127.0.0.1` / `[::1]` or an internal Docker/VPN bridge interface rather than `0.0.0.0` / `[::]` unless explicitly exposed through the reverse proxy.

4. **DNS & Outbound Health Verification:**
   - During the 06:00 audit, test both IPv4 and IPv6 outbound reachability and DNS resolution (`resolvectl status` or `dig`/`getent hosts`).
   - If outbound connectivity fails during a scheduled run, **abort package/image updates immediately**, log the diagnostic output in `.ai/REPORT.md`, and exit cleanly without modifying network configs.