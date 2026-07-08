# ATC (Active Traffic Control) Docker Demo

This project provides a self-contained, Docker-based demo environment to showcase **ATC**'s dynamic Consul traffic control, failover, and redirect orchestration capabilities.

## Architecture Overview

The demo environment spins up:
1. **`consul-dc1`**: The primary Consul agent representing datacenter `dc1`.
2. **`consul-dc2`**: The secondary Consul agent representing datacenter `dc2`.
3. **WAN Federation**: The two Consul datacenters are connected via WAN.
4. **`atc`**: The Active Traffic Control daemon for `dc1` (port `8088`), configured to connect to `consul-dc1`.
5. **`atc-backup`**: The Active Traffic Control daemon for `dc2` (port `8090`), configured to connect to `consul-dc2`.

> [!TIP]
> **Production Deployments**:
> While this demo is Docker Compose-based, production-ready configurations for Kubernetes (Helm) and Nomad are available in the main repository's [deploy](file:///Users/attachmentgenie/DevShed/Projects/atcprojectio/atc/deploy) directory.

---

## Quick Start

### 1. Pull the Docker Images
First, pull the latest released ATC and Consul docker images:
```bash
make pull
```

### 2. Start the Stack
Spin up the two Consul nodes and the ATC service:
```bash
make up
```

### 3. Run the Automated Demo
Execute the interactive CLI demo script to see ATC failover/redirection in action:
```bash
make run-demo
```

---

## Detailed Demo Flow

The `make run-demo` script runs through the following sequence:

1. **WAN federation validation**: Ensures `consul-dc1` and `consul-dc2` are federated.
2. **Service Registration**: Registers `payment-service` in `dc1` with `atc.enabled=true` and custom failover/redirect tags.
3. **Failover Setup**: Demonstrates how ATC immediately detects the new service and registers a `service-resolver` config entry in Consul with a `Failover` block pointing to `dc2`.
4. **Outage Simulation**: Deregisters the service from `dc1`.
5. **Redirection Setup**: Demonstrates how ATC instantly converts the `service-resolver` into a `Redirect` config entry targeting `dc2`, instantly routing client traffic to the remote datacenter.
6. **Recovery**: Re-registers the service in `dc1` and shows that ATC restores the `Failover` configuration.
7. **Clean up**: Deletes the service-resolver config entry from Consul via ATC's Purge API.

---

## Web UI & Observability Dashboards

You can inspect the live state, tracked services, and failover status using the UI dashboards:
- **ATC Web UI**: [http://localhost:8088](http://localhost:8088) (glassmorphic React dashboard)
- **Consul DC1 UI**: [http://localhost:8500](http://localhost:8500)
- **Consul DC2 UI**: [http://localhost:8501](http://localhost:8501)
- **Grafana**: [http://localhost:3000](http://localhost:3000) (pre-configured dashboard visualizing reconciliation rates, loop execution times, Consul latency, and Loki override logs)

---

## Available Make Tasks

| Command | Description |
|---|---|
| `make pull` | Pulls the latest released ATC and Consul docker images |
| `make build` | Alias for `make pull` |
| `make up` | Starts the Docker containers in the background and federates datacenters |
| `make down` | Stops the containers and the observability stack |
| `make up-obs` | Starts the LGTM observability stack (Grafana, Prometheus, Loki, Tempo) |
| `make down-obs` | Stops the LGTM observability stack |
| `make join-wan` | Manually establishes Consul WAN federation |
| `make register` | Registers a test instance of `payment-service` in `dc1` |
| `make deregister` | Deregisters `payment-service` from `dc1` |
| `make override-failover` | Applies a manual failover override targeting `dc2` |
| `make override-redirect` | Applies a manual redirect override targeting `dc2` |
| `make purge` | Permanently purges the `payment-service` resolver from ATC |
| `make status-atc` | Outputs active modules and service tables from ATC CLI |
| `make status-consul` | Queries Consul for the current state of the resolver config entry |
| `make client` | Runs the traffic routing client |
| `make client-laggy` | Runs the traffic client with 800ms mock latency on DC1 requests (simulates gray failure) |
| `make run-demo` | Executes the interactive CLI walkthrough |
| `make clean` | Shuts down containers, teardown observability stack, and removes all volumes |

---

## Testing Gray Failures (Latency Simulation)

A gray failure happens when a service is technically healthy (its health check is green), but suffers from degraded performance (e.g., high latency). In this state, automatic health checks do not trigger failover, forcing slow requests onto clients.

1. **Start the Stack and Observability**:
   ```bash
   make up
   make up-obs
   ```
2. **Register the Service**:
   ```bash
   make register
   ```
3. **Simulate a Gray Failure**:
   Run the traffic client with mock latency:
   ```bash
   make client-laggy
   ```
   Open Grafana at `http://localhost:3000` to observe the spike in Consul API request latency on the dashboard.
4. **Remediate (Manual Override)**:
   Bypass the automated health check by applying a manual redirect to `dc2`:
   - **Via UI**: Go to [http://localhost:8088](http://localhost:8088), open the override modal, and set a redirect to `dc2` for `15m`.
   - **Via MCP**: Instruct your AI client: *"Apply manual redirect override for payment-service to dc2 for 15m"*
5. **Verify Re-routing**:
   Run `make client` (without lag). Note that requests are immediately routed to `dc2` without touching the slow `dc1` instance.
6. **Recover**:
   Purge the override to return to normal automated state monitoring:
   ```bash
   make purge
   ```

---

## Testing Hysteresis & Active-Passive HA

### 1. Hysteresis (Oscillation Dampening)
Run the automated test script to verify global default dampening, override tags, and oscillation debouncing:
```bash
python3 test_hysteresis.py
```

### 2. HA & Datacenter Isolation
Since Consul does not replicate its KV store across the WAN federation, each ATC instance operates independently within its respective datacenter's control plane:
- **Primary (`atc` at port `8088`)** connects to `consul-dc1` and acquires the session lock in `dc1` to become the active controller for `dc1` (`curl -s http://localhost:8088/api/leader` returns `{"leader":true}`).
- **Backup (`atc-backup` at port `8090`)** connects to `consul-dc2` and acquires the session lock in `dc2` to become the active controller for `dc2` (`curl -s http://localhost:8090/api/leader` returns `{"leader":true}`).
- If you were to run a second replica pointing to the same datacenter (e.g. `consul-dc1`), the two instances would compete for the lock in that KV store, establishing a local active-passive standby relationship.

### 3. WAN Federation Verification
1. Query the WAN federation endpoint on either instance:
   ```bash
   curl -s http://localhost:8088/api/federation
   ```
2. The response will list the datacenters and their connection status:
   ```json
   [{"datacenter":"dc1","status":"alive"},{"datacenter":"dc2","status":"alive"}]
   ```
3. Open the React UI at `http://localhost:8088` and verify that the target datacenters in the failover/redirect paths render with a green indicator (`●`), confirming they are WAN-federated and reachable.

---

## Testing Manual Overrides

You can manually bypass automated watcher loops by applying custom routing overrides.

1. Apply a manual override:
   ```bash
   make override-failover
   ```
2. Check Consul to confirm that the resolver config entry is written with `"created-by": "atc-override"`:
   ```bash
   make status-consul
   ```
3. Try registering or deregistering the service. Notice that ATC's logs show the reconciler skips reconciling the service because an active manual override is in place.
4. To remove the manual override and restore automated watcher reconciliation, purge the configuration entry:
   ```bash
   make purge
   ```
```
