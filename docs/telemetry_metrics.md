# Scenario: Telemetry & Observability (Prometheus/Grafana)

This scenario demonstrates how to query raw Prometheus metric counters and navigate the pre-configured Grafana dashboard to monitor traffic routing states, logs, and traces.

## 1. Generating Telemetry Signals

1. Ensure the demo environment and observability stack are running:
   ```bash
   make up
   make up-obs
   ```
2. Register the service in dc1 and dc2:
   ```bash
   make register
   make register-dc2
   ```
3. Run the traffic client in the background or execute multiple queries to generate active telemetry spans and metrics:
   ```bash
   make client
   ```

## 2. Inspect Raw Metrics in Prometheus

1. Open your web browser and navigate to the Prometheus Web Console:
   [http://localhost:9090](http://localhost:9090)
2. In the query expression field, type `atc_forwarder_reconcile_runs_total` and click **Execute**.
3. You will see the total number of watcher reconciliation runs executed by `atc-dc1` and `atc-dc2`.
4. Trigger a service state transition (e.g. reload or deregister):
   ```bash
   make deregister
   ```
5. Re-run the query in Prometheus. You should observe the counters incrementing to reflect the new loop iterations.

## 3. Monitor Live Traffic States in Grafana

1. Open your web browser and navigate to Grafana:
   [http://localhost:3000](http://localhost:3000)
   *(Note: Grafana is pre-configured with anonymous access, so no login credentials are required)*
2. In the Grafana menu, go to **Dashboards** and select the pre-configured **Active Traffic Control (ATC) Dashboard**.
4. The dashboard displays:
   - **Active Traffic Path**: A real-time topology layout showing whether traffic for `payment-service` is routed to DC1 (primary) or redirected/failed-over to DC2 (standby).
   - **Reconciliation Loop Latency**: Histograms capturing the exact execution time of ATC's forwarder and redirector sweeps.
   - **Structured Logs Panel**: Captures logs parsed dynamically from container stdin streams via Loki, showing routing overrides and coordinator leader promotions in real-time.
   - **Distributed Traces Panel**: Links directly to Tempo to trace distributed requests across Consul and backend endpoints.
5. Re-register the service (`make register`) and watch the panels refresh to reflect the active primary path!

## 4. Teardown

Stop and clean up all containers and the observability stack:
```bash
make clean
```
