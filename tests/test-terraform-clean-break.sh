#!/usr/bin/env bash

set -euo pipefail

repository_root=$(git rev-parse --show-toplevel)
terraform_root="$repository_root/terraform"

if rg -n '(data|resource)[[:space:]]+"xcsh_(registration|registration_approval|token)"|resource[[:space:]]+"azurerm_virtual_machine_extension"' \
  "$terraform_root" --glob '*.tf'; then
  echo "Terraform must use the Secure Mesh v2 issuance contract without legacy approvals, tokens, or post-boot VM extensions" >&2
  exit 1
fi

if find "$terraform_root" -type f \( -name '*registration_approval*' -o -name 'ce-node.yaml' \) -print -quit | grep -q .; then
  echo "Superseded registration-approval and static CE bootstrap artifacts must stay deleted" >&2
  exit 1
fi

grep -qF 'data "xcsh_site_image" "kvm"' "$terraform_root/kvm.tf" || {
  echo "KVM must obtain its F5 image through the generated site_image data source" >&2
  exit 1
}

grep -qF 'data.xcsh_site_image.kvm[0].image_download_url' "$terraform_root/kvm.tf" || {
  echo "KVM must consume the signed image URL returned by xcsh_site_image" >&2
  exit 1
}

grep -qF 'not_managed {' "$terraform_root/onprem_kvm.tf" || {
  echo "KVM must use the supported kvm.not_managed Secure Mesh v2 contract" >&2
  exit 1
}

if rg -n 'azure[[:space:]]*\{' "$terraform_root/onprem_kvm.tf"; then
  echo "KVM must not use an Azure-flavoured site contract" >&2
  exit 1
fi

grep -qF 'quay.io/frrouting/frr:10.7.0@sha256:65e5967b922572c0565d968388fb06af69d7e9b3b3eea40ad7e3810687667f68' "$terraform_root/kvm.tf" || {
  echo "KVM must use the verified immutable FRR image from the supported upstream registry" >&2
  exit 1
}

grep -qF 'alpine:3.22.1@sha256:4bcff63911fcb4448bd4fdacec207030997caf25e9bea4045fa6c8c44de311d1' "$terraform_root/kvm.tf" || {
  echo "KVM must pin the local test client image by digest" >&2
  exit 1
}

if [ "$(grep -cF 'keep_locally = false' "$terraform_root/kvm.tf")" -ne 2 ]; then
  echo "Terraform must own and remove both KVM container images" >&2
  exit 1
fi

if rg -n 'image[[:space:]]*=[[:space:]]*"frrouting/frr:|image[[:space:]]*=[[:space:]]*"[^"@]+:[^"@]+"' "$terraform_root/kvm.tf"; then
  echo "KVM must not use the unavailable Docker Hub FRR image or mutable container tags" >&2
  exit 1
fi

echo "Terraform clean-break contract is valid"
