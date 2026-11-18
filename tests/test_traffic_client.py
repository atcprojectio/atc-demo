"""Tests for the demo traffic client's routing decisions (no network)."""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import traffic_client  # noqa: E402

REDIRECT_DC2 = {"Redirect": {"Datacenter": "dc2", "Service": "payment-service"}}
FAILOVER_DC2 = {"Failover": {"*": {"Targets": [{"Service": "payment-service", "Datacenter": "dc2"}]}}}


class RouteRequestTest(unittest.TestCase):
    def route(self, resolver, healthy):
        with mock.patch.object(traffic_client, "get_service_resolver", return_value=resolver), \
             mock.patch.object(traffic_client, "get_healthy_instances", side_effect=lambda dc: healthy.get(dc, [])), \
             mock.patch.object(traffic_client, "make_request", side_effect=lambda port: f"called {port}") as req, \
             mock.patch("builtins.print"):
            return traffic_client.route_request(), req

    def test_redirect_to_dc_without_healthy_instances_fails(self):
        result, req = self.route(REDIRECT_DC2, healthy={"dc1": [], "dc2": []})
        self.assertIn("no healthy instances", result)
        req.assert_not_called()

    def test_redirect_to_healthy_dc_is_served(self):
        result, _ = self.route(REDIRECT_DC2, healthy={"dc2": [{"Service": {}}]})
        self.assertEqual("called 8082", result)

    def test_failover_prefers_healthy_local_dc(self):
        result, _ = self.route(FAILOVER_DC2, healthy={"dc1": [{"Service": {}}]})
        self.assertEqual("called 8080", result)


if __name__ == "__main__":
    unittest.main()
