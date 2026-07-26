# DESIGNED TO FAIL — proves upgrade_settings...enable_upgrade_drain.drain_max_unavailable_node_count
# validator Between(1, 5000) rejects 0 (< min). Run via verify.sh (not plain terraform test).
# mock_provider => no credentials; the real schema validator (see versions.tf for the pinned floor)
# fires at plan. reject-drain-count covers the UPPER bound; this file covers the lower one, so a
# regression that dropped the minimum from the validator cannot pass unnoticed.
mock_provider "xcsh" {}

run "reject_drain_count_under_min" {
  command = plan

  variables {
    probe_name            = "cov-probe-s8-drain-count-min"
    upgrade_drain_arm     = "enable_upgrade_drain"
    drain_max_unavailable = 0
    drain_node_timeout    = 300
  }
}
