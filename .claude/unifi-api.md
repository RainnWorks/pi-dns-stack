# UniFi Network API Reference

Complete reference for the local UniFi Network API on UniFi OS gateways (UDM, UDR, UCG, Cloud Gateway). This is the local device API, not the cloud API at api.ui.com.

## Base URL

```
https://<gateway-ip>/proxy/network/api/s/<site>/
```

- `<gateway-ip>`: IP of the gateway (e.g. `192.168.99.1`)
- `/proxy/network`: required prefix on all UniFi OS devices — without it you get 404s
- `<site>`: almost always `default` for single-site setups
- Some v2 endpoints use `v2/api/site/default/` instead — noted where applicable

## Authentication

### API Key (preferred)

Generate at: **Settings > Control Plane > Integrations > API Keys** on the local gateway UI.

```bash
curl -sk https://<gateway-ip>/proxy/network/api/s/default/stat/health \
  -H "X-API-Key: YOUR_API_KEY"
```

No login, session, or cookie needed. Read-write on the local API.

### Session Auth (fallback if API key doesn't work for writes)

```bash
# Login — saves session cookie
curl -sk -X POST https://<gateway-ip>/api/auth/login \
  -H "Content-Type: application/json" \
  -c cookie.txt \
  -d '{"username": "localadmin", "password": "yourpassword"}'

# Extract CSRF token from cookies
CSRF=$(grep csrf cookie.txt | awk '{print $NF}')

# Use on all subsequent requests
curl -sk -b cookie.txt \
  -H "X-Csrf-Token: $CSRF" \
  https://<gateway-ip>/proxy/network/api/s/default/stat/health
```

Mutating requests (PUT/POST/DELETE) require the `X-Csrf-Token` header. Must use a **local admin account**, not a Ubiquiti cloud account.

## TLS

The gateway uses a self-signed certificate. Always use `-k` / `--insecure` with curl.

## Response Format

All responses:

```json
{
  "meta": { "rc": "ok" },
  "data": [ ... ]
}
```

On error:

```json
{
  "meta": { "rc": "error", "msg": "api.err.InvalidPayload" },
  "data": []
}
```

## Important: PUT Semantics

UniFi requires the **full object** on PUT — it is not a partial update. GET the object first, modify the fields you need, PUT the entire object back. The `_id` must appear both in the URL path and in the request body. Missing fields may be reset to defaults.

## Path Prefixes

- `rest/` — configuration objects (CRUD)
- `stat/` — live runtime/statistics data (read-only)
- `list/` — alternative read endpoint for some resources
- `cmd/` — imperative commands (adopt, restart, backup, etc.)
- `v2/api/site/default/` — newer v2 endpoints (traffic rules, AP groups)
- `integration/v1/sites/{site_id}/` — zone-based firewall

---

## 1. Networks / VLANs

| Operation | Method | Path |
|---|---|---|
| List | GET | `rest/networkconf` |
| Get one | GET | `rest/networkconf/{_id}` |
| Create | POST | `rest/networkconf` |
| Update | PUT | `rest/networkconf/{_id}` |
| Delete | DELETE | `rest/networkconf/{_id}` |

### Key Fields

| Field | Type | Description |
|---|---|---|
| `_id` | string | Object ID |
| `name` | string | Network name |
| `purpose` | string | `corporate`, `guest`, `vlan-only`, `wan`, `vpn-client`, `vpn-server` |
| `ip_subnet` | string | Network CIDR (e.g. `192.168.10.1/24`) |
| `vlan_enabled` | bool | Enable VLAN tagging |
| `vlan` | int | VLAN ID (1–4094) |
| `dhcpd_enabled` | bool | DHCP server active |
| `dhcpd_start` / `dhcpd_stop` | string | DHCP pool range |
| `dhcpd_leasetime` | int | Lease time in seconds |
| `dhcpd_dns_enabled` | bool | Must be `true` for dns fields to take effect |
| `dhcpd_dns_1` through `dhcpd_dns_4` | string | DNS servers handed to DHCP clients |
| `dhcpd_gateway_enabled` | bool | Use custom gateway |
| `dhcpd_gateway` | string | Custom gateway IP |
| `domain_name` | string | Local domain for DHCP clients |
| `igmp_snooping` | bool | IGMP snooping |
| `upnp_lan_enabled` | bool | Allow UPnP |
| `internet_access_enabled` | bool | Allow internet access |
| `intranet_access_enabled` | bool | Allow access to other local networks |
| `is_nat` | bool | NAT outbound traffic |
| `attr_no_delete` | bool | System network — cannot delete |

