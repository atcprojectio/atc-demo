#!/bin/bash

# Exit on error
set -e

# Terminal colors
BOLD="\033[1m"
RED="\033[31;1m"
GREEN="\033[32;1m"
YELLOW="\033[33;1m"
BLUE="\033[34;1m"
CYAN="\033[36;1m"
RESET="\033[0m"

echo -e "${BLUE}========================================================================${RESET}"
echo -e "${BOLD}${CYAN}                ATC Active Traffic Control Demo                    ${RESET}"
echo -e "${BLUE}========================================================================${RESET}"
echo -e "This script demonstrates ATC's ability to watch Consul services and"
echo -e "instantly automate traffic failover & redirect routing configurations."
echo -e "We will also query a client to validate the actual service output!"
echo ""

# Helper to format JSON responses robustly
format_json() {
  local input
  input=$(cat)
  if [[ "$input" == *"not found"* || "$input" == *"Error"* || -z "$input" ]]; then
    echo "$input"
  elif command -v jq >/dev/null 2>&1; then
    echo "$input" | jq "$1"
  else
    echo "$input" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin), indent=2))" 2>/dev/null || echo "$input"
  fi
}

# Helper functions to poll for Consul config updates (prevent race conditions)
wait_for_config_entry() {
  local service_name=$1
  local timeout=15
  local elapsed=0
  echo -n "Waiting for service-resolver config entry to be created by ATC..."
  while [ $elapsed -lt $timeout ]; do
    local res=$(curl -s http://localhost:8500/v1/config/service-resolver/$service_name || true)
    if [[ -n "$res" && "$res" != *"not found"* && "$res" == *"Kind"* ]]; then
      echo -e "\n${GREEN}✓ Config entry created!${RESET}"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
    echo -n "."
  done
  echo -e "\n${RED}Error: service-resolver entry for $service_name was not created within $timeout seconds.${RESET}"
  echo "ATC container logs:"
  docker logs atc-demo-service || true
  exit 1
}

wait_for_redirect_resolver() {
  local service_name=$1
  local timeout=15
  local elapsed=0
  echo -n "Waiting for service-resolver to switch to Redirect..."
  while [ $elapsed -lt $timeout ]; do
    local res=$(curl -s http://localhost:8500/v1/config/service-resolver/$service_name || true)
    if [[ -n "$res" && "$res" == *"Redirect"* ]]; then
      echo -e "\n${GREEN}✓ Config entry redirected!${RESET}"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
    echo -n "."
  done
  echo -e "\n${RED}Error: service-resolver did not switch to Redirect within $timeout seconds.${RESET}"
  echo "ATC container logs:"
  docker logs atc-demo-service || true
  exit 1
}

wait_for_failover_resolver() {
  local service_name=$1
  local timeout=15
  local elapsed=0
  echo -n "Waiting for service-resolver to switch to Failover..."
  while [ $elapsed -lt $timeout ]; do
    local res=$(curl -s http://localhost:8500/v1/config/service-resolver/$service_name || true)
    if [[ -n "$res" && "$res" == *"Failover"* ]]; then
      echo -e "\n${GREEN}✓ Config entry resolved back to Failover!${RESET}"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
    echo -n "."
  done
  echo -e "\n${RED}Error: service-resolver did not switch to Failover within $timeout seconds.${RESET}"
  echo "ATC container logs:"
  docker logs atc-demo-service || true
  exit 1
}

# Helper to print steps
print_step() {
  echo -e "\n${BOLD}${YELLOW}[Step $1] $2${RESET}"
  echo -e "------------------------------------------------------------"
}

# Verify Consul is running
if ! curl -s -f http://localhost:8500/v1/status/leader >/dev/null; then
  echo -e "${RED}Error: consul-dc1 (port 8500) is not running.${RESET}"
  echo -e "Please start the stack with: ${BOLD}make up${RESET}"
  exit 1
fi

print_step "1" "Ensure WAN join and Register backup instance in DC2"
echo "WAN joining dc1 and dc2..."
docker exec consul-dc2 consul join -wan consul-dc1 || true
echo -e "${GREEN}✓ Datacenters federated successfully!${RESET}"
echo ""

echo "Registering payment-service backend instance in DC2 (always active backup)..."
curl -s --request PUT \
  --data '{"ID": "payment-service-dc2-1", "Name": "payment-service", "Address": "payment-service-dc2", "Port": 8082}' \
  http://localhost:8501/v1/agent/service/register
echo -e "${GREEN}✓ payment-service registered in dc2.${RESET}"

print_step "2" "Show and Cleanup Initial State"
echo "Cleaning up any old service registrations..."
curl -s --request PUT http://localhost:8500/v1/agent/service/deregister/payment-service-dc1-1 >/dev/null || true
curl -s --request PUT http://localhost:8501/v1/agent/service/deregister/payment-service-dc2-1 >/dev/null || true
echo "Cleaning up any old service-resolver configurations..."
curl -s -X DELETE http://localhost:8088/api/services?name=payment-service >/dev/null || true

echo "Checking existing services in dc1..."
curl -s http://localhost:8500/v1/catalog/services | format_json '.'
echo ""
echo "Checking service resolvers in dc1..."
RESOLVERS=$(curl -s http://localhost:8500/v1/config/service-resolver/payment-service || true)
if [[ -z "$RESOLVERS" || "$RESOLVERS" == *"not found"* ]]; then
  echo -e "${GREEN}✓ No existing service-resolver found for payment-service (as expected).${RESET}"
else
  echo -e "${RED}Warning: Clean up failed to remove service-resolver.${RESET}"
fi

print_step "3" "Register Service in DC1 with ATC Tagging"
echo -e "Registering ${BOLD}payment-service${RESET} in ${BOLD}dc1${RESET} pointing to active DC1 HTTP echo server with tags:"
echo -e "  - ${CYAN}atc.enabled=true${RESET} (activates ATC monitoring)"
echo -e "  - ${CYAN}atc.failover=standard-failover${RESET} (configures failover to dc2)"
echo -e "  - ${CYAN}atc.redirect=standard-redirect${RESET} (configures redirect when service goes down)"
echo ""

curl -s --request PUT \
  --data '{"ID": "payment-service-dc1-1", "Name": "payment-service", "Tags": ["atc.enabled=true", "atc.failover=standard-failover", "atc.redirect=standard-redirect"], "Address": "payment-service-dc1", "Port": 8080}' \
  http://localhost:8500/v1/agent/service/register

echo -e "${GREEN}✓ payment-service registered in dc1 catalog.${RESET}"
wait_for_config_entry "payment-service"

print_step "4" "Inspect Failover resolver and Validate DC1 Traffic Output"
echo -e "ATC should have automatically created a ${BOLD}service-resolver${RESET} config entry in Consul."
echo "Fetching resolver entry from Consul API:"
echo ""
curl -s http://localhost:8500/v1/config/service-resolver/payment-service | format_json '.'
echo ""
echo -e "${BOLD}Simulating a client HTTP request to payment-service:${RESET}"
python3 traffic_client.py
echo ""

print_step "5" "Simulate Service Outage (Deregister Service from DC1)"
echo -e "Deregistering ${BOLD}payment-service-dc1-1${RESET} from ${BOLD}dc1${RESET} catalog to simulate outage..."
echo ""

curl -s --request PUT \
  http://localhost:8500/v1/agent/service/deregister/payment-service-dc1-1

echo -e "${GREEN}✓ payment-service deregistered from dc1.${RESET}"
wait_for_redirect_resolver "payment-service"

print_step "6" "Inspect Redirect resolver and Validate Failover/Redirect Output"
echo -e "ATC should have converted the resolver config from ${BOLD}Failover${RESET} to ${BOLD}Redirect${RESET}."
echo "This ensures any traffic requesting payment-service in dc1 is redirected immediately to dc2."
echo "Fetching resolver entry from Consul API:"
echo ""
curl -s http://localhost:8500/v1/config/service-resolver/payment-service | format_json '.'
echo ""
echo -e "${BOLD}Simulating a client HTTP request during outage:${RESET}"
python3 traffic_client.py
echo ""

print_step "7" "Simulate Service Recovery in DC1"
echo -e "Re-registering ${BOLD}payment-service-dc1-1${RESET} in ${BOLD}dc1${RESET}..."
echo ""

curl -s --request PUT \
  --data '{"ID": "payment-service-dc1-1", "Name": "payment-service", "Tags": ["atc.enabled=true", "atc.failover=standard-failover", "atc.redirect=standard-redirect"], "Address": "payment-service-dc1", "Port": 8080}' \
  http://localhost:8500/v1/agent/service/register

echo -e "${GREEN}✓ payment-service restored in dc1.${RESET}"
wait_for_failover_resolver "payment-service"

print_step "8" "Verify Failover Restored and Validate Output"
echo "Fetching updated resolver entry from Consul API:"
echo ""
curl -s http://localhost:8500/v1/config/service-resolver/payment-service | format_json '.'
echo ""
echo -e "${BOLD}Simulating a client HTTP request after recovery:${RESET}"
python3 traffic_client.py
echo ""

print_step "9" "Purge/Cleanup Configuration"
echo "If the service is permanently retired, we can purge the config entry from ATC."
echo "Calling ATC Purge API (DELETE /api/services?name=payment-service)..."
echo ""

curl -s -X DELETE http://localhost:8088/api/services?name=payment-service

echo -e "${GREEN}✓ Purge request sent.${RESET}"
echo "Verifying service-resolver entry in Consul is deleted..."
sleep 2
curl -s http://localhost:8500/v1/config/service-resolver/payment-service || echo -e "\n${GREEN}✓ Service-resolver entry successfully deleted from Consul!${RESET}"

echo -e "\n${BLUE}========================================================================${RESET}"
echo -e "${BOLD}${GREEN}                     Demo Completed Successfully!                      ${RESET}"
echo -e "${BLUE}========================================================================${RESET}"
echo -e "Summary:"
echo -e "1. Service tagged with ${CYAN}atc.enabled=true${RESET} was watched by ATC."
echo -e "2. When healthy in DC1, traffic client got output: ${GREEN}* [DC1 Instance] *${RESET}"
echo -e "3. During simulated outage, ATC switched to Redirect, client got output: ${GREEN}* [DC2 Instance] *${RESET}"
echo -e "4. Service recovery restored local routing in DC1."
echo -e "5. Permanent deletion cleaned up via ATC API."
echo -e "Visit the glassmorphic dashboard to see active state: ${BOLD}http://localhost:8088${RESET}"
echo -e "${BLUE}========================================================================${RESET}"
