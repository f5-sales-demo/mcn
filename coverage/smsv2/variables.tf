variable "probe_name" {
  description = "Throwaway SMSv2 site name (fresh per run to avoid duplicate-StatusObject 500)."
  type        = string
  default     = "cov-probe-01"
}

variable "mtu" {
  description = "SLO interface MTU. Provider validator: AtMost(16384) (API rule is 0 or 512-16384). S1 pushes >16384 to prove rejection."
  type        = number
  default     = 1500
}

variable "priority" {
  description = "eth0 interface priority. Provider validator: Between(0, 255). S1 pushes >255 to prove rejection."
  type        = number
  default     = 10
}

variable "vlan_id" {
  description = "vlan_interface VLAN tag. Provider validator: Between(1, 4095). S1 pushes >4095 to prove rejection."
  type        = number
  default     = 100
}

variable "proxy_port" {
  description = "custom_proxy port. Provider validator: Between(0, 65535). S1 pushes >65535 to prove rejection."
  type        = number
  default     = 8080
}

variable "extended_arms" {
  description = <<-EOT
    When true (default), the probe renders the S1 vlan_interface interface entry and the
    top-level custom_proxy block so the vlan_id and proxy_port numeric leaves are reachable
    at PLAN time (schema validators fire during plan under both mock_provider tests and live
    plans). Set false only for a live apply if the XC API rejects the vlan/proxy combination:
    the base eth0 interface (which carries the mtu and priority leaves) still applies live and
    stays idempotent/import-clean, while vlan_id/proxy_port remain plan-validated.
  EOT
  type        = bool
  default     = true
}
