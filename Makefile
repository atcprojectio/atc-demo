.PHONY: build pull up down join-wan register deregister register-dc2 client purge status-atc status-consul run-demo clean help

# Default target
all: help

help:
	@echo "ATC Demo Automation Tasks:"
	@echo "  make pull           - Pull the latest released ATC and Consul docker images"
	@echo "  make up             - Spin up the federated Consul, mock services, and ATC in background"
	@echo "  make down           - Stop all containers"
	@echo "  make join-wan       - Ensure WAN federation is connected between dc1 and dc2"
	@echo "  make register       - Register payment-service in dc1 (points to port 8080 mock container)"
	@echo "  make deregister     - Deregister payment-service from dc1"
	@echo "  make register-dc2   - Register payment-service in dc2 (points to port 8082 mock container)"
	@echo "  make client         - Execute the traffic_client.py routing query and print outputs"
	@echo "  make purge          - Delete/purge payment-service resolver entry from ATC"
	@echo "  make override-failover - Apply manual failover override targeting dc2"
	@echo "  make override-redirect - Apply manual redirect override targeting dc2"
	@echo "  make status-atc     - Show services list from ATC server"
	@echo "  make status-consul  - Query Consul DC1 for payment-service resolver config entry"
	@echo "  make run-demo       - Run the complete interactive CLI demo script"
	@echo "  make clean          - Stop containers and remove volumes"

pull:
	docker compose pull

up:
	docker compose up -d
	@echo "Waiting for services to start..."
	@sleep 3
	@make join-wan

down:
	docker compose down

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

status-consul:
	@curl -s http://localhost:8500/v1/config/service-resolver/payment-service | jq . 2>/dev/null || curl -s http://localhost:8500/v1/config/service-resolver/payment-service

run-demo:
	@chmod +x demo.sh
	@./demo.sh

clean:
	docker compose down -v
