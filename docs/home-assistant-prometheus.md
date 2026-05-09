# Home Assistant — Pi metrics as entities

Each Pi exposes Prometheus-format metrics on `:9100` already (`modules/observability.nix`). The simplest path is to have HA scrape those endpoints directly — no Prometheus server needed.

## What you get

For each Pi: CPU temperature, available RAM, uptime, and a `binary_sensor` per monitored service. ~20 entities for the current 3-Pi setup, viewable on a Lovelace dashboard, usable in automations ("notify me if dns1.coredns goes down").

## Setup

Drop the following into HA's `configuration.yaml` (or split into packages if you prefer). Adjust IPs as needed.

### System metrics — `command_line` sensors

```yaml
sensor:
  # CPU temperature (°C). awk grabs the first thermal_zone reading.
  - platform: command_line
    name: dns1 cpu temp
    command: >
      curl -s --max-time 5 http://192.168.96.45:9100/metrics
      | awk '/^node_thermal_zone_temp{/ {print $NF; exit}'
    unit_of_measurement: "°C"
    scan_interval: 60

  - platform: command_line
    name: dns2 cpu temp
    command: >
      curl -s --max-time 5 http://192.168.96.60:9100/metrics
      | awk '/^node_thermal_zone_temp{/ {print $NF; exit}'
    unit_of_measurement: "°C"
    scan_interval: 60

  - platform: command_line
    name: kitchen-music cpu temp
    command: >
      curl -s --max-time 5 http://192.168.96.157:9100/metrics
      | awk '/^node_thermal_zone_temp{/ {print $NF; exit}'
    unit_of_measurement: "°C"
    scan_interval: 60

  # Available RAM (MB).
  - platform: command_line
    name: dns1 ram available
    command: >
      curl -s --max-time 5 http://192.168.96.45:9100/metrics
      | awk '/^node_memory_MemAvailable_bytes/ {printf "%.0f", $NF/1024/1024; exit}'
    unit_of_measurement: "MB"
    scan_interval: 60

  # Uptime (seconds since boot — derived from now - boot_time).
  - platform: command_line
    name: dns1 uptime
    command: >
      curl -s --max-time 5 http://192.168.96.45:9100/metrics
      | awk '/^node_time_seconds / {now=$NF} /^node_boot_time_seconds / {boot=$NF} END {printf "%.0f", now-boot}'
    unit_of_measurement: "s"
    device_class: duration
    scan_interval: 300
```

### Service health — `binary_sensor` per service

`node_exporter`'s systemd collector emits one row per (service × state). Match the `name="X.service",state="active"` row and grab the value (1 = active, 0 = otherwise).

```yaml
binary_sensor:
  # dns1 — DNS trio
  - platform: command_line
    name: dns1 coredns
    command: >
      curl -s --max-time 5 http://192.168.96.45:9100/metrics
      | grep -m1 '^node_systemd_unit_state{name="coredns.service",state="active"'
      | awk '{print $NF}'
    payload_on: "1"
    payload_off: "0"
    device_class: running
    scan_interval: 30

  - platform: command_line
    name: dns1 adguardhome
    command: >
      curl -s --max-time 5 http://192.168.96.45:9100/metrics
      | grep -m1 '^node_systemd_unit_state{name="adguardhome.service",state="active"'
      | awk '{print $NF}'
    payload_on: "1"
    payload_off: "0"
    device_class: running
    scan_interval: 30

  - platform: command_line
    name: dns1 unbound
    command: >
      curl -s --max-time 5 http://192.168.96.45:9100/metrics
      | grep -m1 '^node_systemd_unit_state{name="unbound.service",state="active"'
      | awk '{print $NF}'
    payload_on: "1"
    payload_off: "0"
    device_class: running
    scan_interval: 30
```

Repeat the trio for `dns2` (`192.168.96.60`) and `kitchen-music` (`192.168.96.157`). Same pattern.

### A quick reachability binary_sensor (no node_exporter needed)

For the simplest "is the box up?" check, ping it:

```yaml
binary_sensor:
  - platform: ping
    name: dns1
    host: 192.168.96.45
    count: 2
    scan_interval: 30
```

(Built-in HA integration; don't even need to scrape the metrics endpoint for this.)

## Lovelace example

```yaml
type: vertical-stack
cards:
  - type: entities
    title: dns1
    entities:
      - binary_sensor.dns1
      - binary_sensor.dns1_coredns
      - binary_sensor.dns1_adguardhome
      - binary_sensor.dns1_unbound
      - sensor.dns1_cpu_temp
      - sensor.dns1_ram_available
      - sensor.dns1_uptime
```

Repeat per host.

## Automations

Once these entities exist, the obvious wins:

```yaml
automation:
  - alias: Notify if dns resolver down
    trigger:
      - platform: state
        entity_id:
          - binary_sensor.dns1_coredns
          - binary_sensor.dns2_coredns
        to: "off"
        for: "00:01:00"   # debounce against transient blips
    action:
      - service: notify.mobile_app_<your_device>
        data:
          message: "{{ trigger.entity_id }} is down"

  - alias: Warn on Pi temperature
    trigger:
      - platform: numeric_state
        entity_id:
          - sensor.dns1_cpu_temp
          - sensor.dns2_cpu_temp
          - sensor.kitchen_music_cpu_temp
        above: 75
    action:
      - service: persistent_notification.create
        data:
          message: "{{ trigger.entity_id }} hit {{ trigger.to_state.state }}°C"
```

## Trade-offs vs. running Prometheus

You don't get: long-term history (HA recorder is ~10 days vs Prometheus 30+), PromQL/aggregations, Grafana dashboards, alert routing via Alertmanager. For a 3-Pi homelab, you almost certainly don't care about any of that yet.

**If you ever do care**, the upgrade path is non-destructive: stand up Prometheus on Tower (snippet at the bottom), point it at the same `:9100` endpoints, and your HA sensors keep working. Grafana then layers on for proper dashboards.

---

## Appendix: upgrading to Prometheus + Grafana later

If/when you want history + dashboards, add Prometheus to `thenairn.com`'s docker-compose:

```yaml
prometheus:
  image: prom/prometheus:latest
  container_name: prometheus
  restart: unless-stopped
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.retention.time=30d'
    - '--storage.tsdb.path=/prometheus'
    - '--web.enable-lifecycle'
  volumes:
    - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    - prometheus_data:/prometheus
  ports:
    - "9090:9090"
```

`./prometheus/prometheus.yml`:

```yaml
global:
  scrape_interval: 30s

scrape_configs:
  - job_name: 'homelab-pis'
    static_configs:
      - targets:
          - '192.168.96.45:9100'
          - '192.168.96.60:9100'
          - '192.168.96.157:9100'
```

Add Grafana the same way (port 3001 — 3000 conflicts with AdGuard's UI), point it at `http://prometheus:9090`, import dashboard 1860 (Node Exporter Full).

For HA's own state in Prometheus: enable the built-in `prometheus:` integration in `configuration.yaml`, generate a long-lived access token, and add HA as a scrape target with the bearer token.
