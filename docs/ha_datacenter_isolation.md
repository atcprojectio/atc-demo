# Scenario: Active-Passive HA & Datacenter Isolation

This scenario demonstrates how separate ATC instances coordinate and operate independently in federated environments.

## 1. Start the Stack

Ensure the core services are running:
```bash
make up
```

## 2. HA & Datacenter Isolation

Consul does not replicate its KV store across the WAN federation, so leader election is per datacenter. The demo runs three ATC containers:

| Container | Ports (API / metrics / MCP) | Consul | Role |
|---|---|---|---|
| `atc-dc1` | `8088` / `8089` / `8092` | `consul-dc1` | Competes for the dc1 leader locks |
| `atc-dc1-backup` | `8094` / `8095` / `8096` | `consul-dc1` | HA standby for dc1: competes for the same locks |
| `atc-dc2` | `8090` / `8091` / `8093` | `consul-dc2` | Controller for dc2, independent of dc1 |

- **Datacenter isolation:** `atc-dc1` and `atc-dc2` each hold the locks in their own datacenter, so both are leaders at the same time without conflict.
- **Active-passive HA in dc1:** `atc-dc1` and `atc-dc1-backup` compete for the dc1 locks (one per module: `atc/leader/lock/forwarder` and `atc/leader/lock/redirector`). One holds them; the other waits as standby.

Check who leads in dc1:
```bash
make status-leader          # atc-dc1
make status-leader-backup   # atc-dc1-backup
```
Exactly one of the two reports `"leader": true` for each module.

### Fail over to the standby
1. Stop the current dc1 leader (usually `atc-dc1`):
   ```bash
   make stop-primary
   ```
2. Within about one session TTL (15 seconds), the standby takes over:
   ```bash
   make status-leader-backup
   make logs-backup | grep "Leadership acquired"
   ```
3. Bring the primary back; it rejoins as standby:
   ```bash
   make start-primary
   make status-leader
   ```

## 3. WAN Federation Verification

1. Query the WAN federation endpoint:
   ```bash
   make status-federation
   ```
2. The response will list the datacenters and their connection status:
   ```json
   [{"datacenter":"dc1","status":"alive"},{"datacenter":"dc2","status":"alive"}]
   ```
3. Open the React UI at `http://localhost:8088` and verify that the target datacenters in the failover/redirect paths render with a green indicator (`●`), confirming they are WAN-federated and reachable.

## 4. Teardown

Stop and clean up all containers and volumes:
```bash
make clean
```
