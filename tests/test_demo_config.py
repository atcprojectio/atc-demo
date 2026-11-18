"""Static checks that keep the demo's script, Prometheus and Grafana config consistent."""
import json
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


DASHBOARD = "deploy/observability/grafana/provisioning/dashboards/atc-dashboard.json"


class DemoScriptTest(unittest.TestCase):
    def test_dc2_backup_stays_registered_until_retirement(self):
        """Step 1 registers the dc2 backup; nothing may deregister it before step 9 retires
        the service, or redirects point at a datacenter with no instances."""
        script = read("demo.sh")
        registered = script.index('"ID": "payment-service-dc2-1"')
        retirement = script.index('print_step "9"')
        for m in re.finditer(r"deregister/payment-service-dc2-1", script):
            self.assertFalse(registered < m.start() < retirement,
                             "payment-service-dc2-1 is deregistered after it was registered")


class ComposeTest(unittest.TestCase):
    def test_atc_uses_consul_container_port(self):
        """Inside the Docker network every Consul agent listens on 8500; ports like 8501 are
        only host mappings. atc-dc2 used consul-dc2:8501 and could never reach Consul."""
        compose = read("docker-compose.yml")
        addrs = re.findall(r"ATC_CONSUL_ADDR=http://([\w-]+):(\d+)", compose)
        self.assertEqual(3, len(addrs))
        for host, port in addrs:
            self.assertTrue(host.startswith("consul-"), host)
            self.assertEqual("8500", port, f"{host}:{port} is a host port, not reachable inside the network")


class PrometheusTest(unittest.TestCase):
    def test_every_atc_container_is_scraped(self):
        containers = re.findall(r"container_name:\s*(atc-[\w-]+)", read("docker-compose.yml"))
        self.assertIn("atc-dc1-backup", containers)
        scrape = read("deploy/observability/prometheus-config.yml")
        for name in containers:
            self.assertIn(f"'{name}:8089'", scrape, f"{name} must be scraped (HA failover hides its metrics otherwise)")


class DashboardTest(unittest.TestCase):
    def setUp(self):
        self.panels = {p["id"]: p for p in json.loads(read(DASHBOARD))["panels"]}

    def exprs(self, panel_id):
        return [t.get("expr", "") for t in self.panels[panel_id].get("targets", [])]

    def test_reconcile_rate_is_split_per_instance(self):
        for t in self.panels[1]["targets"]:
            self.assertIn("by (instance)", t["expr"])
            self.assertIn("{{instance}}", t["legendFormat"])

    def test_prometheus_queries_do_not_use_service_name(self):
        """ATC's Prometheus metrics carry module/otel_scope_name labels, not service_name."""
        for pid, panel in self.panels.items():
            if panel.get("type") == "logs":
                continue
            for expr in self.exprs(pid):
                if "atc_" in expr:
                    self.assertNotIn("service_name", expr, f"panel {pid}")

    def test_consul_panels_use_metrics_consul_exports(self):
        """Checked against a running demo: consul_api_http is a summary (no _bucket series) and
        consul_catalog_service does not exist."""
        exprs = " ".join(e for pid in self.panels for e in self.exprs(pid))
        self.assertNotIn("consul_api_http_bucket", exprs)
        self.assertNotIn("consul_catalog_service{", exprs)
        self.assertIn('consul_api_http{quantile="0.9", method=~"PUT|DELETE"}', exprs)
        self.assertIn("consul_state_service_instances", exprs)

    def test_consul_latency_panel_excludes_blocking_reads(self):
        """Blocking GETs (watches, the leader lock) are held open for minutes by design; a p90 that
        includes them showed ~15s on an idle demo. Only writes measure real API latency."""
        for pid in self.panels:
            for expr in self.exprs(pid):
                if "consul_api_http" in expr:
                    self.assertIn('method=~"PUT|DELETE"', expr, f"panel {pid}")

    def test_consul_metric_names_do_not_include_the_hostname(self):
        """Without disable_hostname, Consul prefixes gauges with the container ID
        (consul_<id>_state_service_instances), which changes on every recreate."""
        infra = read("docker-compose.infrastructure.yml")
        agents = re.findall(r"command: agent .*", infra)
        self.assertEqual(2, len(agents))
        for cmd in agents:
            self.assertIn("disable_hostname = true", cmd)

    def test_logs_panel_matches_atc_service_name(self):
        """ATC exports logs with service.name="atc" (telemetry.Init in the atc repo) unless
        OTEL_SERVICE_NAME overrides it; Loki's OTLP endpoint maps it to service_name."""
        compose = read("docker-compose.yml")
        m = re.search(r"OTEL_SERVICE_NAME=([\w-]+)", compose)
        service = m.group(1) if m else "atc"
        logs = [p for p in self.panels.values() if p.get("type") == "logs"]
        self.assertEqual(1, len(logs))
        for expr in self.exprs(logs[0]["id"]):
            self.assertIn(f'service_name="{service}"', expr)
            self.assertNotIn("| json", expr, "OTLP log bodies are plain text")


if __name__ == "__main__":
    unittest.main()
