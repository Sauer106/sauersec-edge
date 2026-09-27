# Threat model

## Assets

- The homelab's internal services (Proxmox, the SSO provider, dashboards, game servers)
- Tunnel credentials (the VLESS UUID and the REALITY key pair)
- The user's browsing and DNS activity while on untrusted networks

## Adversaries and what they can do

| Adversary | Capability | Mitigation |
|---|---|---|
| **Restrictive local network** (guest network, corporate filter) | Blocks by SNI and destination IP, may block outside DNS, can see traffic metadata | Tier 2 imitates a real site's TLS handshake. Tier 3 only ever connects to Cloudflare anycast IPs using an ordinary hostname. Client DNS goes through the tunnel (or DoH for bootstrap), so the network never sees plaintext lookups |
| **Passive observer on the local network** | Reads unencrypted traffic and DNS | Full-tunnel TUN capture, IPv4 and IPv6. DNS is forced into the tunnel |
| **Internet scanner hitting the VPS** | Probes open ports | Only 443 is open (REALITY, which serves the borrowed site to unauthenticated probes). The WS inbound listens on loopback only. SSH is reachable over the tailnet |
| **Someone holding a leaked UUID** | Uses the tunnel | Routing limits them to the lab subnet (plus internet egress). Private ranges and cloud metadata are blocked. The UUID is rotatable, and was rotated after exposure |
| **A compromised VPS** | Pivots into the lab | The Tailscale ACL scopes `tag:vps` to the lab subnet and Pi-hole DNS only. Lab services still require SSO. The VPS holds no lab credentials |
| **A local non-root process on the Mac** | Tampers with the client | The config is root-owned (0600). The sudoers rule only allows start, stop and restore. The scripts live in root-owned paths |

## Out of scope and known limitations

- **Cloudflare can see Tier 3 traffic in the clear** at its edge. This is inherent to any CDN front, and the inner protocol is VLESS. Lab traffic is additionally protected by TLS to Traefik.
- **The VPS provider** can see egress traffic metadata.
- **WebSocket transport is deprecated** in Xray, so an unreviewed Xray upgrade could remove it. The transport should be pinned or migrated to XHTTP.
- **Active probing of Tier 3** can identify a WebSocket endpoint behind Cloudflare. The random path reduces the chance of an opportunistic hit, but it isn't a secret the design relies on.
- **Captive portals** need the tunnel to be off until the user has logged in.
- **Mid-session failover is deliberately disabled** (see D7). If a path dies, the user reconnects.
- **The macOS client manages system DNS by hand.** A Network Extension based client would integrate more cleanly, at the cost of the pick-once behavior.
