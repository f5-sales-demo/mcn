variable "probe_name" {
  description = "Throwaway SMSv2 site name (fresh per run to avoid duplicate-StatusObject 500)."
  type        = string
  default     = "cov-probe-01"
}

variable "mtu" {
  description = "SLO interface MTU. Valid range per API: 0 or 512-16384 (S1 pushes out-of-range values)."
  type        = number
  default     = 1500
}

# NOTE: vlan_id / priority / proxy_port variables are intentionally NOT declared here.
# tflint (terraform_unused_declarations) rejects declared-but-unused variables. They are
# re-introduced in S1/S3 together with the vlan_interface and custom_proxy blocks that
# consume them (see the coverage plan Task 11), so declaration and use land together.
