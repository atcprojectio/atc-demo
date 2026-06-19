#!/usr/bin/env python3
import urllib.request
import json
import time
import sys

# Terminal colors
BOLD = "\033[1m"
RED = "\033[31;1m"
GREEN = "\033[32;1m"
YELLOW = "\033[33;1m"
BLUE = "\033[34;1m"
CYAN = "\033[36;1m"
RESET = "\033[0m"

def log(msg, color=RESET):
    print(f"{color}{msg}{RESET}")

def api_request(url, method="GET", data=None):
    try:
        req_data = json.dumps(data).encode('utf-8') if data else None
        headers = {"Content-Type": "application/json"} if data else {}
        req = urllib.request.Request(url, method=method, data=req_data, headers=headers)
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status, response.read().decode('utf-8')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8')
    except Exception as e:
        return 500, str(e)

def get_resolver():
    status, body = api_request("http://localhost:8500/v1/config/service-resolver/payment-service")
    if status == 200:
        return json.loads(body)
    return None

def clean_up():
    log("Cleaning up service registrations and resolver configuration...", YELLOW)
    api_request("http://localhost:8500/v1/agent/service/deregister/payment-service-dc1-1", method="PUT")
    api_request("http://localhost:8501/v1/agent/service/deregister/payment-service-dc2-1", method="PUT")
    api_request("http://localhost:8088/api/services?name=payment-service", method="DELETE")
    time.sleep(2)
    # Ensure payment-service is registered in dc2 as backup
    api_request("http://localhost:8501/v1/agent/service/register", method="PUT", data={
        "ID": "payment-service-dc2-1",
        "Name": "payment-service",
        "Address": "payment-service-dc2",
        "Port": 8082
    })
    log("Cleanup complete.", GREEN)

def register_dc1(tags):
    log(f"Registering payment-service in dc1 with tags: {tags}", BLUE)
    status, _ = api_request("http://localhost:8500/v1/agent/service/register", method="PUT", data={
        "ID": "payment-service-dc1-1",
        "Name": "payment-service",
        "Tags": tags,
        "Address": "payment-service-dc1",
        "Port": 8080
    })
    if status != 200:
        log("Failed to register service in dc1", RED)
        sys.exit(1)

def deregister_dc1():
    log("Deregistering payment-service from dc1...", BLUE)
    status, _ = api_request("http://localhost:8500/v1/agent/service/deregister/payment-service-dc1-1", method="PUT")
    if status != 200:
        log("Failed to deregister service from dc1", RED)
        sys.exit(1)

def wait_for_resolver_state(expected_kind, timeout=12):
    """Waits for resolver to match expected state (e.g. 'Failover' or 'Redirect') and returns elapsed time."""
    start = time.time()
    while time.time() - start < timeout:
        res = get_resolver()
        if res:
            if expected_kind == "Failover" and "Failover" in res and res["Failover"]:
                return time.time() - start
            if expected_kind == "Redirect" and "Redirect" in res and res["Redirect"]:
                return time.time() - start
            if expected_kind == "None" and ("Redirect" not in res or not res["Redirect"]) and ("Failover" not in res or not res["Failover"]):
                return time.time() - start
        elif expected_kind == "Deleted":
            return time.time() - start
        time.sleep(0.1)
    return None

def test_global_dampening():
    log("\n=== Test 1: Global Default Dampening (5s) ===", BOLD + CYAN)
    clean_up()
    
    # We register with NO atc.dampening tag, so it should default to 5s.
    tags = ["atc.enabled=true", "atc.failover=standard-failover", "atc.redirect=standard-redirect"]
    register_dc1(tags)
    
    log("Waiting for resolver to become Failover...", YELLOW)
    elapsed = wait_for_resolver_state("Failover", timeout=10)
    if elapsed is None:
        log("FAIL: Resolver did not transition to Failover within 10s", RED)
        return False
    
    log(f"Resolver transitioned to Failover in {elapsed:.2f} seconds.", GREEN)
    if 4.0 <= elapsed <= 6.5:
        log("SUCCESS: Global dampening of 5s respected (took ~5s).", GREEN)
        return True
    else:
        log(f"FAIL: Global dampening of 5s not respected (took {elapsed:.2f}s instead).", RED)
        return False

