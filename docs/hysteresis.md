# Scenario: Hysteresis (Oscillation Dampening)

This scenario demonstrates ATC's ability to debounce rapid service health flapping, protecting Consul's configuration engine from excessive write churn.

## How to Run

1. **Start the Stack**:
   Ensure the core services are running:
   ```bash
   make up
   ```
2. **Execute the Flapping Simulator**:
   Run the automated test script to verify global default dampening, override tags, and oscillation debouncing:
   ```bash
   make test-hysteresis
   ```
3. **Teardown**:
   Stop and clean up all containers and volumes:
   ```bash
   make clean
   ```
