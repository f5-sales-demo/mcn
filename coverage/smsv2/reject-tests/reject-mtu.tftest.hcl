# DESIGNED TO FAIL — proves interface_list.mtu validator AtMost(16384) rejects >16384.
# One reject run per file: a failing run halts the rest of its own file, so each leaf gets
# its own file to guarantee its validator fires. Run via verify.sh (not plain terraform test).
# mock_provider => no credentials; validator fires from the real v3.75.0 schema at plan.
mock_provider "xcsh" {}

run "reject_mtu_over_max" {
  command = plan

  # mtu is AtMost(16384) ONLY (API rule {0} u [512,16384] has no single min), so the failing
  # value must EXCEED the max — a small value like 200 would NOT be rejected.
  variables {
    probe_name = "cov-probe-s1-mtu"
    mtu        = 20000
    priority   = 10
    vlan_id    = 100
    proxy_port = 8080
  }
}
