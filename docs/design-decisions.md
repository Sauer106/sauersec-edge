# Design decisions

Each entry: the decision, the alternatives considered, and why.

---

## D1 · Three tiers, ordered by cost

**Decision:** Tailscale → REALITY → CDN, preferring the cheapest working path.

**Why:** Each tier adds latency and moving parts. Tailscale is direct and fast; REALITY adds one hop through the VPS; CDN adds Cloudflare's edge and a tunnel. Using the cheapest working tier keeps everyday use fast while keeping a path open on hostile networks.

---

## D2 · Separate transport for the CDN tier

**Decision:** A second Xray inbound (VLESS over WebSocket) instead of trying to put REALITY behind Cloudflare.

**Alternatives:** REALITY behind Cloudflare (impossible — Cloudflare terminates TLS, so the borrowed handshake never reaches the origin); gRPC or XHTTP transports.

**Why WebSocket:** It's the transport every client reliably supports, and it passes Cloudflare's proxy without special settings. Xray now marks WS as deprecated in favor of XHTTP, so migrating is on the roadmap.

---

## D3 · Cloudflare Tunnel instead of a proxied DNS record

**Decision:** Run `cloudflared` on the VPS and point a tunnel hostname at `http://127.0.0.1:10000`.

**Alternatives:** An orange-cloud A record pointing at the VPS IP, with an origin certificate on port 443 or 8443.

**Why:**
- No inbound port. Port 443 stays with REALITY, and the WS inbound binds to loopback only.
- The VPS IP never appears in DNS, so a filter looking up the hostname only ever sees Cloudflare anycast IPs.
- No origin certificate to manage.
- It has its own tunnel, separate from the homelab tunnel, so the two fail independently.

**Gotcha:** The service URL must be `127.0.0.1`, not `localhost`. `cloudflared` resolved `localhost` to `::1`, while Xray listened on IPv4 only, which caused a 502.

---

## D4 · Internet egress from the VPS, not from home

**Decision:** Full-tunnel traffic exits from the VPS. Only lab ranges go over the tailnet.

**Alternative:** Hairpin all traffic home, through a SOCKS proxy on the tailnet, so websites see the residential IP.

**Why:** Fewer dependencies (the tunnel survives a home ISP outage), lower latency (no NYC→PA→internet round trip), and no home-upload bottleneck. The privacy property that matters, the local network seeing only encrypted traffic to Cloudflare, holds either way. The home exit can be added later for specific destinations only if needed.

**Rejected approach:** Setting a Tailscale exit node on the VPS. That reroutes *all* of the VPS's traffic, including REALITY replies and `cloudflared`, which breaks both.

---

## D5 · Allow-then-deny routing on the edge

**Decision:**
1. Lab and tailnet ranges → `direct`.
2. All private, loopback, link-local and ULA ranges → `block`.
3. Everything else → `direct` (internet).

**Why:** Tunnel users should reach the lab and the internet, but never the VPS's own localhost services, the cloud provider's metadata endpoint (`169.254.169.254`), or any other private network the VPS can see. Rule 1 comes first, so specific lab addresses (like Pi-hole `10.0.2.7/32`) are allowed even though rule 2 covers `10.0.0.0/8`.

`domainStrategy: IPIfNonMatch` makes Xray resolve hostnames before matching, so `evil.example → 127.0.0.1` can't slip past rule 2.

---

## D6 · `sniffing.routeOnly: true`

**Decision:** Keep sniffing on (it's needed for domain-based routing), but only use the sniffed name for routing, never to rewrite the destination.

**Why:** With `destOverride` on, Xray replaced the requested `10.0.6.3` with the sniffed SNI `proxmox.example.com` and resolved it using public DNS. That name exists only in the lab's split-horizon DNS, so the connection died right after the TLS ClientHello. See Lessons learned, L4.

---

## D7 · Lock the path at connect time

**Decision:** The client probes REALITY and then CDN once, and uses the first one that works for the whole session.

**Alternative:** sing-box `urltest`, which re-tests every minute and switches to the fastest path.

**Why:** Mid-session switching dropped long-lived connections like SSH. Predictability beats small latency wins here. The tradeoff is that if the path dies, the user reconnects, and the menu offers **Reconnect** for exactly that.

---

## D8 · Point system DNS at `127.0.0.1`, not a TUN address

**Decision:** sing-box runs a `direct` inbound on `127.0.0.1:53` that hijacks queries into its DNS router. macOS DNS is set to `127.0.0.1` while the tunnel is up.

**Why:** macOS's resolver (mDNSResponder) binds its queries to the physical interface. So queries to a TUN-side address like `172.19.0.2` left through Wi-Fi and went unanswered. `dig` worked, because it doesn't bind, which hid the problem. Loopback is always reachable.

---

## D9 · Bootstrap resolver outside the tunnel

**Decision:** A DoH resolver (`https://1.1.1.1`) with no detour, used for the tunnel's own server name and as `default_domain_resolver`.

**Why:** Once system DNS points at sing-box, resolving the tunnel endpoint through the system resolver becomes circular: resolving `edge.example.com` needs the tunnel, and the tunnel needs `edge.example.com`. Using DoH instead of plain UDP 53 also survives networks that block outside DNS.

---

## D10 · Three-layer DNS restore

**Decision:** An EXIT trap in the script, a launchd watchdog every 15 s, and the watchdog also running at boot.

**Why:** A client that rewrites system DNS and then dies leaves the machine with no working DNS. Each layer covers a failure the others can't:

| Failure | Covered by |
|---|---|
| Disconnect, Ctrl-C, sing-box crash, script error | EXIT trap |
| `kill -9` on the script | Watchdog (checks the script PID from the state file) |
| Reboot or power loss mid-session | Watchdog's `RunAtLoad` |

The state file records each service's **original** DNS, so a manually configured resolver is restored exactly instead of being reset to DHCP.

---

## D11 · Least-privilege menu bar control

**Decision:** SwiftBar runs as the user and calls `sudo -n` for exactly three commands. The work runs in a root LaunchDaemon.

**Alternatives:** Running SwiftBar as root (no), or a blanket NOPASSWD rule (no).

**Why:** The UI can start, stop and restore. It can't run arbitrary commands. The sudoers file is validated with `visudo -c` before it's installed, so a typo can't lock out `sudo`.
