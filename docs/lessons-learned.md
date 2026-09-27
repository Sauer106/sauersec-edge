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

## L8 · Some names hung, but only in Safari

**Symptom:** SSO-protected apps, and later GitHub, spun forever in Safari. Terminal tools (`curl`, `dig`) and other sites worked. `dns-sd -G v4` hung for exactly the names Safari was stuck on (for example `github.githubassets.com`), while other names answered in under 100 ms.

**Wrong turns:** The service was healthy. It wasn't AAAA handling or HTTPS (type 65) records either: sing-box answered every query type instantly when asked directly. A per-host exception sending one name to the public resolver *seemed* to fix the SSO host, but only because reconnecting cleared the stuck lookup.

**Isolation:**
1. `tcpdump` on loopback showed macOS **never sent** the stuck queries to sing-box.
2. `scutil --dns` showed a second resolver, marked `Scoped` with `if_index: en0`, that also pointed at `127.0.0.1`.
3. Quitting Safari (dropping its in-flight lookups) made the same name resolve immediately.

**Root cause:** Safari scopes some lookups to the active interface. A lookup scoped to `en0` can't reach an address that exists only on loopback, so it sits in flight forever. `dns-sd` then attaches to the same stuck lookup, which is why it hung for the same names.

**Fix:** Point system DNS at the Mac's own LAN address, which both scoped and unscoped lookups can reach, and guard it with a pf rule (see D8).

**Takeaway:** Check the result against your hypothesis before applying the fix. Two "obvious" patches (answering AAAA immediately, blocking HTTPS records) would have added config without fixing anything, and a third looked like it worked for the wrong reason.

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
