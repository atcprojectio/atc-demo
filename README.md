# ATC (Active Traffic Control) Docker Demo

This project provides a self-contained, Docker-based demo environment to showcase **ATC**'s dynamic Consul traffic control, failover, and redirect orchestration capabilities.

## Architecture Overview

The demo environment spins up:
1. **`consul-dc1`**: The primary/local Consul agent representing datacenter `dc1`.
2. **`consul-dc2`**: A secondary/remote Consul agent representing datacenter `dc2`.
3. **WAN Federation**: The two Consul datacenters are connected via WAN.
4. **`atc`**: The primary Active Traffic Control service itself (port `8088`), running with HA enabled.
5. **`atc-backup`**: A secondary/backup Active Traffic Control service (port `8090`), running with HA enabled and sharing session locks with the primary.

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

## Web UI Dashboard

You can inspect the live state, tracked services, and failover status using ATC's glassmorphic React dashboard:
- **ATC Web UI**: [http://localhost:8088](http://localhost:8088)

You can also view the Consul UI for each datacenter:
- **Consul DC1 UI**: [http://localhost:8500](http://localhost:8500)
- **Consul DC2 UI**: [http://localhost:8501](http://localhost:8501)

---

## Available Make Tasks

| Command | Description |
|---|---|
| `make pull` | Pulls the latest released ATC and Consul docker images |
| `make build` | Alias for `make pull` |
| `make up` | Starts the Docker containers in the background and federates datacenters |
| `make down` | Stops the containers |
| `make join-wan` | Manually establishes Consul WAN federation |
| `make register` | Registers a test instance of `payment-service` in `dc1` |
| `make deregister` | Deregisters `payment-service` from `dc1` |
| `make override-failover` | Applies a manual failover override targeting `dc2` |
| `make override-redirect` | Applies a manual redirect override targeting `dc2` |
| `make purge` | Permanently purges the `payment-service` resolver from ATC |
| `make status-atc` | Outputs active modules and service tables from ATC CLI |
| `make status-consul` | Queries Consul for the current state of the resolver config entry |
| `make run-demo` | Executes the interactive CLI walkthrough |
| `make clean` | Shuts down containers and removes associated Docker volumes |

---

## Testing Hysteresis & Active-Passive HA

### 1. Hysteresis (Oscillation Dampening)
Run the automated test script to verify global default dampening, override tags, and oscillation debouncing:
```bash
python3 test_hysteresis.py
```

### 2. Active-Passive Failover
1. Query leadership endpoints:
   - Primary: `curl -s http://localhost:8088/api/leader`
   - Backup: `curl -s http://localhost:8090/api/leader`
2. One instance will report `{"leader":true}` and the other `{"leader":false}`.
3. Stop the active container (e.g. `docker stop atc-demo-backup` if the backup is the active leader).
4. Query the surviving container and verify it has taken over leadership (`{"leader":true}`).

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
