.PHONY: compose-up compose-down tf-init tf-plan up down loadtest

# --- docker-compose (só para entender a app) --------------------------------

compose-up:
	docker compose up --build

compose-down:
	docker compose down -v

# --- Terraform (a entrega real) ---------------------------------------------

tf-init:
	cd infra/terraform && terraform init

tf-plan:
	cd infra/terraform && terraform plan

up:
	cd infra/terraform && terraform init -upgrade=false && terraform apply -auto-approve

down:
	cd infra/terraform && terraform destroy -auto-approve

# --- Bônus: teste de carga simples contra a API via Ingress -----------------

loadtest:
	./infra/loadtest/loadtest.sh