---

## 2. Firewall Rules (Legacy)

| Operation | Method | Path |
|---|---|---|
| List | GET | `rest/firewallrule` |
| Create | POST | `rest/firewallrule` |
| Update | PUT | `rest/firewallrule/{_id}` |
| Delete | DELETE | `rest/firewallrule/{_id}` |

Only returns user-created rules. System rules (index 3001+) are not accessible.

### Key Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Rule name |
| `enabled` | bool | Active |
| `ruleset` | string | `WAN_IN`, `WAN_OUT`, `WAN_LOCAL`, `LAN_IN`, `LAN_OUT`, `LAN_LOCAL`, `GUEST_IN`, `GUEST_OUT`, `GUEST_LOCAL` |
| `rule_index` | int | Processing order — lower = first. User rules start at 2000 |
| `action` | string | `accept`, `drop`, `reject` |
| `protocol` | string | `all`, `tcp`, `udp`, `tcp_udp`, `icmp` |
| `src_address` | string | Source IP/CIDR |
| `src_port` | string | Port, range (`80:90`), or comma-separated |
| `src_network_id` | string | Source network object ID (alternative to src_address) |
| `src_firewall_group_ids` | string[] | Source firewall group IDs |
| `src_mac` | string | Source MAC |
| `dst_address` | string | Destination IP/CIDR |
| `dst_port` | string | Destination port(s) |
| `dst_network_id` | string | Destination network object ID |
| `dst_firewall_group_ids` | string[] | Destination firewall group IDs |
| `state_established` | bool | Match established connections |
| `state_invalid` | bool | Match invalid state |
| `state_new` | bool | Match new connections |
| `state_related` | bool | Match related connections |
| `logging` | bool | Log matching traffic |
| `icmp_typename` | string | ICMP type (when protocol is `icmp`) |
| `ip_sec` | string | `match-ipsec`, `match-none` |

---

## 3. Firewall Groups

Reusable IP, network, or port sets referenced from firewall rules.

| Operation | Method | Path |
|---|---|---|
| List | GET | `rest/firewallgroup` |
| Create | POST | `rest/firewallgroup` |
| Update | PUT | `rest/firewallgroup/{_id}` |
| Delete | DELETE | `rest/firewallgroup/{_id}` |

### Key Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Group name |
| `group_type` | string | `address-group`, `ipv6-address-group`, `port-group` |
| `group_members` | string[] | IPs/CIDRs or port numbers |

---

## 4. Traffic Rules (v2)

Simplified rules from the Traffic Management UI.

| Operation | Method | Path |
|---|---|---|
| List | GET | `v2/api/site/default/trafficrules` |
| Create | POST | `v2/api/site/default/trafficrules` |
| Get one | GET | `v2/api/site/default/trafficrules/{id}` |
| Update | PUT | `v2/api/site/default/trafficrules/{id}` |
| Delete | DELETE | `v2/api/site/default/trafficrules/{id}` |

### Key Fields

| Field | Type | Description |
|---|---|---|
| `description` | string | Rule name |
| `enabled` | bool | Active |
| `action` | string | `BLOCK`, `ALLOW`, `THROTTLE` |
| `matching_target` | string | `INTERNET`, `LOCAL`, `IP`, `DOMAIN` |
| `target_devices` | object[] | `[{"type":"ALL_DEVICES"}]` or specific clients/networks |
| `bandwidth_limit` | object | `{"upload_limit_kbps": 5000, "download_limit_kbps": 10000, "enabled": true}` |
| `schedule` | object | Time-based activation |

Gotcha: successful PUT returns `201 Created`, not `200 OK`.

---

## 5. Zone-Based Firewall (Network 8.x+)

| Operation | Method | Path |
|---|---|---|
| List zones | GET | `integration/v1/sites/{site_id}/firewall/zones` |
| Create zone | POST | `integration/v1/sites/{site_id}/firewall/zones` |
| Update zone | PUT | `integration/v1/sites/{site_id}/firewall/zones/{id}` |
| Delete zone | DELETE | `integration/v1/sites/{site_id}/firewall/zones/{id}` |
| List policies | GET | `integration/v1/sites/{site_id}/firewall/policies` |

Built-in zones (`External`, `Internal`, `Gateway`, `VPN`, `Hotspot`) cannot be deleted. Zone-to-zone policy management via API is limited — full policy matrix must be configured in the UI.

---

## 6. Port Forwarding

