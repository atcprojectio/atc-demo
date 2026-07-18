# Scenario: Testing Manual Overrides

You can manually bypass automated watcher loops by applying custom routing overrides.

1. **Start the Stack**:
   Ensure the core services are running:
   ```bash
   make up
   ```
2. **Apply a Manual Override**:
   ```bash
   make override-failover
   ```
3. **Verify Consul Config**:
   Check Consul to confirm that the resolver config entry is written with `"created-by": "atc-override"`:
   ```bash
   make status-consul
   ```
4. **Test Loop Bypass**:
   Try registering or deregistering the service. Notice that ATC's logs show the reconciler skips reconciling the service because an active manual override is in place.
5. **Recover**:
   To remove the manual override and restore automated watcher reconciliation, purge the configuration entry:
   ```bash
   make purge
   ```
6. **Teardown**:
   Stop and clean up all containers and volumes:
   ```bash
   make clean
   ```
