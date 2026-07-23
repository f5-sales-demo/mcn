terraform {
  # Azure Blob Storage remote state, configured as a PARTIAL backend: no
  # environment-specific values are hardcoded here. Supply them at init time.
  #
  #   Local: terraform init -backend-config=backend.hcl   (copy backend.hcl.example; gitignored)
  #   CI:    terraform init -backend=false                (no state; config-validity + plan tests only)
  #
  # Auth is the storage account access key via the ARM_ACCESS_KEY environment
  # variable (never committed).
  backend "azurerm" {}
}
