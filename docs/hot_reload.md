# Scenario: Dynamic Configuration Hot-Reload

This scenario demonstrates ATC's ability to watch its configuration file (`atc-config.yaml`) and dynamically reload routing strategies and dampening thresholds at runtime without process restarts.

## 1. Start the Stack & Verify Initial State

1. **Start the Stack**:
   Ensure the core services are running:
   ```bash
   make up
   ```
2. **Register the Service**:
   Register `payment-service` in Consul DC1:
   ```bash
   make register
   ```
3. **Verify Initial Redirect Target**:
   Check the Consul configuration entry to confirm the default redirect target is `dc2`:
   ```bash
   make status-consul
   ```
   Under the `Redirect` field, you should see:
   ```json
   "Redirect": {
     "Datacenter": "dc2"
   }
   ```
4. **Simulate Outage**:
   Simulate an outage by removing the local service instance:
   ```bash
   make deregister
   ```
5. **Verify Redirect Routing**:
   Verify the Consul configuration entry shows the redirect is active:
   ```bash
   make status-consul
   ```
6. **Restore Service**:
   Restore the service instance back online:
   ```bash
   make register
   ```

## 2. Trigger Hot-Reload

1. Open `atc-config.yaml` in the root of the project.
2. Locate the redirect strategy section at the bottom:
   ```yaml
     redirect:
       standard-redirect:
         datacenter: "dc2"
   ```
3. Change the redirect target from `"dc2"` to `"dc3"`:
   ```yaml
     redirect:
       standard-redirect:
         datacenter: "dc3"
   ```
4. Save the file.
5. Inspect the container logs of `atc-dc1` to verify the hot-reload was triggered:
   ```bash
   make logs-atc | grep "Configuration reloaded"
   ```
   You should see a log entry similar to:
   ```json
   {"time":"...","level":"INFO","msg":"Configuration reloaded dynamically from file watcher","dry_run":false}
   ```

## 3. Verify Hot-Reloaded Configuration

1. Simulate an outage again:
   ```bash
   make deregister
   ```
2. Query Consul for the updated resolver configuration entry:
   ```bash
   make status-consul
   ```
   The configuration entry has dynamically updated to route traffic to the hot-reloaded target:
   ```json
   "Redirect": {
     "Datacenter": "dc3"
   }
   ```
3. Register the service back online and revert your changes in `atc-config.yaml` back to `"dc2"`.
4. **Teardown**:
   Stop and clean up all containers and volumes:
   ```bash
   make clean
   ```
