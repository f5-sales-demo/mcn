# DESIGNED TO FAIL — proves upgrade_settings...enable_upgrade_drain.drain_node_timeout validator
# Between(0, 900) rejects 901 (> max). Run via verify.sh (not plain terraform test). mock_provider =>
# no credentials; validator fires from the real provider schema at plan. upgrade_drain_arm=
# enable_upgrade_drain renders the drain leaves; drain_max_unavailable stays valid so only
# drain_node_timeout fails.
mock_provider "xcsh" {}

run "reject_drain_timeout_over_max" {
  command = plan

  variables {
    probe_name            = "cov-probe-s5-drain-timeout"
    upgrade_drain_arm     = "enable_upgrade_drain"
    drain_max_unavailable = 1
    drain_node_timeout    = 901
  }
}