| Operation | Method | Path |
|---|---|---|
| List | GET | `rest/portforward` |
| List (with UPnP) | GET | `stat/portforward` |
| Create | POST | `rest/portforward` |
| Update | PUT | `rest/portforward/{_id}` |
| Delete | DELETE | `rest/portforward/{_id}` |

### Key Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Rule name |
| `enabled` | bool | Active |
| `pfwd_interface` | string | `wan`, `wan2`, `both` |
| `proto` | string | `tcp_udp`, `tcp`, `udp` |
| `src` | string | Source filter (`any` or CIDR) |
| `dst_port` | string | External port(s) — single or range (`8080:8090`) |
| `fwd` | string | Internal destination IP |
| `fwd_port` | string | Internal destination port(s) |
| `log` | bool | Log matching traffic |

---

## 7. Routing

### Static Routes

| Operation | Method | Path |
|---|---|---|
| List (live table) | GET | `stat/routing` |
| List (user-defined) | GET | `rest/routing` |
| Create | POST | `rest/routing` |
| Update | PUT | `rest/routing/{_id}` |
| Delete | DELETE | `rest/routing/{_id}` |

### Key Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Route name |
| `enabled` | bool | Active |
| `type` | string | `nexthop-route`, `interface-route`, `blackhole` |
| `network` | string | Destination CIDR |
| `next_hop` | string | Next-hop IP (for nexthop-route) |
| `interface` | string | Outgoing interface: `WAN1`, `WAN2`, or a network `_id` |
| `distance` | int | Administrative distance |

---

## 8. Clients

| Endpoint | Method | Description |
|---|---|---|
| `stat/sta` | GET | Currently connected clients |
| `rest/user` | GET | All known clients (including offline) |
| `stat/alluser` | POST | Historical client data. Body: `{"type":"all","conn":"all","within":24}` |

### Client Fields

`hostname`, `mac`, `ip`, `network`, `vlan`, `is_wired`, `last_seen`, `signal` (wireless), `tx_bytes`, `rx_bytes`, `satisfaction`.

### Client Commands

POST to `cmd/stamgr`:

| Command | Fields | Description |
|---|---|---|
| `block-sta` | `mac` | Block a client |
| `unblock-sta` | `mac` | Unblock a client |
| `kick-sta` | `mac` | Disconnect a client |
| `authorize-guest` | `mac`, `minutes`, `up`, `down`, `bytes` | Authorize guest |
| `unauthorize-guest` | `mac` | Revoke guest access |

---

## 9. Devices (APs, Switches, Gateways)

### Query

| Endpoint | Method | Description |
|---|---|---|
| `stat/device-basic` | GET | Lightweight: mac, type, state |
| `stat/device` | GET | Full detail for all devices |
| `stat/device` | POST | Filter by MAC: `{"macs":["aa:bb:cc:dd:ee:ff"]}` |
| `stat/device/{mac}` | GET | Single device |

### Key Device Fields

`_id`, `mac`, `name`, `type` (`uap`/`usw`/`ugw`/`udm`), `model`, `version` (firmware), `state` (0=disconnected, 1=connected, 4=upgrading), `uptime`, `ip`, `satisfaction`, `radio_table` (APs), `port_table` (switches), `sys_stats` (CPU/RAM).

### Commands

POST to `cmd/devmgr`:

| Command | Fields | Description |
|---|---|---|
| `adopt` | `mac` | Adopt a device |
| `restart` | `mac` | Reboot |
| `force-provision` | `mac` | Re-push config |
| `upgrade` | `mac` | Upgrade firmware |
| `upgrade-external` | `mac`, `url` | Upgrade from URL |
| `set-locate` / `unset-locate` | `mac` | Blink/stop LED |
| `power-cycle` | `mac`, `port_idx` | Power-cycle PoE port |
| `speedtest` | — | Run WAN speed test |
| `speedtest-status` | — | Get speed test result |

### Update Device Settings

PUT to `rest/device/{_id}`:

Writable fields: `name`, `led_override` (`default`/`on`/`off`), `disabled`, `port_overrides` (switch ports).

---

## 10. WLANs / WiFi

| Operation | Method | Path |
|---|---|---|
| List | GET | `rest/wlanconf` |
| Create | POST | `rest/wlanconf` |
| Update | PUT | `rest/wlanconf/{_id}` |
| Delete | DELETE | `rest/wlanconf/{_id}` |

