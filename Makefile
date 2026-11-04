# Makefile — lối tắt cho dev. Yêu cầu: ./scripts/bootstrap.sh đã chạy.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help setup check lint lint-all security security-full fmt hooks-update

help: ## Liệt kê target
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

setup: ## Cài toolchain (mise) + git hooks
	./scripts/bootstrap.sh

check: ## Kiểm tra toolchain đã đủ chưa
	./scripts/bootstrap.sh --check

lint: ## Chạy hook pre-commit trên file đã stage
	pre-commit run

lint-all: ## Chạy toàn bộ hook pre-commit trên mọi file (như CI)
	pre-commit run --all-files

security: ## gitleaks (staged) + trivy misconfig
	pre-commit run gitleaks trivy-misconfig --all-files

security-full: ## Quét như CI: gitleaks full history, trivy vuln+misconfig, govulncheck
	gitleaks git --redact --no-banner --verbose .
	TRIVY_SEVERITY=MEDIUM,HIGH,CRITICAL scripts/hooks/trivy-scan.sh vuln
	scripts/hooks/trivy-scan.sh misconfig
	govulncheck ./...

fmt: ## Format Go + TS
	golangci-lint fmt ./...
	-npx --no-install prettier --write .

hooks-update: ## Nâng rev các hook do pre-commit quản lý (tool system nâng ở mise.toml)
	pre-commit autoupdate
	pre-commit run --all-files
