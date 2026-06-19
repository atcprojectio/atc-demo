#!/usr/bin/env python3
import urllib.request
import json
import sys

def get_service_resolver():
    try:
        req = urllib.request.urlopen("http://localhost:8500/v1/config/service-resolver/payment-service", timeout=1)
        data = json.loads(req.read().decode('utf-8'))
        return data
    except Exception:
        return None

def get_healthy_instances(dc):
    port = 8500 if dc == "dc1" else 8501
    try:
        req = urllib.request.urlopen(f"http://localhost:{port}/v1/health/service/payment-service?passing=true", timeout=1)
        instances = json.loads(req.read().decode('utf-8'))
        return instances
    except Exception:
        return []

def make_request(port):
    url = f"http://localhost:{port}"
    try:
        req = urllib.request.urlopen(url, timeout=1)
        return req.read().decode('utf-8').strip()
    except Exception as e:
        return f"Error connecting to mock service on port {port}: {e}"

def route_request():
    resolver = get_service_resolver()
    
    # 1. Check if redirection is active
    if resolver and "Redirect" in resolver and resolver["Redirect"]:
        target_dc = resolver["Redirect"].get("Datacenter", "dc1")
        target_svc = resolver["Redirect"].get("Service", "payment-service")
        print(f"\033[34;1m[Traffic Router]\033[0m Redirect Rule Active -> Target DC: {target_dc}, Service: {target_svc}")
        if target_dc == "dc2":
            return make_request(8082)
        else:
            return make_request(8080)
            
    # 2. Check if failover is active
    if resolver and "Failover" in resolver and resolver["Failover"]:
        # Try local DC first (dc1)
        dc1_instances = get_healthy_instances("dc1")
        if dc1_instances:
            print("\033[34;1m[Traffic Router]\033[0m Local DC1 healthy -> Routing to payment-service in DC1...")
            return make_request(8080)
        else:
            # Failover to target DC
            targets = resolver["Failover"].get("*", {}).get("Targets", [])
            if targets:
                target_dc = targets[0].get("Datacenter", "dc2")
                print(f"\033[33;1m[Traffic Router]\033[0m DC1 instances OFFLINE -> Failing over to Datacenter: {target_dc}...")
                if target_dc == "dc2":
                    return make_request(8082)
            
    # 3. Default fallback routing
    dc1_instances = get_healthy_instances("dc1")
    if dc1_instances:
        print("\033[34;1m[Traffic Router]\033[0m Default Route -> Local DC1...")
        return make_request(8080)
    else:
        dc2_instances = get_healthy_instances("dc2")
        if dc2_instances:
            print("\033[34;1m[Traffic Router]\033[0m Default Route -> Local DC1 offline, fallback to DC2...")
            return make_request(8082)
        return "\033[31;1mError: No healthy instances of payment-service found in either DC1 or DC2!\033[0m"

if __name__ == "__main__":
    print(route_request())