### Key Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | SSID |
| `enabled` | bool | Active |
| `security` | string | `open`, `wpapsk`, `wpaeap` |
| `x_passphrase` | string | WPA key (write-only — returned redacted) |
| `wpa_mode` | string | `wpa2`, `wpa3`, `wpa2/wpa3` |
| `networkconf_id` | string | Network/VLAN to assign clients to |
| `is_guest` | bool | Guest network |
| `l2_isolation` | bool | Client isolation |
| `hide_ssid` | bool | Hidden SSID |
| `fast_roaming_enabled` | bool | 802.11r |
| `mac_filter_enabled` | bool | MAC filtering |
| `mac_filter_list` | string[] | MAC addresses |
| `mac_filter_policy` | string | `allow` or `deny` |
| `wlan_band` | string | `both`, `2g`, `5g` |
| `schedule_enabled` | bool | Time-based SSID |

### AP Groups (v2)

| Operation | Method | Path |
|---|---|---|
| List | GET | `v2/api/site/default/apgroups` |
| Create | POST | `v2/api/site/default/apgroups` |
| Update | PUT | `v2/api/site/default/apgroups/{_id}` |

Body: `{"name": "Upstairs APs", "device_macs": ["aa:bb:cc:dd:ee:ff"]}`.

---

## 11. VPN

VPN configurations are stored as `rest/networkconf` entries with VPN-specific `purpose` and fields.

### VPN-Specific Fields on networkconf

| Field | Type | Description |
|---|---|---|
| `vpn_type` | string | `openvpn-server`, `openvpn-client`, `ipsec-vpn`, `wireguard-server`, `wireguard-client` |
| `ipsec_key_exchange` | string | `ikev1` or `ikev2` |
| `ipsec_peer_ip` | string | Remote peer IP |
| `x_ipsec_pre_shared_key` | string | PSK (write-only) |
| `openvpn_configuration` | string | Raw OpenVPN config (client mode) |
| `ip_subnet` | string | VPN tunnel subnet |
| `vpn_client_pull_dns` | bool | Push DNS to VPN clients |

### RADIUS

| Operation | Method | Path |
|---|---|---|
| List profiles | GET | `rest/radiusprofile` |
| Create profile | POST | `rest/radiusprofile` |
| List accounts | GET | `rest/account` |
| Create account | POST | `rest/account` |

---

## 12. Switch Port Profiles

| Operation | Method | Path |
|---|---|---|
| List | GET | `rest/portconf` |
| Create | POST | `rest/portconf` |
| Update | PUT | `rest/portconf/{_id}` |
| Delete | DELETE | `rest/portconf/{_id}` |

### Key Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Profile name |
| `forward` | string | `all`, `native`, `customize`, `disabled` |
| `native_networkconf_id` | string | Untagged VLAN network ID |
| `voice_networkconf_id` | string | VoIP VLAN network ID |
| `poe_mode` | string | `auto`, `passv24`, `passthrough`, `off` |
| `dot1x_ctrl` | string | 802.1X: `force_authorized`, `auto`, `mac_based` |
| `isolation` | bool | Port isolation |
| `stp_port_mode` | bool | Spanning Tree |
| `egress_rate_limit_kbps_enabled` | bool | Rate limiting |
| `egress_rate_limit_kbps` | int | Rate in kbps |
| `port_security_enabled` | bool | MAC-based security |
| `port_security_mac_addresses` | string[] | Allowed MACs |

### Per-Port Overrides

PUT to `rest/device/{switch_id}` with `port_overrides` array:

```json
{
  "port_overrides": [
    {
      "port_idx": 5,
      "name": "Camera",
      "portconf_id": "<profile_id>",
      "poe_mode": "auto"
    }
  ]
}
```

Only specified ports are overridden — others keep profile defaults.

---

## 13. DPI / Traffic Stats

| Endpoint | Method | Description |
|---|---|---|
| `stat/dpi` | GET | Site-wide DPI summary |
| `stat/sitedpi` | POST | By app or category: `{"type":"by_app"}` |
| `stat/stadpi` | POST | Per-client: `{"type":"by_app","macs":["..."]}` |
| `cmd/stat` | POST | Reset counters: `{"cmd":"clear-dpi"}` |

DPI must be enabled site-wide to get data.

---

## 14. Threat Management / IDS/IPS

### IPS Events

POST to `stat/ips/event`:

```json
{
  "start": 1700000000000,
  "end": 1700086400000,
  "_limit": 3000
}
```

Timestamps in **milliseconds**.

### IPS Settings

PUT to `rest/setting/ips/{_id}`:

| Field | Type | Description |
|---|---|---|
| `enabled` | bool | IPS on/off |
| `ips_mode` | string | `ids` (detect only) or `ips` (detect + block) |
| `sensitivity` | string | `low`, `medium`, `high` |
| `restrict_tor` | bool | Block Tor traffic |

