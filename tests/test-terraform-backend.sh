#!/usr/bin/env bash

set -euo pipefail

repository_root=$(git rev-parse --show-toplevel)
backend_tf="$repository_root/terraform/backend.tf"
backend_example="$repository_root/terraform/backend.hcl.example"

grep -qF 'backend "azurerm" {}' "$backend_tf" || {
  echo "terraform/backend.tf must declare the partial azurerm backend" >&2
  exit 1
}

grep -Eq '^[[:space:]]*key[[:space:]]*=[[:space:]]*"mcn-nextgen\.tfstate"[[:space:]]*$' "$backend_example" || {
  echo "terraform/backend.hcl.example must select mcn-nextgen.tfstate" >&2
  exit 1
}

if grep -Eq '^[[:space:]]*key[[:space:]]*=[[:space:]]*"mcn\.tfstate"[[:space:]]*$' "$backend_example"; then
  echo "terraform/backend.hcl.example must not select the superseded state key" >&2
  exit 1
fi

echo "Terraform Azure backend contract is valid"
