# Home Assistant + Prometheus integration

End-to-end recipe for getting metrics from this repo's Pis (and HA itself) into HA dashboards via Prometheus.

## Architecture

```
   Pis (node_exporter :9100)         HA (built-in /api/prometheus)
              │                                  │
              └─────────────┬────────────────────┘
                            ▼
                    Prometheus (Tower :9090)
                            │
              ┌─────────────┴────────────────────┐
              ▼                                  ▼
        Grafana (optional)             HA `command_line` sensors
        for dashboards                 for entities + automations
```

- **node_exporter** is already running on every Pi via `modules/observability.nix` — exposes `:9100/metrics`. No changes here.
- **Prometheus** runs as a single container on Tower, scrapes every endpoint on a schedule, stores metrics for the configured retention window.
- **HA** publishes its own state at `https://hass.local:8123/api/prometheus` once the integration is enabled — Prometheus scrapes that too.
- **Grafana** is the standard way to visualize. Skip it for the first pass; add it once you have data flowing.
- **HA sensors** for individual values you want as entities (binary_sensor, gauge etc.) — pull from Prometheus's HTTP query API.

## 1. Tower side: add Prometheus to the stack

In `thenairn.com`'s docker-compose, add:

```yaml
prometheus:
  image: prom/prometheus:latest
  container_name: prometheus
  restart: unless-stopped
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.retention.time=30d'
    - '--storage.tsdb.path=/prometheus'
    - '--web.enable-lifecycle'   # for `curl -X POST :9090/-/reload`
  volumes:
    - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    - prometheus_data:/prometheus
  ports:
    - "9090:9090"
  networks:
    - default
```

And in your volumes section:

```yaml
volumes:
  prometheus_data:
```

Then create `./prometheus/prometheus.yml`:

```yaml
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  # The three Pis running node_exporter. Same module, same :9100.
  - job_name: 'homelab-pis'
    static_configs:
      - targets:
          - '192.168.96.45:9100'    # dns1
          - '192.168.96.60:9100'    # dns2
          - '192.168.96.157:9100'   # kitchen-music
        labels:
          environment: 'homelab'

  # Home Assistant — exports its own state when the prometheus integration
  # is enabled. Replace with your HA host/IP.
  - job_name: 'home-assistant'
    metrics_path: /api/prometheus
    bearer_token: 'YOUR_LONG_LIVED_ACCESS_TOKEN'
    static_configs:
      - targets:
          - '192.168.96.15:8123'    # adjust if HA is elsewhere
```

### Generate HA's bearer token

In HA UI: **Profile → Security → Long-Lived Access Tokens → Create Token**. Paste the result into `bearer_token` above. Don't commit it; keep that file out of git.

### Sanity check after `docker compose up -d prometheus`

- Visit `http://tower.thenairn.com:9090/targets` (or `:9090/targets` directly). All four targets should be `UP`.
- If a Pi shows `DOWN`, check that node_exporter is reachable: `curl http://192.168.96.45:9100/metrics | head`.
- If HA is `DOWN`, double-check the bearer token and that `prometheus:` is in HA's `configuration.yaml` (next section).

## 2. HA side: enable the built-in Prometheus integration

In `configuration.yaml`:

```yaml
prometheus:
  namespace: hass
  filter:
    # Optional: scope what gets exposed. Default is everything, which is
    # fine for a homelab. Comment this out to expose all entities.
    include_domains:
      - sensor
      - binary_sensor
      - climate
      - light
      - switch
      - device_tracker
```

Restart HA. Verify with:

```sh
curl -H "Authorization: Bearer YOUR_TOKEN" http://192.168.96.15:8123/api/prometheus | head -20
```

Should return Prometheus-format metrics (`hass_sensor_value{...}`, etc.).

## 3. HA-side sensors for headline metrics

This is where you decide what's worth being a *first-class HA entity* (vs. just-visible-in-Grafana). Examples:

```yaml
# configuration.yaml — add to existing `sensor:` and `binary_sensor:` lists.

sensor:
  # CPU temperature on each Pi.
  - platform: command_line
    name: kitchen_music_cpu_temp
    command: >
      curl -s 'http://tower.thenairn.com:9090/api/v1/query?query=node_thermal_zone_temp{instance="192.168.96.157:9100"}'
      | jq -r '.data.result[0].value[1] // "unavailable"'
    unit_of_measurement: "°C"
    scan_interval: 60

  - platform: command_line
    name: dns1_cpu_temp
    command: >
      curl -s 'http://tower.thenairn.com:9090/api/v1/query?query=node_thermal_zone_temp{instance="192.168.96.45:9100"}'
      | jq -r '.data.result[0].value[1] // "unavailable"'
    unit_of_measurement: "°C"
    scan_interval: 60

binary_sensor:
  # Per-service health for the DNS trio.
  - platform: command_line
    name: dns1_coredns_active
    command: >
      curl -s 'http://tower.thenairn.com:9090/api/v1/query?query=node_systemd_unit_state{instance="192.168.96.45:9100",name="coredns.service",state="active"}'
      | jq -r '.data.result[0].value[1] // "0"'
    payload_on: "1"
    payload_off: "0"
    device_class: running
    scan_interval: 30
```

Repeat for each `(host, service)` you care about. Or — far cleaner — once you have a handful of these, switch to a **template** that loops over them. Or use the **HACS `prometheus_sensor`** integration, which is purpose-built for this.

## 4. Optional: Grafana for real dashboards

Add to docker-compose:

```yaml
grafana:
  image: grafana/grafana:latest
  container_name: grafana
  restart: unless-stopped
  volumes:
    - grafana_data:/var/lib/grafana
  ports:
    - "3001:3000"   # 3000 conflicts with AdGuard's UI on the Pis
  networks:
    - default
```

Add Prometheus as a data source: `http://prometheus:9090` (from inside the docker network). Import the official dashboards:

- **1860** — Node Exporter Full (the canonical Pi/server dashboard)
- **15983** — Home Assistant overview

Optionally, embed Grafana into HA via the *Iframe Card* on a Lovelace dashboard.

## Things this doesn't cover (yet)

- **Alerting** — Alertmanager could send notifications (HA, ntfy, etc.) when something goes off. Add only when you find yourself wishing for it.
- **Long-term storage** — Prometheus's local TSDB is fine for 30 days; if you want years, look at VictoriaMetrics or Mimir.
- **Cardinality control** — `hass_*` metrics include a label per entity, which can balloon. The `filter:` in step 2 keeps it sane.
- **Scrape security** — node_exporter and HA's metrics endpoint are unauthenticated on LAN. Acceptable for an internal homelab; fix with mTLS or a reverse proxy if exposing externally.
