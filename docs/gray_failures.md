# Scenario: Testing Gray Failures (Latency Simulation)

A gray failure happens when a service is technically healthy (its health check is green), but suffers from degraded performance (e.g., high latency). In this state, automatic health checks do not trigger failover, forcing slow requests onto clients.

Follow these steps to test manual redirection overrides during a simulated latency spike:

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
   - **Via Makefile**: Run `make override-redirect`
   - **Via UI**: Go to [http://localhost:8088](http://localhost:8088), open the override modal, and set a redirect to `dc2` for `15m`.
   - **Via MCP**: Instruct your AI client: *"Apply manual redirect override for payment-service to dc2 for 15m"*
5. **Verify Re-routing**:
   Run `make client` (without lag). Note that requests are immediately routed to `dc2` without touching the slow `dc1` instance.
6. **Recover**:
   Purge the override to return to normal automated state monitoring:
   ```bash
   make purge
   ```
7. **Teardown**:
   Stop and clean up all containers and observability resources:
   ```bash
   make clean
   ```
