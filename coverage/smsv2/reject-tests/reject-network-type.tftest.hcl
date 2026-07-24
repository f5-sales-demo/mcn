# DESIGNED TO FAIL — proves blocked_services.blocked_service.network_type validator
# OneOf(VIRTUAL_NETWORK_*) rejects an out-of-enum value. Run via verify.sh (not plain terraform
# test). mock_provider => no credentials; validator fires from the real v3.76.0 schema at plan.
# services_arm=blocked_services renders the blocked_service so the network_type leaf is reachable.
# blocked_network_type has no terraform validation so the provider OneOf validator fires.
mock_provider "xcsh" {}

run "reject_network_type_out_of_enum" {
  command = plan

  variables {
    probe_name           = "cov-probe-s4-nettype-bad"
    services_arm         = "blocked_services"
    blocked_network_type = "BOGUS"
  }
}
