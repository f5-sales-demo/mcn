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

variable "vlan_id" {
  description = "VLAN id for a vlan_interface arm (1-4095). Wired for S3 interface oneof coverage."
  type        = number
  default     = 100
}

variable "priority" {
  description = "Interface priority (0-255). Wired for S1/S3 coverage."
  type        = number
  default     = 10
}

variable "proxy_port" {
  description = "custom_proxy proxy_port (0-65535). Wired for S3 forward-proxy coverage."
  type        = number
  default     = 8080
}
