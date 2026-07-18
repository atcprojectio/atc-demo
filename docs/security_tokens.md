# Scenario: Security & Token Delegation

This scenario demonstrates how to secure ATC's REST and MCP endpoints and authenticate client requests using static keys or delegated Consul ACL tokens.

> [!NOTE]
> **Consul Default Allow ACL Policy**:
> We are configuring Consul ACLs with `default_policy = "allow"` in the sandbox environment. 
> - **Why this is unconventional**: In production environments, ACLs are typically configured with `default_policy = "deny"` to establish a zero-trust environment where every client must present a valid token.
> - **Why we do it in the demo**: By setting it to `"allow"`, we ensure that all other test scenarios, scripts (`demo.sh`, `test_hysteresis.py`), and raw developer `curl` commands continue to work out-of-the-box without friction or token handling, while still allowing the authentication scenario to validate and reject invalid tokens.
> - **Production Recommendation**: For production setups, always enforce `default_policy = "deny"` to secure the Consul cluster properly.

## 1. Start the Stack & Verify Unsecured State

1. **Start the Stack**:
   Ensure the core services are running:
   ```bash
   make up
   ```
2. **Query the Unsecured API**:
   Query ATC's leader API endpoint:
   ```bash
   make status-leader
   ```
3. **Verify Open Access**:
   Verify that the response returns `200 OK` successfully without credentials:
   ```http
   HTTP/1.1 200 OK
   Content-Type: application/json

   {"leader":true}
   ```

## 2. Enable ATC Authentication

1. Open `atc-config.yaml` in the root of the project.
2. Locate the `auth` section:
   ```yaml
   # Native Authentication & Authorization (RBAC) settings
   auth:
     enabled: false
     static_keys:
       - "atc-super-secret-token"
     consul_token_delegation: true
   ```
3. Change `enabled` from `false` to `true`:
   ```yaml
   # Native Authentication & Authorization (RBAC) settings
   auth:
     enabled: true
     static_keys:
       - "atc-super-secret-token"
     consul_token_delegation: true
   ```
4. Save the file. (Wait a few seconds for the hot-reload watcher to apply the new configurations, or restart the container `docker compose restart atc-dc1`).

## 3. Verify Unauthorized Request

1. Attempt to query the API endpoint again without a token:
   ```bash
   make status-leader
   ```
2. The request is now rejected by ATC's security middleware, returning a `401 Unauthorized` status:
   ```http
   HTTP/1.1 401 Unauthorized
   Content-Type: application/json

   {"error":"unauthorized: missing token"}
   ```

## 4. Verify Static Key Authentication

1. Send the request passing the configured static key:
   ```bash
   make status-leader-static
   ```
2. Verify that the request is successfully authorized and returns `200 OK`.

## 5. Verify Consul Token Delegation

When a token is passed that is not in the `static_keys` list, and `consul_token_delegation` is set to `true`, ATC delegates token validation to the local Consul agent by verifying if the token has access to Consul.

1. Query the API passing the valid Consul ACL token:
   ```bash
   make status-leader-consul
   ```
2. Verify that ATC delegates the token validation to Consul, which authorizes it, returning `200 OK`.
3. Query the API passing an invalid/unknown token:
   ```bash
   make status-leader-invalid
   ```
4. Verify that Consul rejects the token delegation check, causing ATC to return `401 Unauthorized`:
   ```http
   HTTP/1.1 401 Unauthorized
   Content-Type: application/json

   {"error":"unauthorized: invalid token"}
   ```

## 6. Restore Configuration & Teardown

1. **Restore Config**:
   Revert `auth.enabled` back to `false` in `atc-config.yaml` to allow other scenarios to run token-free.
2. **Teardown**:
   Stop and clean up all containers and volumes:
   ```bash
   make clean
   ```