---

## 15. System

### Settings

GET `get/setting` returns all settings grouped by key. Update with PUT to `rest/setting/{key}/{_id}`.

Key setting groups: `mgmt`, `connectivity`, `guest_access`, `country`, `locale`, `ntp`, `snmp`, `ips`.

### Events & Alerts

| Endpoint | Method | Description |
|---|---|---|
| `stat/event` | GET | Recent events (newest first, max 3000) |
| `stat/alarm` | GET | Active alerts |
| `cmd/evtmgt` | POST | `{"cmd":"archive-all-alarms"}` to dismiss all |

### Backups

POST to `cmd/backup`:

| Command | Description |
|---|---|
| `{"cmd":"backup","days":"-1"}` | Trigger backup |
| `{"cmd":"list-backups"}` | List backups |
| `{"cmd":"delete-backup","filename":"..."}` | Delete backup |

Download: GET `dl/backup?filepath=<filename>` (binary download).

### System Info

| Endpoint | Description |
|---|---|
| `stat/sysinfo` | Firmware, uptime, hostname |
| `stat/health` | Subsystem health (WAN, LAN, VPN) |

---

## 16. Hotspot / Guest Access

### Vouchers

POST to `cmd/hotspot`:

| Command | Key Fields | Description |
|---|---|---|
| `create-voucher` | `expire` (minutes), `n` (count), `quota` (uses, 0=unlimited), `note`, `up`/`down` (kbps), `bytes` (MB) | Create vouchers |
| `delete-voucher` | `_id` | Delete voucher |

List vouchers: GET `stat/voucher`.

### Guest Portal Settings

PUT to `rest/setting/guest_access/{_id}`:

Fields: `auth` (`none`/`password`/`hotspot`), `redirect_enabled`, `redirect_url`, `x_password`, `portal_enabled`, `voucher_enabled`.

---

## 17. Dynamic DNS

| Operation | Method | Path |
|---|---|---|
| Status | GET | `stat/dynamicdns` |
| Config | GET | `rest/dynamicdns` |
| Update | PUT | `rest/dynamicdns/{_id}` |

Fields: `service` (provider), `hostname`, `server`, `x_username`, `x_password`, `enabled`.

---

## Quick Reference

| Area | Primary Endpoint |
|---|---|
| Networks/VLANs | `rest/networkconf` |
| Firewall rules | `rest/firewallrule` |
| Firewall groups | `rest/firewallgroup` |
| Traffic rules (v2) | `v2/api/site/default/trafficrules` |
| Zone firewall | `integration/v1/sites/{id}/firewall/zones` |
| Port forwarding | `rest/portforward` |
| Static routes | `rest/routing` |
| Connected clients | `stat/sta` |
| All clients | `rest/user` |
| Client commands | `cmd/stamgr` |
| Devices | `stat/device` |
| Device commands | `cmd/devmgr` |
| WLANs | `rest/wlanconf` |
| AP groups (v2) | `v2/api/site/default/apgroups` |
| VPN | `rest/networkconf` (vpn_type) |
| RADIUS | `rest/radiusprofile` |
| Switch port profiles | `rest/portconf` |
| Port overrides | `rest/device/{id}` (port_overrides) |
| DPI stats | `stat/sitedpi` |
| IPS events | `stat/ips/event` |
| IPS settings | `rest/setting/ips/{id}` |
| Site settings | `get/setting` |
| Events/alerts | `stat/event`, `stat/alarm` |
| Backups | `cmd/backup` |
| System info | `stat/sysinfo`, `stat/health` |
| Vouchers | `cmd/hotspot`, `stat/voucher` |
| Guest portal | `rest/setting/guest_access/{id}` |
| Dynamic DNS | `rest/dynamicdns` |

## Global Gotchas

1. **PUT requires full object** — not partial. GET first, modify, PUT back.
2. **`/proxy/network` prefix is mandatory** on all UniFi OS devices.
3. **`x_` prefix = write-only secrets** — returned redacted. Track these yourself.
4. **v2 paths differ** — `v2/api/site/default/` not `api/s/default/`.
5. **`rest/` = config, `stat/` = live data, `cmd/` = commands**.
6. **IDs are MongoDB ObjectIds** — always GET before PUT.
7. **Zone-based firewall policy management is incomplete via API** — zone CRUD works, full policy matrix requires UI.
8. **Self-signed TLS** — always use `-k` / disable cert verification.
9. **Session auth needs local admin** — cloud/UI accounts don't work.
10. **Traffic rule PUT returns 201** not 200 — don't treat as error.
