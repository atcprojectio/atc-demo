# Scenario: Active-Passive HA & Datacenter Isolation

This scenario demonstrates how separate ATC instances coordinate and operate independently in federated environments.

## 1. Start the Stack

Ensure the core services are running:
```bash
make up
```

## 2. HA & Datacenter Isolation

Since Consul does not replicate its KV store across the WAN federation, each ATC instance operates independently within its respective datacenter's control plane:
- **Primary (`atc` at port `8088`)** connects to `consul-dc1` and acquires the session lock in `dc1` to become the active controller for `dc1` (`make status-leader` returns `{"leader":true}`).
- **Backup (`atc-backup` at port `8090`)** connects to `consul-dc2` and acquires the session lock in `dc2` to become the active controller for `dc2` (querying the `dc2` leader status returns `{"leader":true}`).
- If you were to run a second replica pointing to the same datacenter (e.g. `consul-dc1`), the two instances would compete for the lock in that KV store, establishing a local active-passive standby relationship.

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