def test_immediate_dampening():
    log("\n=== Test 2: Tag Override with 0s (Immediate) ===", BOLD + CYAN)
    clean_up()
    
    # We register with atc.dampening=0s tag, so it should update immediately.
    tags = ["atc.enabled=true", "atc.failover=standard-failover", "atc.redirect=standard-redirect", "atc.dampening=0s"]
    register_dc1(tags)
    
    log("Waiting for resolver to become Failover...", YELLOW)
    elapsed = wait_for_resolver_state("Failover", timeout=5)
    if elapsed is None:
        log("FAIL: Resolver did not transition to Failover within 5s", RED)
        return False
        
    log(f"Resolver transitioned to Failover in {elapsed:.2f} seconds.", GREEN)
    if elapsed < 2.0:
        log("SUCCESS: 0s dampening tag respected (took <2s).", GREEN)
        return True
    else:
        log(f"FAIL: 0s dampening tag not respected (took {elapsed:.2f}s instead).", RED)
        return False

def test_custom_dampening():
    log("\n=== Test 3: Tag Override with 2s Custom Dampening ===", BOLD + CYAN)
    clean_up()
    
    # We register with atc.dampening=2s tag, so it should take 2s.
    tags = ["atc.enabled=true", "atc.failover=standard-failover", "atc.redirect=standard-redirect", "atc.dampening=2s"]
    register_dc1(tags)
    
    log("Waiting for resolver to become Failover...", YELLOW)
    elapsed = wait_for_resolver_state("Failover", timeout=6)
    if elapsed is None:
        log("FAIL: Resolver did not transition to Failover within 6s", RED)
        return False
        
    log(f"Resolver transitioned to Failover in {elapsed:.2f} seconds.", GREEN)
    if 1.5 <= elapsed <= 3.5:
        log("SUCCESS: 2s custom dampening tag respected.", GREEN)
        return True
    else:
        log(f"FAIL: 2s custom dampening tag not respected (took {elapsed:.2f}s instead).", RED)
        return False

def test_flapping_debounce():
    log("\n=== Test 4: Flapping and Oscillation Debouncing ===", BOLD + CYAN)
    clean_up()
    
    # Register initially to have a baseline Failover configuration
    # We'll use 0s dampening to establish baseline immediately
    tags = ["atc.enabled=true", "atc.failover=standard-failover", "atc.redirect=standard-redirect", "atc.dampening=5s"]
    register_dc1(["atc.enabled=true", "atc.failover=standard-failover", "atc.redirect=standard-redirect", "atc.dampening=0s"])
    wait_for_resolver_state("Failover")
    log("Baseline established (Failover active immediately).", GREEN)
    
    # Now re-register with 5s dampening so subsequent transitions use 5s
    register_dc1(tags)
    time.sleep(1) # Let the active state settle
    
    log("\nStarting flapping sequence:", YELLOW)
    # 1. Deregister (should want Redirect)
    deregister_dc1()
    
    # 2. Wait 1.5s, then Register again (should cancel Redirect write, want Failover)
    time.sleep(1.5)
    log("Service recovered during dampening period...", YELLOW)
    register_dc1(tags)
    
    # 3. Wait 1.5s, then Deregister again (should cancel Failover write, want Redirect)
    time.sleep(1.5)
    log("Service failed again during dampening period...", YELLOW)
    deregister_dc1()
    
    # Now let's watch and measure from the LAST failure (step 3)
    log("Watching for final Redirect transition. Intermediate transitions should have been debounced...", YELLOW)
    start_watch = time.time()
    elapsed = wait_for_resolver_state("Redirect", timeout=10)
    
    if elapsed is None:
        log("FAIL: Resolver did not transition to Redirect", RED)
        return False
        
    total_since_start_watch = time.time() - start_watch
    log(f"Resolver transitioned to Redirect in {total_since_start_watch:.2f} seconds after the last flap.", GREEN)
    
    # The elapsed time since last failure should be around 5s (the dampening period)
    if 4.0 <= total_since_start_watch <= 6.5:
        log("SUCCESS: Flapping debounced successfully! Intermediate writes canceled, final target written after full dampening.", GREEN)
        return True
    else:
        log(f"FAIL: Dampening since last flap was not respected (took {total_since_start_watch:.2f}s).", RED)
        return False

def main():
    log("=== RUNNING ATC HYSTERESIS INTEGRATION TESTS ===", BOLD + YELLOW)
    success = True
    success &= test_global_dampening()
    success &= test_immediate_dampening()
    success &= test_custom_dampening()
    success &= test_flapping_debounce()
    
    clean_up()
    
    if success:
        log("\n=== ALL INTEGRATION TESTS PASSED ===", BOLD + GREEN)
        sys.exit(0)
    else:
        log("\n=== SOME INTEGRATION TESTS FAILED ===", BOLD + RED)
        sys.exit(1)

if __name__ == "__main__":
    main()
