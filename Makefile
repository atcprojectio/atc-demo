.PHONY: build pull up down join-wan register deregister register-dc2 client client-laggy purge status-atc status-consul run-demo up-obs down-obs up-infra down-infra up-atc down-atc clean help test-hysteresis status-federation logs-atc logs-backup stop-primary start-primary status-leader status-leader-backup status-leader-static status-leader-consul status-leader-invalid status-metrics override-failover override-redirect

# Default target
all: help

help:
	@echo "ATC Demo Automation Tasks:"
	@echo "  make pull           - Pull the latest released ATC and Consul docker images"
	@echo "  make up             - Spin up the federated Consul, mock services, and ATC in background"
	@echo "  make down           - Stop all containers"
	@echo "  make up-obs         - Start the LGTM observability stack (Grafana, Prometheus, Loki, Tempo)"
	@echo "  make down-obs       - Stop the LGTM observability stack"
	@echo "  make up-infra       - Spin up Consul and mock services only (no ATC containers)"
	@echo "  make down-infra     - Stop and remove Consul and mock services"
	@echo "  make up-atc         - Start the ATC container instances"
	@echo "  make down-atc       - Stop and remove the ATC container instances"
	@echo "  make join-wan       - Ensure WAN federation is connected between dc1 and dc2"
	@echo "  make register       - Register payment-service in dc1 (points to port 8080 mock container)"
	@echo "  make deregister     - Deregister payment-service from dc1"
	@echo "  make register-dc2   - Register payment-service in dc2 (points to port 8082 mock container)"
	@echo "  make client         - Execute the traffic_client.py routing query and print outputs"
	@echo "  make client-laggy   - Run traffic_client.py with mock late entry from ATC"
	@echo "  make override-failover - Apply manual failover override targeting dc2"
	@echo "  make override-redirect - Apply manual redirect override targeting dc2"
	@echo "  make status-atc     - Show services list from ATC server"
	@echo "  make status-federation - Query ATC WAN federation status"
	@echo "  make status-leader  - Query leadership status of the primary ATC node"
	@echo "  make status-metrics - Query exposed Prometheus metrics for ATC"
	@echo "  make test-hysteresis - Run the automated flapping hysteresis test script"
	@echo "  make status-consul  - Query Consul DC1 for payment-service resolver config entry"
	@echo "  make run-demo       - Run the complete interactive CLI demo script"
	@echo "  make clean          - Stop all containers and remove associated volumes"

pull:
	docker compose pull

up:
	docker compose up -d
	@echo "Waiting for services to start..."
	@sleep 3
	@make join-wan

up-infra:
	docker compose up -d consul-dc1 consul-dc2 payment-service-dc1 payment-service-dc2
	@echo "Waiting for infrastructure to start..."
	@sleep 3
	@make join-wan

down-infra:
	docker compose rm -fsv consul-dc1 consul-dc2 payment-service-dc1 payment-service-dc2

up-atc:
	docker compose up -d atc-dc1 atc-dc2

down-atc:
	docker compose rm -fsv atc-dc1 atc-dc2

down:
	docker compose down
	@docker compose -f ./deploy/observability/docker-compose.observability.yml down --remove-orphans 2>/dev/null || true

up-obs:
	@docker network inspect atc-demo_demo-net >/dev/null 2>&1 || docker network create atc-demo_demo-net || true
	docker compose -f ./deploy/observability/docker-compose.observability.yml up -d

down-obs:
	docker compose -f ./deploy/observability/docker-compose.observability.yml down

join-wan:
	docker exec consul-dc2 consul join -wan consul-dc1 || true

register:
	curl -s --request PUT \
		--data '{"ID": "payment-service-dc1-1", "Name": "payment-service", "Tags": ["atc.enabled=true", "atc.failover=standard-failover", "atc.redirect=standard-redirect"], "Address": "payment-service-dc1", "Port": 8080}' \
		http://localhost:8500/v1/agent/service/register
	@echo "\nRegistered payment-service-dc1-1 in dc1 (pointing to port 8080 mock)"

deregister:
	curl -s --request PUT \
		http://localhost:8500/v1/agent/service/deregister/payment-service-dc1-1
	@echo "\nDeregistered payment-service-dc1-1 from dc1"

register-dc2:
	curl -s --request PUT \
		--data '{"ID": "payment-service-dc2-1", "Name": "payment-service", "Address": "payment-service-dc2", "Port": 8082}' \
		http://localhost:8501/v1/agent/service/register
	@echo "\nRegistered payment-service-dc2-1 in dc2 (pointing to port 8082 mock)"

client:
	@python3 traffic_client.py

client-laggy:
	@SIMULATE_DC1_LATENCY=true python3 traffic_client.py

purge:
	curl -s -X DELETE http://localhost:8088/api/services?name=payment-service
	@echo "\nSent purge request to ATC for payment-service"

override-failover:
	curl -s -X POST -H "Content-Type: application/json" -d '{"service":"payment-service","type":"failover","target_dc":"dc2"}' http://localhost:8088/api/overrides
	@echo "\nApplied manual failover override targeting dc2"

override-redirect:
	curl -s -X POST -H "Content-Type: application/json" -d '{"service":"payment-service","type":"redirect","target_dc":"dc2"}' http://localhost:8088/api/overrides
	@echo "\nApplied manual redirect override targeting dc2"

status-atc:
	curl -s http://localhost:8088/services

status-federation:
	@curl -s http://localhost:8088/api/federation

logs-atc:
	@docker logs atc-dc1

logs-backup:
	@docker logs atc-dc1-backup

stop-primary:
	docker compose stop atc-dc1

start-primary:
	docker compose start atc-dc1

status-leader:
	@curl -i http://localhost:8088/api/leader

status-leader-backup:
	@curl -i http://localhost:8094/api/leader

status-leader-static:
	@curl -i -H "Authorization: Bearer atc-super-secret-token" http://localhost:8088/api/leader

status-leader-consul:
	@curl -i -H "X-Consul-Token: atc-consul-master-token" http://localhost:8088/api/leader

status-leader-invalid:
	@curl -i -H "X-Consul-Token: some-bad-token" http://localhost:8088/api/leader

status-metrics:
	@curl -s http://localhost:8089/metrics | grep "atc_"

test-hysteresis:
	@python3 test_hysteresis.py

status-consul:
	@curl -s http://localhost:8500/v1/config/service-resolver/payment-service | jq . 2>/dev/null || curl -s http://localhost:8500/v1/config/service-resolver/payment-service

run-demo:
	@chmod +x demo.sh
	@./demo.sh

clean:
	docker compose down -v
	docker compose -f ./deploy/observability/docker-compose.observability.yml down -v --remove-orphans 2>/dev/null || true
