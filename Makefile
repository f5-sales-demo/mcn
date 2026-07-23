# mcn CE-HA (BGP/ECMP) developer targets.

.PHONY: test fmt validate

# Run the plan-level test suite (no Azure/XC credentials; all providers mocked).
test:
	cd terraform && terraform test

# Format all Terraform files in place.
fmt:
	cd terraform && terraform fmt -recursive

# Config-validity check (no backend, no credentials).
validate:
	cd terraform && terraform init -backend=false && terraform validate
