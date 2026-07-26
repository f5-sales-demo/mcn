# DESIGNED TO FAIL — proves load_balancing.vip_vrrp_mode validator OneOf(VIP_VRRP_INVALID,
# VIP_VRRP_ENABLE, VIP_VRRP_DISABLE) rejects an out-of-enum value. Run via verify.sh (not plain
# terraform test). mock_provider => no credentials; validator fires from the real provider schema at
# plan. A non-empty vip_vrrp_mode renders load_balancing so the leaf is reachable. vip_vrrp_mode has
# no terraform validation so the provider OneOf validator (not a variable check) fires.
mock_provider "xcsh" {}

run "reject_vip_vrrp_mode_out_of_enum" {
  command = plan

  variables {
    probe_name    = "cov-probe-s4-vrrp-bad"
    vip_vrrp_mode = "BOGUS"
  }
}
