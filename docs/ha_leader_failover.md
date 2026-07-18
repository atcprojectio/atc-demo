# Scenario: Local HA & Leader Failover Simulation

This scenario demonstrates how multiple ATC instances pointing to the same datacenter coordinate using Consul KV session locks to establish a resilient, active-passive controller group.

## 1. Verify Initial Leadership

1. Ensure the demo environment is running (including `atc-dc1-backup`):
   ```bash
   make up
   ```
2. Query the primary ATC instance (`atc-dc1` on port `8088`) to verify it holds the leader lock:
   ```bash
   make status-leader
   ```
   Output:
   ```json
   {"leader":true}
   ```
3. Query the standby ATC instance (`atc-dc1-backup` on port `8094`) to verify it is running in standby mode:
   ```bash
   make status-leader-backup
   ```
   Output:
   ```json
   {"leader":false}
   ```

## 2. Trigger Coordinator Failover

1. Stop the active primary container:
   ```bash
   make stop-primary
   ```
2. Monitor the logs of the standby instance to observe leadership promotion:
   ```bash
   make logs-backup
   ```
   You will see logs indicating that the Consul session lock was acquired and the controller is now active:
   ```text
   Consul leadership lock acquired, promoting node to active leader
   ```
3. Query the standby instance to confirm it has successfully promoted itself to leader:
   ```bash
   make status-leader-backup
   ```
   Output:
   ```json
   {"leader":true}
   ```

## 3. Restart Original Leader

1. Bring the original primary container back online:
   ```bash
   make start-primary
   ```
2. Query both nodes to verify that leadership remains stable on the promoted backup node and that the restarted node safely assumes standby mode:
   - Query `atc-dc1-backup`:
     ```bash
     make status-leader-backup
     ```
     Output: `{"leader":true}`
   - Query `atc-dc1`:
     ```bash
     make status-leader
     ```
     Output: `{"leader":false}`

## 4. Teardown

Stop and clean up all containers and volumes:
```bash
make clean
```
