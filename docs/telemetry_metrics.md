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
3. You will see the total number of reconciliation runs executed by `atc-dc1`, `atc-dc1-backup` and `atc-dc2` (one series per `instance`; the standby only counts while it leads).
4. Trigger a service state transition (e.g. reload or deregister):
   ```bash
   make deregister
   ```
5. Re-run the query in Prometheus. You should observe the counters incrementing to reflect the new loop iterations.

## 3. Monitor Live Traffic States in Grafana

1. Open your web browser and navigate to Grafana:
   [http://localhost:3000](http://localhost:3000)
   *(Note: Grafana is pre-configured with anonymous access, so no login credentials are required)*
2. In the Grafana menu, go to **Dashboards** and open **ATC Traffic Control & Observability**.
3. The dashboard has five panels:
   - **ATC Active Reconciliation Rate (runs/sec)**: forwarder and redirector reconciliation runs per second, one line per ATC instance.
   - **Reconciliation Duration (p95 milliseconds)**: 95th-percentile duration of forwarder and redirector reconciliation runs.
   - **Consul Registered Service Instances**: service instances registered in each datacenter's Consul.
   - **Consul API Write Latency (p90 ms)**: 90th-percentile latency of writes (PUT/DELETE) to each Consul agent's HTTP API, such as ATC's resolver writes and session renewals. Reads are left out because blocking queries (watches, the leader lock) hold the request open by design, which would make reads look slow.
   - **ATC System Reconciler & Override Audit Logs**: ATC's logs from Loki (`{service_name="atc"}`), including reconciliation, leadership and audit entries.
4. Traces are not on the dashboard: open **Explore**, pick the **Tempo** data source and search for service `atc` to follow reconciliation and API spans.
5. Re-register the service (`make register`) and watch the panels refresh to reflect the active primary path!

## 4. Teardown

Stop and clean up all containers and the observability stack:
```bash
make clean
```
