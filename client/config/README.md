# sing-box client config

`client.example.json` is the template. Fill in the placeholders and install it as root-only:

```sh
sudo mkdir -p /usr/local/etc/nyc-vpn
sudo install -m 600 -o root -g wheel client.json /usr/local/etc/nyc-vpn/client.json
sudo sing-box check -c /usr/local/etc/nyc-vpn/client.json
```

The `auto` (urltest) group is kept for manual `sing-box run` sessions. `nyc-vpn` strips it at connect time and pins every reference to the chosen path (see design decision D7).

| DNS rule | Why |
|---|---|
| Tunnel hostname → `bootstrap` (DoH, no detour) | Prevents a resolution loop once system DNS points at sing-box (L7) |
| SSO hostname → `public` | Legacy work-around from before the real L8 fix; safe to remove |
| Lab suffix → `pihole` through the tunnel | Split-horizon lab names |
| Everything else → `public` through the tunnel | The local network never sees lookups |
