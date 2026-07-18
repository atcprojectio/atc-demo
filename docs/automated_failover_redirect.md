# Scenario: Automated Failover & Redirect Demo

This scenario demonstrates ATC's ability to watch Consul services and instantly automate traffic failover & redirect routing configurations during service state transitions.

The automated `make run-demo` script runs through the following sequence:

1. **WAN federation validation**: Ensures `consul-dc1` and `consul-dc2` are federated.
2. **Service Registration**: Registers `payment-service` in `dc1` with `atc.enabled=true` and custom failover/redirect tags.
3. **Failover Setup**: Demonstrates how ATC immediately detects the new service and registers a `service-resolver` config entry in Consul with a `Failover` block pointing to `dc2`.
4. **Outage Simulation**: Deregisters the service from `dc1`.
5. **Redirection Setup**: Demonstrates how ATC instantly converts the `service-resolver` into a `Redirect` config entry targeting `dc2`, instantly routing client traffic to the remote datacenter.
6. **Recovery**: Re-registers the service in `dc1` and shows that ATC restores the `Failover` configuration.
7. **Clean up**: Deletes the service-resolver config entry from Consul via ATC's Purge API.

## How to Run

1. **Start the Stack**:
   Ensure the core services are running:
   ```bash
   make up
   ```
2. **Execute the Demo**:
   Execute the interactive CLI demo script to see the sequence run:
   ```bash
   make run-demo
   ```
3. **Teardown**:
   Stop and clean up all containers:
   ```bash
   make clean
   ```
