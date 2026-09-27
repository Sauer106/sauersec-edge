# Cloudflare Tunnel for Tier 3

A dedicated tunnel runs **on the edge VPS**, separate from the homelab's own tunnel.

1. In Zero Trust, go to **Networks → Tunnels → Create a tunnel** (type: cloudflared) and name it after the VPS.
2. Install the connector on the VPS:
   ```sh
   curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
   echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
     > /etc/apt/sources.list.d/cloudflared.list
   apt update && apt install -y cloudflared
   cloudflared service install <TUNNEL_TOKEN>
   ```
3. Add a public hostname route:
   - Hostname: `edge.example.com`. Choose a bland name; filters match on words like "vpn."
   - Service: **HTTP** → `127.0.0.1:10000`. Use the explicit IPv4 address, not `localhost` (see Lessons learned, L1).
   - **No** Cloudflare Access policy, since tunnel clients can't complete an interactive login.
4. Verify:
   ```sh
   curl -i https://edge.example.com/<RANDOM_WS_PATH>   # expect 400 Bad Request (non-WS request reached Xray)
   ```
   A real WebSocket upgrade (with a valid 16-byte `Sec-WebSocket-Key`) returns `101 Switching Protocols`.

Notes: Cloudflare closes idle connections after about 100 s, so SSH clients should set `ServerAliveInterval 25`. Bot Fight Mode can interfere with non-browser clients.
