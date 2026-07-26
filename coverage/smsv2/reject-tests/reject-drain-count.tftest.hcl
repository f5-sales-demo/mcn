# DESIGNED TO FAIL — proves upgrade_settings...enable_upgrade_drain.drain_max_unavailable_node_count
# validator Between(1, 5000) rejects 5001 (> max). Run via verify.sh (not plain terraform test).
# mock_provider => no credentials; validator fires from the real provider schema at plan.
# upgrade_drain_arm=enable_upgrade_drain renders the drain leaves; drain_node_timeout stays valid so
# only drain_max_unavailable_node_count fails.
mock_provider "xcsh" {}

run "reject_drain_count_over_max" {
  command = plan

  variables {
    probe_name            = "cov-probe-s5-drain-count"
    upgrade_drain_arm     = "enable_upgrade_drain"
    drain_max_unavailable = 5001
    drain_node_timeout    = 300
  }
}
