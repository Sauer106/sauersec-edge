# Lessons learned

The bugs that took the longest, how each was isolated, and the root cause. Most were found by **bisecting the path**: testing each hop on its own until one of them failed.

---

## L1 · 502 from Cloudflare: `localhost` means IPv6

**Symptom:** `curl https://edge.example.com/<path>` returned `HTTP/2 502`, while the same request on the VPS against `127.0.0.1:10000` returned the expected `400 Bad Request` from Xray's WS inbound.

**Isolation:** `journalctl -u cloudflared` showed `dial tcp [::1]:1000: connect: connection refused`.

**Root cause:** Two problems in one field. The port had a typo (`1000`), and `localhost` resolved to `::1` while Xray listened on IPv4 only.

**Fix:** Set the service URL to `http://127.0.0.1:10000`.

**Takeaway:** Write loopback origins as explicit IPv4 addresses.

---

## L2 · "The client is broken" was the server policy

**Symptom:** The GUI client (Hiddify) showed timeouts, then "failed to start background core."

**Isolation:** A minimal sing-box SOCKS client with one outbound worked immediately: `curl --socks5-hostname … http://10.0.6.2:9000` returned a `302`. So the server path was proven and the client was the variable. Separately, the client's built-in connectivity check fetched a public URL, which the (then lab-only) Xray routing blackholed by design, so the client reported every profile as dead.

**Takeaway:** When a GUI hides its logs, rebuild the smallest possible client and test one hop at a time. A health check that assumes internet egress will fail against a lab-only tunnel.

---

## L3 · A config edit silently restored old routing

**Symptom:** The next day, the full tunnel had no internet.

**Isolation:** A dump of `routing` / `outbounds` (with secrets filtered out) showed the final rule was back to `tcp,udp → block`, and the private-range rule was gone. A hand edit had started from an older copy of the rules.

**Takeaway:** Every scripted change writes a timestamped backup first. When editing, print the routing section and review it before restarting Xray.

---

## L4 · Sniffing broke split-horizon names

**Symptom:** Lab names resolved correctly through the tunnel (`proxmox.example.com → 10.0.6.3`), but HTTPS died right after the ClientHello (`SSL_ERROR_SYSCALL`). The same request *from the VPS* returned `200`, and `nc` could reach 443.

**Isolation:** The Xray log showed `accepted tcp:10.0.6.3:443 [vless-ws-cdn -> direct]`, so routing was fine. The inbound config had `sniffing.destOverride: [http, tls, quic]`, and `getent hosts proxmox.example.com` on the VPS returned nothing.

**Root cause:** Xray replaced the destination IP with the sniffed SNI, then resolved that name with public DNS, where the name doesn't exist.

**Fix:** Set `"routeOnly": true` on both inbounds.

---

## L5 · Proxy mode isn't VPN mode

**Symptom:** `curl https://ifconfig.me` returned the local network's IP while "connected."

**Root cause:** The client's only inbound was `mixed` (a local SOCKS/HTTP proxy). Terminal tools, SSH and raw DNS ignore the system proxy.

**Fix:** Add a `tun` inbound with `auto_route` and `strict_route`.

---

## L6 · macOS resolver vs. TUN DNS

**Symptom:** With system DNS set to the TUN address, `dig @172.19.0.2 name` worked, but `dscacheutil -q host -a name …` and Safari hung.

**Root cause:** mDNSResponder binds its queries to the physical interface, so they never entered the TUN. `dig` doesn't bind, which is why it worked.

**Fix:** A sing-box `direct` inbound on `127.0.0.1:53` feeding `hijack-dns`, with system DNS set to `127.0.0.1`.

---

## L7 · The resolution loop

**Symptom:** After switching to `127.0.0.1`, lab names hung while public names (from cache) worked.

**Root cause:** `default_domain_resolver` was the macOS system resolver, which was now sing-box itself. Resolving the tunnel's own server name went sing-box → system → sing-box → Pi-hole rule → needs the tunnel.

**Fix:** A DoH bootstrap server with no detour, plus an explicit rule sending the tunnel hostname to that bootstrap server.

---

## L8 · One name hung, and only in the system resolver

**Symptom:** Every SSO-protected app spun forever. `dig` answered A, AAAA and HTTPS (type 65) queries instantly. `dns-sd -G v4` for the SSO hostname never returned, while other names answered in under 100 ms, including other names in the same zone.

**Isolation:** Wrong hypotheses were ruled out one test at a time:
- The SSO service was healthy (checked directly by lab IP).
- The public route was healthy (checked from the VPS).
- It wasn't IPv6: the AAAA query was answered.
- It wasn't the HTTPS record: the type 65 query was answered too.
- A `tcpdump` on `lo0` showed the system resolver **never sent the query** to sing-box.

What stood out: the SSO host was the only name in the zone that Pi-hole didn't hold locally, so it was forwarded upstream to the Cloudflare-proxied public record.

**Fix:** Route that one name to the public resolver (still through the tunnel) instead of Pi-hole. The cleaner long-term fix is a Pi-hole local record plus a Traefik route, so every lab-facing name resolves the same way.

**Takeaway:** Check the result against your hypothesis before applying the fix. Two "obvious" patches (answering AAAA immediately, blocking HTTPS records) would have added config without fixing anything.

---

## L9 · zsh reserved names

`LINES` is a special parameter in zsh (the terminal height). `typeset -a LINES` fails with *can't change type of a special parameter*. Also avoid `path`, `status`, `COLUMNS` and `PROMPT` as variable names in zsh.

---

## L10 · Making disconnect feel instant

Disconnect felt slow for three separate reasons:
1. **zsh defers traps until a foreground `sleep` or `curl` returns.** Fix: run waits as `cmd & wait $!`, since `wait` is interruptible.
2. **The health checker's child processes kept the job alive.** Fix: `pkill -P $HPID` before killing the checker itself.
3. **`networksetup` calls are serialized by the system.** Fix: restore the *active* service first, signal the UI, then restore the rest in the background. The state file is removed only when all of them are done, so crash safety is unchanged.

Launchd's default 10-second `ThrottleInterval` also swallowed quick Cancel-then-Connect clicks. Setting it to `1` fixed that.
